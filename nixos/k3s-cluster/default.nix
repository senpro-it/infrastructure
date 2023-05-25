{ config, pkgs, lib, ... }:

with lib;

{
  options = {
    senpro-it = {
      k3s-cluster = {
        enable = mkEnableOption ''
          Whether to enable k3s cluster functionalities.
        '';
      };
    };
  };
  config = (lib.mkIf config.senpro-it.k3s-cluster.enable {
    services.k3s = {
      enable = true;
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
