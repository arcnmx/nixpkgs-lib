{ pkgs, lib, ... }: with pkgs; with lib; let
  generate = import ../generate/shell.nix {
    inherit pkgs;
  };
  branches = [ "generate" ];
in {
  name = "nixpkgs-lib-generate";
  ci.gh-actions = {
    enable = true;
    checkoutOptions = {
      fetch-depth = 0;
      ref = "generate";
    };
  };
  ci.version = "nix2.4-broken";
  gh-actions.on = {
    push = {
      inherit branches;
    };
    pull_request = {
      inherit branches;
    };
    schedule = singleton {
      cron = "0 0 * * *";
    };
  };
  tasks.generate.inputs = singleton (ci.command {
    name = "generate";
    command = ''
      ${generate.generate}/bin/generate-nixpkgs
    '';
    impure = true;
    environment = [ "CI_PLATFORM" "GITHUB_REF" "GITHUB_EVENT_NAME" ];
  });
}
