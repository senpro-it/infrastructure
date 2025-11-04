{ config, pkgs, lib, ... }:

with lib;

{
  options = {
    senpro-it = {
      host = {
        name = mkOption {
          type = types.strMatching
            "^$|^[[:alnum:]]([[:alnum:]_-]{0,61}[[:alnum:]])?$";
          default = "nixos";
          description = ''
            The name of the machine. Leave it empty if you want to obtain it from a
            DHCP server (if using DHCP). The hostname must be a valid DNS label (see
            RFC 1035 section 2.3.1: "Preferred name syntax", RFC 1123 section 2.1:
            "Host Names and Numbers") and as such must not contain the domain part.
            This means that the hostname must start with a letter or digit,
            end with a letter or digit, and have as interior characters only
            letters, digits, and hyphen. The maximum length is 63 characters.
            Additionally it is recommended to only use lower-case characters.
            If (e.g. for legacy reasons) a FQDN is required as the Linux kernel
            network node hostname (uname --nodename) the option
            boot.kernel.sysctl."kernel.hostname" can be used as a workaround (but
            the 64 character limit still applies).

            WARNING: Do not use underscores (_) or you may run into unexpected issues.
          '';
        };
      };
    };
  };
  config = {
    boot = {
      loader = {
        systemd-boot.enable = true;
        efi.canTouchEfiVariables = true;
      };
    };
    console = {
      font = "Lat2-Terminus16";
      keyMap = "de";
    };
    environment = {
      systemPackages = with pkgs; [ git flow-control nano jq file htop ];
    };
    i18n = {
      defaultLocale = "de_DE.UTF-8";
    };
    networking = {
      hostName = "${config.senpro-it.host.name}";
      firewall = {
        enable = true;
      };
      useDHCP = false;
      useNetworkd = true;
    };
    programs.fish = {
      enable = true;
      useBabelfish = true;
    };
    users = {
      mutableUsers = false;
      defaultUserShell = pkgs.fish;
    };
    nix.gc.automatic = lib.mkDefault false;
    services = {
      openssh = {
        enable = true;
      };
      resolved = {
        dnssec = "false";
      };
    };
    system = {
      autoUpgrade.enable = lib.mkDefault false;
      copySystemConfiguration = true;
      stateVersion = "23.11";
    };
  };
}
