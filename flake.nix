{
  description = "nixpkgs/lib mirror";
  outputs = { self }: {
    lib = import ./lib;
    legacyPackages = self.lib.genAttrs self.lib.systems.supported.hydra (system: {
      inherit (self) lib;
    });
    flakes = {
      metadata.libOnly = true;
    };
  };
}
