{ pkgs, lib, ... }: with lib; let
  flake-check = name: path: pkgs.ci.command {
    name = "${name}-check";
    command = ''
      nix flake check ${path}
    '';
    impure = true;
    environment = ["NIX_CONF_DIR" "NIX_USER_CONF_FILES"];
  };
in {
  name = "nixpkgs-lib-flake";
  ci.version = "v0.7";
  ci.gh-actions = {
    enable = true;
    checkoutOptions.submodules = false;
  };
  gh-actions.on.push.branches = [ "lib-*" ];
  tasks.flake.inputs = singleton (flake-check "flake" ".");
}
