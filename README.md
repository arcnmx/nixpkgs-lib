# nixpkgs-lib

A mirror of [nixpkgs/lib](https://github.com/NixOS/nixpkgs/tree/master/lib) used for bootstrapping
purposes. This is mainly used in cases where nixpkgs is an unnecessarily large download when only
`pkgs.lib` is needed.

## Flakes

This is designed to be used as a drop-in replacement for nixpkgs, and thus should be imported like
so:

```nix
{
	inputs.nixpkgs.url = "github:arcnmx/nixpkgs-lib";
	outputs = { nixpkgs, ... }: {
		lib.exampleFn = nixpkgs.lib.hasPrefix "whee";
	};
}
```

### Overriding

If `nixpkgs` is used by an upstream dependency, it should override this lib with the real nixpkgs:

```nix
{
	inputs = {
		example = {
			url = "example/whee";
			# override `nixpkgs-lib` with the real `nixpkgs`:
			inputs.nixpkgs.follows = "nixpkgs";
		};
		nixpkgs.url = "nixpkgs";
	};
}
```

## Branches

The source code lives in the [generate](https://github.com/arcnmx/nixpkgs-lib/tree/generate) branch.
master is managed automatically, and should not be pushed to manually.
