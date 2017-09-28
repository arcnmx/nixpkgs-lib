{ lib }:
let

  inherit (builtins) attrNames isFunction;

in

rec {


  /* `overrideDerivation drv f' takes a derivation (i.e., the result
     of a call to the builtin function `derivation') and returns a new
     derivation in which the attributes of the original are overridden
     according to the function `f'.  The function `f' is called with
     the original derivation attributes.

     `overrideDerivation' allows certain "ad-hoc" customisation
     scenarios (e.g. in ~/.config/nixpkgs/config.nix).  For instance,
     if you want to "patch" the derivation returned by a package
     function in Nixpkgs to build another version than what the
     function itself provides, you can do something like this:

       mySed = overrideDerivation pkgs.gnused (oldAttrs: {
         name = "sed-4.2.2-pre";
         src = fetchurl {
           url = ftp://alpha.gnu.org/gnu/sed/sed-4.2.2-pre.tar.bz2;
           sha256 = "11nq06d131y4wmf3drm0yk502d2xc6n5qy82cg88rb9nqd2lj41k";
         };
         patches = [];
       });

     For another application, see build-support/vm, where this
     function is used to build arbitrary derivations inside a QEMU
     virtual machine.
  */
  overrideDerivation = drv: f:
    let
      newDrv = derivation (drv.drvAttrs // (f drv));
    in addPassthru newDrv (
      { meta = drv.meta or {};
        passthru = if drv ? passthru then drv.passthru else {};
      }
      //
      (drv.passthru or {})
      //
      (if (drv ? crossDrv && drv ? nativeDrv)
       then {
         crossDrv = overrideDerivation drv.crossDrv f;
         nativeDrv = overrideDerivation drv.nativeDrv f;
       }
       else { }));

  # A more powerful version of `makeOverridable` with features similar
  # to `makeExtensibleWithInterface`.
  makeOverridableWithInterface = interface: f: origArgs: let

    addOverrideFuncs = {val, args, ...}: overridePackage:
      (lib.optionalAttrs (builtins.isAttrs val) (val // {
        extend = f: overridePackage (_: self: super: {
          val = super.val // f self.val super.val;
        });

        overrideDerivation = newArgs: overridePackage (_: self: super: {
          val = lib.overrideDerivation super.val newArgs;
        });

        ${if val ? overrideAttrs then "overrideAttrs" else null} = fdrv:
          overridePackage (_: self: super: {
            val = super.val.overrideAttrs fdrv;
          });
      })) // (lib.optionalAttrs (builtins.isFunction val) {
        __functor = _: val;
        extend = throw "extend not yet supported for functors";
        overrideDerivation = throw "overrideDerivation not yet supported for functors";
      }) // {
        inherit overridePackage;

        override = newArgs: overridePackage (_: self: super: {
          args = super.args //
            (if builtins.isFunction newArgs then newArgs super.args else newArgs);
        });
      };

  in lib.makeExtensibleWithInterface (x: o: interface (addOverrideFuncs x o) o) (output: self: {
    args = origArgs;
    val = f output self.args self.val;
  });


  /* `makeOverridable` takes a function from attribute set to
     attribute set and injects 4 attributes which can be used to
     override arguments and return values of the function.


     1. `override` allows you to change what arguments were passed to
     the function and acquire the new result.

       nix-repl> x = {a, b}: { result = a + b; }

       nix-repl> y = lib.makeOverridable x { a = 1; b = 2; }

       nix-repl> y
       { override = «lambda»; overrideDerivation = «lambda»; result = 3; }

       nix-repl> y.override { a = 10; }
       { override = «lambda»; overrideDerivation = «lambda»; result = 12; }


     2. `extend` changes the results of the function, giving you a
     view of the original result and a view of the eventual final
     result. It is meant to do the same thing as
     `makeExtensible`. That is, it lets you add to or change the
     return value, such that previous extensions are consistent with
     the final view, rather than being based on outdated
     values. "Outdated" values come from the `super` argument, which
     must be used when you are attempting to modify and old value. And
     the final values come from the `self` argument, which recursively
     refers to what all extensions combined return.

       nix-repl> obj = makeOverridable (args: { }) { }

       nix-repl> obj = obj.extend (self: super: { foo = "foo"; })

       nix-repl> obj.foo
       "foo"

       nix-repl> obj = obj.extend (self: super: { foo = super.foo + " + "; bar = "bar"; foobar = self.foo + self.bar; })

       nix-repl> obj
       { bar = "bar"; foo = "foo + "; foobar = "foo + bar"; ... } # Excess omitted


     3. `overrideDerivation`: Please refer to "Nixpkgs Contributors
     Guide" section "<pkg>.overrideDerivation" to learn about
     `overrideDerivation` and caveats related to its use.


     4. `overridePackage` is by far the most powerful of the four, as
     it exposes a deeper structure. It provides `self` and `super`
     views of both the arguments and return value of the function,
     allowing you to change both in one override; you can even have
     overrides for one based on overrides for the other. It also
     provides the `output` view, which is the view of `self` after
     passing it through the `makeOverridable` interface and adding all
     the `overrideX` functions. `output` is necessary when your
     overrides depend on the overridable structure of `output`.

       nix-repl> obj = makeOverridable ({a, b}: {inherit a b;}) {a = 1; b = 3;}

       nix-repl> obj = obj.overridePackage (output: self: super: { args = super.args // {b = self.val.a;}; })

       nix-repl> obj.b
       1

       nix-repl> obj = obj.overridePackage (output: self: super: { val = super.val // {a = self.args.a + 10;}; })

       nix-repl> obj.b
       11

  */
  makeOverridable = fn: makeOverridableWithInterface (x: _: x) (_: args: _: fn args);

  callPackageCommon = functionArgs: scope: f: args:
    let
      intersect = builtins.intersectAttrs functionArgs;
      interface = val: overridePackage: val // {
        overrideScope = newScope: overridePackage (_: self: super: {
          scope = super.scope.extend newScope;
        });
      };
    in (makeOverridableWithInterface interface f (intersect scope // args))
      .overridePackage (output: self: super: {
        inherit scope;
        # Don't use super.args because that contains the original scope.
        args = intersect self.scope  // args;
      });


  /* Call the package function in the file `fn' with the required
    arguments automatically.  The function is called with the
    arguments `args', but any missing arguments are obtained from
    `autoArgs'.  This function is intended to be partially
    parameterised, e.g.,

      callPackage = callPackageWith pkgs;
      pkgs = {
        libfoo = callPackage ./foo.nix { };
        libbar = callPackage ./bar.nix { };
      };

    If the `libbar' function expects an argument named `libfoo', it is
    automatically passed as an argument.  Overrides or missing
    arguments can be supplied in `args', e.g.

      libbar = callPackage ./bar.nix {
        libfoo = null;
        enableX11 = true;
      };

    On top of the additions from `makeOverridable`, an `overrideScope`
    function is also added to the result. It is similar to `override`,
    except that it provides `self` and `super` views to the
    scope. This can't be done in `makeOverridable` because the scope
    is filtered to just the arguments needed by the function before
    entering `makeOverridable`. It is useful to have a view of the
    scope before restriction; for example, to change versions for a
    particular dependency.

      foo.overrideScope (self: super: {
        llvm = self.llvm_37;
      })

    `llvm_37` would not exist in the scope after restriction.

  */
  callPackageWith = autoArgs: fn: args:
    let f = if builtins.isFunction fn then fn else import fn;
    in callPackageCommon (builtins.functionArgs f) autoArgs (output: x: _: f x) args;


  # Like `callPackageWith`, but provides the function with a `self`
  # view of the output, which has the override functions
  # injected. `fn` is called with the new output whenever an override
  # or extension is added.
  callPackageWithOutputWith = autoArgs: fn: args:
    let f = if builtins.isFunction fn then fn else import fn;
    in callPackageCommon (builtins.functionArgs f) autoArgs (output: args: _: f args output ) args;


  /* Like callPackage, but for a function that returns an attribute
     set of derivations. The override function is added to the
     individual attributes. */
  callPackagesWith = autoArgs: fn: args:
    let
      f = if builtins.isFunction fn then fn else import fn;
      auto = builtins.intersectAttrs (builtins.functionArgs f) autoArgs;
      origArgs = auto // args;
      pkgs = f origArgs;
      mkAttrOverridable = name: pkg: makeOverridable (newArgs: (f newArgs).${name}) origArgs;
    in lib.mapAttrs mkAttrOverridable pkgs;


  /* Add attributes to each output of a derivation without changing
     the derivation itself. */
  addPassthru = drv: passthru:
    let
      outputs = drv.outputs or [ "out" ];

      commonAttrs = drv // (builtins.listToAttrs outputsList) //
        ({ all = map (x: x.value) outputsList; }) // passthru;

      outputToAttrListElement = outputName:
        { name = outputName;
          value = commonAttrs // {
            inherit (drv.${outputName}) outPath drvPath type outputName;
          };
        };

      outputsList = map outputToAttrListElement outputs;
  in commonAttrs // { outputUnspecified = true; };


  /* Strip a derivation of all non-essential attributes, returning
     only those needed by hydra-eval-jobs. Also strictly evaluate the
     result to ensure that there are no thunks kept alive to prevent
     garbage collection. */
  hydraJob = drv:
    let
      outputs = drv.outputs or ["out"];

      commonAttrs =
        { inherit (drv) name system meta; inherit outputs; }
        // lib.optionalAttrs (drv._hydraAggregate or false) {
          _hydraAggregate = true;
          constituents = map hydraJob (lib.flatten drv.constituents);
        }
        // (lib.listToAttrs outputsList);

      makeOutput = outputName:
        let output = drv.${outputName}; in
        { name = outputName;
          value = commonAttrs // {
            outPath = output.outPath;
            drvPath = output.drvPath;
            type = "derivation";
            inherit outputName;
          };
        };

      outputsList = map makeOutput outputs;

      drv' = (lib.head outputsList).value;
    in lib.deepSeq drv' drv';

  /* Make a set of packages with a common scope. All packages called
     with the provided `callPackage' will be evaluated with the same
     arguments. Any package in the set may depend on any other. The
     `overrideScope' function allows subsequent modification of the package
     set in a consistent way, i.e. all packages in the set will be
     called with the overridden packages. The package sets may be
     hierarchical: the packages in the set are called with the scope
     provided by `newScope' and the set provides a `newScope' attribute
     which can form the parent scope for later package sets. */
  makeScope = newScope: f:
    let self = f self // {
          newScope = scope: newScope (self // scope);
          callPackage = self.newScope {};
          overrideScope = g:
            makeScope newScope
            (self_: let super = f self_; in super // g super self_);
          packages = f;
        };
    in self;

}
