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
          description = lib.mdDoc ''
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
          description = lib.mdDoc ''
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
          addressRange = mkOption {
            type = types.str;
            description = lib.mdDoc ''
              IP range which MetalLB should use to advertise services.
            '';
            example = "192.168.178.20-192.168.178.40";
          };
        };
        nfs = {
          server = mkOption {
            type = types.str;
            default = "127.0.0.1";
            description = lib.mdDoc ''
              The NFS server to connect to. Can be either an IPv4 address or an FQDN.
            '';
            example = "192.168.178.1";
          };
          directory = mkOption {
            type = types.path;
            default = "/";
            description = lib.mdDoc ''
              Target directory at the server which should be mounted.
            '';
            example = "/mnt/example";
          };
        };
        server = {
          address = mkOption {
            type = types.str;
            default = "";
            description = lib.mdDoc ''
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
            description = lib.mdDoc ''
              The k3s token to use when connecting to a server.

              WARNING: This option will expose store your token unencrypted world-readable in the nix store.
              If this is undesired use the tokenFile option instead.
            '';
          };
        };
        traefik = {
          loadBalancerIP = mkOption {
            type = types.str;
            description = lib.mdDoc ''
              IPv4 address of the Load Balancer for the Traefik Ingress Controller.
            '';
            example = "192.168.178.20";
          };
          certResolver = {
            letsEncrypt = {
              dnsChallenge = {
                provider = mkOption {
                  type = types.str;
                  description = lib.mdDoc ''
                    Identifier of the DNS provider. See [ACME provider](https://doc.traefik.io/traefik/https/acme/#providers) for further information.
                  '';
                  example = "hostingde";
                };
                environment = {
                  hostingde = {
                    apiKey = mkOption {
                      type = types.str;
                      default = "";
                      description = lib.mdDoc ''
                        API key for the hosting.de API to generate SSL certificates using the Traefik dnsChallenge.
                      '';
                    };
                    zoneName = mkOption {
                      type = types.str;
                      default = "";
                      description = lib.mdDoc ''
                        Zone name for the Traefik dnsChallenge. API key must have sufficient rights for this zone..
                      '';
                    };
                  };
                };
              };
            };
          };
          services = {
            dashboard = {
              hostName = mkOption {
                type = types.str;
                description = lib.mdDoc ''
                  Hostname to use for the Traefik dashboard. It should be FQDN.
                '';
                example = "dashboard.traefik.local";
              };
            };
          };
        };
      };
    };
  };
  config = (lib.mkIf config.senpro-it.k3s-cluster.enable {
    networking = {
      firewall = {
        allowedTCPPorts = if config.senpro-it.k3s-cluster.role == "server" then [ 6443 10250 ] else [ 10250 ];
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
      extraFlags = if config.senpro-it.k3s-cluster.role == "server" then "--flannel-backend=host-gw --disable=servicelb --container-runtime-endpoint unix:///run/containerd/containerd.sock" else "";
    };
    virtualisation.containerd = {
      enable = true;
      settings = {
        version = 2;
        plugins."io.containerd.grpc.v1.cri" = {
          cni.conf_dir = "/var/lib/rancher/k3s/agent/etc/cni/net.d/";
          cni.bin_dir = "${pkgs.runCommand "cni-bin-dir" {} ''
            mkdir -p $out
            ln -sf ${pkgs.cni-plugins}/bin/* ${pkgs.cni-plugin-flannel}/bin/* $out
          ''}";
        };
      };
    };
    systemd.services = {
      k3s = {
        path = [ pkgs.ipset pkgs.nfs-utils ];
        wants = [ "containerd.service" ];
        after = [ "containerd.service" ];
      };
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
      k3s-traefik-provisioner = {
        enable = true;
        description = "Provisioner for k3s Traefik Ingress Controller.";
        restartIfChanged = true;
        requiredBy = [ "k3s.service" ];
        preStart = ''
          ${pkgs.coreutils-full}/bin/printf "%s\n" \
            "apiVersion: v1" \
            "kind: PersistentVolumeClaim" \
            "" \
            "metadata:" \
            "  name: traefik" \
            "  namespace: kube-system" \
            "spec:" \
            "  storageClassName: nfs-csi" \
            "  accessModes:" \
            "  - ReadWriteMany" \
            "  - ReadWriteOnce" \
            "  resources:" \
            "    requests:" \
            "      storage: 128Mi" \
            "---" \
            "apiVersion: helm.cattle.io/v1" \
            "kind: HelmChartConfig" \
            "metadata:" \
            "  name: traefik" \
            "  namespace: kube-system" \
            "spec:" \
            "  valuesContent: |-" \
            "    logs:" \
            "      level: INFO" \
            "      access:" \
            "        enabled: true" \
            "" \
            "    dashboard:" \
            "      enabled: true" \
            "" \
            "    deployment:" \
            "      enabled: true" \
            "      replicas: 2" \
            "      initContainers:" \
            "        - name: volume-permissions" \
            "          image: busybox:latest" \
            "          command: [\"sh\", \"-c\", \"touch /data/acme.json; chmod -v 600 /data/acme.json\"]" \
            "          securityContext:" \
            "            runAsNonRoot: true" \
            "            runAsGroup: 65532" \
            "            runAsUser: 65532" \
            "          volumeMounts:" \
            "            - name: data" \
            "              mountPath: /data" \
            "" \
            "    ports:" \
            "      web:" \
            "        redirectTo: websecure" \
            "      websecure:" \
            "        tls:" \
            "          certResolver: \"letsEncrypt\"" \
            "" \
            "    persistence:" \
            "      enabled: true" \
            "      existingClaim: traefik" \
            "      accessMode: ReadWriteOnce" \
            "      size: 128Mi" \
            "      path: /data" \
            "" \
            "    providers:" \
            "      kubernetesCRD:" \
            "        enabled: true" \
            "        namespaces: []" \
            "    kubernetesIngress:" \
            "      enabled: true" \
            "      namespaces: []" \
            "      publishedService:" \
            "        enabled: true" \
            "" \
            "    rbac:" \
            "      enabled: true" \
            "" \
            "    service:" \
            "      enabled: true" \
            "      type: LoadBalancer" \
            "      spec:" \
            "        loadBalancerIP: \"${config.senpro-it.k3s-cluster.traefik.loadBalancerIP}\"" \
            "" \
            "    certResolvers:" \
            "      letsEncrypt:" \
            "        dnsChallenge:" \
            "          provider: ${config.senpro-it.k3s-cluster.traefik.certResolver.letsEncrypt.dnsChallenge.provider}" \
            "          delayBeforeCheck: 30" \
            "          resolvers:" \
            "            - 1.1.1.1" \
            "            - 8.8.8.8" \
            "        storage: /data/acme.json" \
            "" \
            "    updateStrategy:" \
            "      type: RollingUpdate" \
            "      rollingUpdate:" \
            "        maxUnavailable: 1" \
            "" \
            "    env:" \
            "      - name: HOSTINGDE_API_KEY" \
            "        value: ${config.senpro-it.k3s-cluster.traefik.certResolver.letsEncrypt.dnsChallenge.environment.hostingde.apiKey}" \
            "      - name: HOSTINGDE_ZONE_NAME" \
            "        value: ${config.senpro-it.k3s-cluster.traefik.certResolver.letsEncrypt.dnsChallenge.environment.hostingde.zoneName}" \
            "" \
            "    additionalArguments:" \
            "      - --serversTransport.insecureSkipVerify=true" \
            "      - --providers.kubernetescrd.allowCrossNamespace=true" \
            "" \
            "    # See https://github.com/traefik/traefik-helm-chart/blob/master/traefik/values.yaml for more examples" \
            "    # The deployment.kind=DaemonSet and hostNetwork=true is to get real ip and x-forwarded for," \
            "    # and can be omitted if this is not needed." \
            "" \
            "    # The updateStrategy settings are required for the latest traefik helm version when using hostNetwork." \
            "    # see more here: https://github.com/traefik/traefik-helm-chart/blob/v20.8.0/traefik/templates/daemonset.yaml#L12-L14" \
            "    # but this version not yet supported by k3s, so leaving it commented out for now." \
            "    # The config above has been tested to work with latest stable k3s (v1.25.4+k3s1)." \
            "---" \
            "apiVersion: traefik.containo.us/v1alpha1" \
            "kind: IngressRoute" \
            "metadata:" \
            "  name: traefik-dashboard" \
            "  namespace: kube-system" \
            "spec:" \
            "  entryPoints:" \
            "    - websecure" \
            "  routes:" \
            "    - match: Host(\`${config.senpro-it.k3s-cluster.traefik.services.dashboard.hostName}\`) && (PathPrefix(\`/dashboard\`) || PathPrefix(\`/api\`))" \
            "      kind: Rule" \
            "      services:" \
            "      - name: api@internal" \
            "        kind: TraefikService" > /var/lib/rancher/k3s/server/manifests/ingress-controller.yaml 
        '';
        postStop = ''
          ${pkgs.coreutils-full}/bin/rm -f /var/lib/rancher/k3s/server/manifests/ingress-controller.yaml
        '';
        serviceConfig = { ExecStart = ''${pkgs.bashInteractive}/bin/bash -c "while true; do echo 'k3s-traefik-provisioner is up & running'; sleep 1d; done"''; };
      };
    };
  });
}
