# infrastructure
Nixpkgs overlay containing various modules and packages.

## Usage

Use the Nix modules in this repository by importing it in your `configuration.nix` as follows:

```
let

  infrastructure = builtins.fetchGit {
    url = "https://github.com/senpro-it/infrastructure.git";
    ref = "main";
    rev = "<commit-hash>";
  };

in {

  imports = [
    "${infrastructure}/nixos"
    ./hardware-configuration.nix
  ];

  ...

}
```
