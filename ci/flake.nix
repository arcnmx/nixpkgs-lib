{ pkgs, lib, ... }: with lib; let
  flake-check = name: path: pkgs.ci.command {
    name = "${name}-check";
    command = ''
      nix flake check ${path}
    '';
    impure = true;
  };
in {
  name = "nixpkgs-lib-flake";
  ci.version = "nix2.4";
  ci.gh-actions = {
    enable = true;
    checkoutOptions.submodules = false;
  };
  gh-actions.on.push.branches = [ "master" ];
  tasks.flake.inputs = singleton (flake-check "flake" ".");
}
