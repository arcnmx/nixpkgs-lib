{ pkgs ? import <nixpkgs> { } }: with pkgs; let
  generate = writeShellScriptBin "generate-nixpkgs" ''
    export NIXPKGS_LIB_GENERATE=${toString ./.}
    export NIXPKGS_LIB=${toString ../.}
    export PATH="$PATH:${git-filter-repo}/bin"
    exec ${runtimeShell} ${./filter.sh} "$@"
  '';
in mkShell {
  inherit generate;
  nativeBuildInputs = [ git-filter-repo generate ];
}
