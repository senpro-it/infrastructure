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
      extraFlags = if config.senpro-it.k3s-cluster.role == "server" then "--flannel-backend=host-gw --container-runtime-endpoint unix:///run/containerd/containerd.sock" else "";
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
    systemd.services.k3s = {
      path = [ pkgs.ipset ];
      wants = [ "containerd.service" ];
      after = [ "containerd.service" ];
    };
  });
}
