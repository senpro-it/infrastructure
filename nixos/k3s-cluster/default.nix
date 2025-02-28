{ config, pkgs, lib, ... }:

with lib;

{
  options = {
    senpro-it = {
      k3s-cluster = {
        enable = mkEnableOption ''
          Whether to enable k3s cluster functionalities.
        '';
        init = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Initialize HA cluster using an embedded etcd datastore.

            If this option is `false` and `role` is `server`

            On a server that was using the default embedded sqlite backend,
            enabling this option will migrate to an embedded etcd DB.

            If an HA cluster using the embedded etcd datastore was already initialized,
            this option has no effect.

            This option only makes sense in a server that is not connecting to another server.

            If you are configuring an HA cluster with an embedded etcd,
            the 1st server must have `init = true`
            and other servers must connect to it using `serverAddress`.
          '';
        };
        role = mkOption {
          type = types.enum [ "server" "agent" ];
          default = "server";
          description = ''
            Whether k3s should run as a server or agent.

            If it's a server:

            - By default it also runs workloads as an agent.
            - Starts by default as a standalone server using an embedded sqlite datastore.
            - Configure `init = true` to switch over to embedded etcd datastore and enable HA mode.
            - Configure `server.address` to join an already-initialized HA cluster.

            If it's an agent:

            - `server.address` is required.
          '';
        };
        metallb = {
          enable = mkEnableOption ''
            Should the MetalLB load balancer be used?
          '';
          addressRange = mkOption {
            type = types.str;
            description = ''
              IP range which MetalLB should use to advertise services.
            '';
            example = "192.168.178.20-192.168.178.40";
          };
        };
        nodeExternalIp = mkOption {
          default = "";
          type = types.str;
          description = lib.mkDoc ''
            Use this when MetalLB is disabled to specify a dedicated
            external IP. You must pick this manually.
          '';
        };
        nfs = {
          enable = mkEnableOption ''
            Should the cluster be configured to use an NFS storage?
          '';
          server = mkOption {
            type = types.str;
            default = "127.0.0.1";
            description = ''
              The NFS server to connect to. Can be either an IPv4 address or an FQDN.
            '';
            example = "192.168.178.1";
          };
          directory = mkOption {
            type = types.path;
            default = "/";
            description = ''
              Target directory at the server which should be mounted.
            '';
            example = "/mnt/example";
          };
        };
        server = {
          address = mkOption {
            type = types.str;
            default = "";
            description = ''
              The k3s server to connect to.

              Servers and agents need to communicate each other. Read
              [the networking docs](https://rancher.com/docs/k3s/latest/en/installation/installation-requirements/#networking)
              to know how to configure the firewall.
            '';
            example = "https://10.0.0.10:6443";
          };
          token = mkOption {
            type = types.str;
            default = "";
            description = ''
              The k3s token to use when connecting to a server.

              WARNING: This option will expose store your token unencrypted world-readable in the nix store.
              If this is undesired use the tokenFile option instead.
            '';
          };
        };
        extraFlags = mkOption {
          type = types.listOf types.str;
          default = [];
          description = ''
            List of additional arguments to be passed to k3s at start, appeneded at the end.
            This can be used to sneak in customizations not covered by this configuration.
            An example is to use --bind-adress=0.0.0.0 to change how the Kubelet listens for
            incomming traffic, making it accessible to the entire network.

            Copy /etc/rancher/k3s/k3s.yaml into your local .kube folder as "config" to access a host
            that has been exposed this way.
          '';
        };
      };
    };
  };

  config = (lib.mkIf config.senpro-it.k3s-cluster.enable {
    environment.systemPackages = with pkgs; [
      kubectl
    ];
    environment.variables = {
      KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
    };
    networking = {
      firewall = {
        allowedTCPPorts 
          = if config.senpro-it.k3s-cluster.role == "server" then [ 6443 10250 ] else [ 10250 ]
          + (if !config.senpro-it.k3s-cluster.metallb.enable then [ 80 443 ] else [ 7946 ]);
        allowedTCPPortRanges = mkIf (config.senpro-it.k3s-cluster.role == "server") [
          { from = 2379; to = 2380; }
        ];
        allowedUDPPorts = [ 8472 51820 ];
      };
    };
    services.k3s = {
      enable = true;
      role = "${config.senpro-it.k3s-cluster.role}";
      clusterInit = config.senpro-it.k3s-cluster.init;
      serverAddr = if config.senpro-it.k3s-cluster.init == false then "${config.senpro-it.k3s-cluster.server.address}" else "";
      token = if config.senpro-it.k3s-cluster.init == false then "${config.senpro-it.k3s-cluster.server.token}" else "";
      extraFlags =
        (
          if config.senpro-it.k3s-cluster.role == "server" 
          then (lib.concatStringsSep " " [
            "--flannel-backend=host-gw"
            "--container-runtime-endpoint unix:///run/containerd/containerd.sock"
            "--kube-controller-manager-arg node-monitor-period=5s"
            "--kube-controller-manager-arg node-monitor-grace-period=20s"
            (
              if config.senpro-it.k3s-cluster.metallb.enable
              then "--disable=servicelb"
              else "--node-external-ip ${config.senpro-it.k3s-cluster.nodeExternalIp}"
            )
          ])
          else ""
        ) + " " + (lib.concatStringsSep " " config.senpro-it.k3s-cluster.extraFlags);
    };
    virtualisation.containerd = {
      enable = true;
      settings = {
        version = 2;
        plugins."io.containerd.grpc.v1.cri" = {
          cni.conf_dir = "/var/lib/rancher/k3s/agent/etc/cni/net.d/";
          # NOTE(KI): If Nix breaks, this is why. Requires LF - not CRLF.
          cni.bin_dir = "${pkgs.runCommand "cni-bin-dir" {} ''
            mkdir -p $out
            ln -sf ${pkgs.cni-plugins}/bin/* ${pkgs.cni-plugin-flannel}/bin/* $out
          ''}";
        };
      };
    };
    systemd.services = lib.mkMerge [
      {
        k3s = {
          path = [ pkgs.ipset pkgs.nfs-utils ];
          wants = [ "containerd.service" ];
          after = [ "containerd.service" ];
        };
      }

      (lib.mkIf config.senpro-it.k3s-cluster.metallb.enable {
        k3s-metallb-provisioner = {
          enable = true;
          description = "Provisioner for k3s MetalLB load balancer.";
          restartIfChanged = true;
          requiredBy = [ "k3s.service" ];
          preStart = ''
            ${pkgs.coreutils-full}/bin/printf "%s\n" \
              "apiVersion: v1" \
              "kind: Namespace" \
              "metadata:" \
              "  labels:" \
              "    pod-security.kubernetes.io/audit: privileged" \
              "    pod-security.kubernetes.io/enforce: privileged" \
              "    pod-security.kubernetes.io/warn: privileged" \
              "  name: metallb-system" \
              "---" \
              "apiVersion: helm.cattle.io/v1" \
              "kind: HelmChart" \
              "metadata:" \
              "  name: metallb" \
              "  namespace: metallb-system" \
              "spec:" \
              "  chart: metallb" \
              "  repo: https://metallb.github.io/metallb" \
              "  targetNamespace: metallb-system" \
              "---" \
              "apiVersion: metallb.io/v1beta1" \
              "kind: IPAddressPool" \
              "metadata:" \
              "  name: default-pool" \
              "  namespace: metallb-system" \
              "spec:" \
              "  addresses:" \
              "  - ${config.senpro-it.k3s-cluster.metallb.addressRange}" \
              "---" \
              "apiVersion: metallb.io/v1beta1" \
              "kind: L2Advertisement" \
              "metadata:" \
              "  name: default" \
              "  namespace: metallb-system" \
              "spec:" \
              "  ipAddressPools:" \
              "  - default-pool" > /var/lib/rancher/k3s/server/manifests/metallb.yaml
          '';
          postStop = ''
            ${pkgs.coreutils-full}/bin/rm -f /var/lib/rancher/k3s/server/manifests/metallb.yaml
          '';
          serviceConfig = { ExecStart = ''${pkgs.bashInteractive}/bin/bash -c "while true; do echo 'k3s-metallb-provisioner is up & running'; sleep 1d; done"''; };
        };
      })

      (lib.mkIf config.senpro-it.k3s-cluster.nfs.enable {
        k3s-nfs-provisioner = {
          enable = true;
          description = "Provisioner for k3s NFS storage.";
          restartIfChanged = true;
          requiredBy = [ "k3s.service" ];
          preStart = ''
            ${pkgs.coreutils-full}/bin/printf "%s\n" \
              "apiVersion: helm.cattle.io/v1" \
              "kind: HelmChart" \
              "metadata:" \
              "  name: nfs" \
              "  namespace: kube-system" \
              "spec:" \
              "  chart: csi-driver-nfs" \
              "  repo: https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts" \
              "  targetNamespace: kube-system" \
              "---" \
              "apiVersion: storage.k8s.io/v1" \
              "kind: StorageClass" \
              "metadata:" \
              "  name: nfs-csi" \
              "provisioner: nfs.csi.k8s.io" \
              "parameters:" \
              "  server: ${config.senpro-it.k3s-cluster.nfs.server}" \
              "  share: ${config.senpro-it.k3s-cluster.nfs.directory}" \
              "reclaimPolicy: Retain" \
              "volumeBindingMode: Immediate" \
              "mountOptions:" \
              "  - nfsvers=4.1" > /var/lib/rancher/k3s/server/manifests/nfs.yaml
          '';
          postStop = ''
            ${pkgs.coreutils-full}/bin/rm -f /var/lib/rancher/k3s/server/manifests/nfs.yaml
          '';
          serviceConfig = { ExecStart = ''${pkgs.bashInteractive}/bin/bash -c "while true; do echo 'k3s-nfs-provisioner is up & running'; sleep 1d; done"''; };
        };
      })
    ];
  });
}
