{ config, pkgs, lib, ... }:

{
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
      systemPackages = with pkgs; [ exa ];
    };
    i18n = {
      defaultLocale = "de_DE.UTF-8";
    };
    programs.fish = {
      enable = true;
      useBabelfish = true;
    };
    users = {
      mutableUsers = false;
      defaultUserShell = pkgs.fish;
    };
    nix = {
      gc = {
        automatic = true;
        dates = "Sat, 22:00";
        randomizedDelaySec = "30min";
      };
    };
    services = {
      openssh = {
        enable = true;
      };
    };
    system = {
      autoUpgrade = {
        enable = true;
        dates = "Sun, 21:00";
        rebootWindow = {
          lower = "21:00";
          upper = "23:30";
        };
        allowReboot = true;
        randomizedDelaySec = "30min";
      };
      copySystemConfiguration = true;
      stateVersion = "22.11";
    };
  };
}
