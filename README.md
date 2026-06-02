# `override-utils`

This project implements an ergonomic interface for overriding Nixpkgs
implemented in pure Nix.

The inspiration for this project is a blog post I wrote:
[The hard part of type-checking Nix](https://haskellforall.com/2022/03/the-hard-part-of-type-checking-nix).  In that post I noted that one major source of
usability issues was Nixpkgs:

> The real issue with Nix isn’t the lack of a type checker. The absence of a
> type-checker is problematic, but in my view this is a symptom of a larger
> issue.
>
> The fundamental problem that plagues all type-checking attempts for Nix is
> that nobody actually uses Nix the language at any significant scale. Instead,
> the community has adopted two sub-languages embedded within Nix for
> programming “in the large”:
>
> - Nixpkgs overlays
>
>   This is an embedded language that simulates object-oriented programming with
>   inheritance / late binding / dynamic scope (depending on how you think about
>   it)
>
> - NixOS modules
>
>   This is an embedded language that roughly emulates Terraform

This project addresses part of that problem by providing a simpler way to create
Nixpkgs overrides/overlays with fewer footguns and better error messages.

For example, instead of writing this:

```nix
final: prev: {
  nix-serve-ng = prev.nix-serve-ng.overrideAttrs (old: {
    patches = (old.patches or []) ++ [ ./lix-compat.patch ];
  });
}
```

… you can now write this:

```nix
final: override {
  nix-serve-ng.overrideAttrs.patches = append [ ./lix-compat.patch ];
}
```

## Quickstart

### Flake interface

```nix
{ inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  inputs.override-utils.url = "github:Gabriella439/override-utils";

  outputs = { nixpkgs, flake-utils, override-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system: {
      packages =
        let
          utils = override-utils.lib."${system}";

          overlay = final: utils.override {
            nix-serve-ng.overrideAttrs.patches =
              utils.append [ ./lix-compat.patch ];
          };

          pkgs = nixpkgs.legacyPackages."${system}".appendOverlays [ overlay ];

        in
          { inherit (pkgs) nix-serve-ng; };
    });
}
```

### Non-flake interface

This repository provides a `default.nix` which uses `flake-compat` to export the
same outputs as as `flake.nix`.

## Tutorial

You can create an override function using `override`.  For example, this
creates a new function that sets the `foo` attribute to `2`:

```nix
override {
  foo = set 2;
}
```

The result of `override` is a function that you can directly invoke on an
existing attribute set, like this:

```nix
nix-repl> :print override { foo = set 2; } { bar = 3; }
{ bar = 3; foo = 2; }
```

You need to specify an operation (like `set`) for each attribute you modify.  If
you omit the operation:

```nix
override {
  foo = 1;
}
```

… then you will get an error message like this one:

```nix
nix-repl> :print override { foo = 1; } { }
…
       override-utils: No operation specified

       You wrote something like this:

           override {
             foo =
               1;
           }

       … but you need to specify an operation like this:

           override {
             foo =
               set 1;
               ━━━
           }
```

Overrides can be nested:

```nix
override {
  foo.bar = set 1;
}
```

… and they will create any intermediate attributes that are missing:

```nix
nix-repl> :print override { foo.bar = set 1; } { }
{ foo = { bar = 1; }; }
```

You can modify an existing value using `modify`, which is the most general
interface for modifying values:

```nix
nix-repl> :print override { foo = modify ({ input }: input + 3); } { foo = 2; }
{ foo = 5; }
```

The `modify` operation lets you specify a default value if the attribute is not
present:

```nix
nix-repl> :print override { foo = modify ({ input ? 0 }: input + 3); } { }
{ foo = 3; }

nix-repl> :print override { foo = modify ({ input ? 0 }: input + 3); } { foo = 2; }
{ foo = 5; }
```

However, you'll more commonly use a helper operation, like `add`:

```nix
nix-repl> :print override { foo = add 3; } { }
{ foo = 3; }

nix-repl> :print override { foo = add 3; } { foo = 2; }
{ foo = 5; }
```

For the full list of supported operations, see the [Operations](#operations)
section below.

You can transform each element in a list using the `"*"` attribute:

```nix
nix-repl> :print override { foo."*" = add 1; } { foo = [ 2 3 5 ]; }
{ foo = [ 3 4 6 ]; }

nix-repl> :print override { foo."*" = add 1; } { }
{ foo = [ ]; }
```

… or you can transform a specific element in a list using the element's index:

```nix
nix-repl> :print override { foo."0" = set 7; } { foo = [ 2 3 5 ]; }
{ foo = [ 7 3 5 ]; }
```

Similarly, you can transform every attribute in an attribute set using the
"\<name\>" attribute:

```nix
nix-repl> :print override { "<name>" = add 1; } { x = 2; y = 3; }
{ x = 3; y = 4; }
```

Finally, all of the `.override*` methods in Nixpkgs are supported, meaning
that you can write something like this:

```nix
override {
  nix-serve-ng.overrideAttrs.patches = append [ ./lix-compat.patch ];
}
```

… and that is the same thing as if you had written:

```nix
prev: {
  nix-serve-ng = prev.nix-serve-ng.overrideAttrs (old: {
    patches = (old.patches or []) + [ ./lix-compat.patch ];
  });
}
```

You can combine and nest all of these features arbitrarily.  For example:

```nix
nix-repl> old = { projects = [ { } { name = "OS"; } { name = "pkgs"; } ]; }

nix-repl> :print override { projects."*".name = prefix "Nix"; } old
{ projects = [ { name = "Nix"; } { name = "NixOS"; } { name = "Nixpkgs"; } ]; }
```

Or if you want something more realistic, here's an example overlay from one of
my own projects that patches `servant-multipart-client.cabal` just for GHCJS:

```nix
final: override {
  haskell.packages.ghcjs.override.overrides = set (hfinal: override {
    servant-multipart-client.overrideCabal.postPatch = append
      ''
      sed -i 's/ .*<0.19//' servant-multipart-client.cabal
      '';
  });
}
```

To do the same thing without this package you would have to write:

```nix
final: prev: {
  haskell = prev.haskell // {
    packages = prev.haskell.packages // {
      ghcjs = prev.haskell.packages.ghcjs.override (old: {
        overrides = hfinal: hprev: {
          servant-multipart-client =
            final.haskell.lib.overrideCabal
              hprev.servant-multipart-client
              (old: {
                postPatch = (old.postPatch or "") +
                  ''
                  sed -i 's/ .*<0.19//' servant-multipart-client.cabal
                  '';
              });
        };
      });
    };
  };
}
```

## Overlays

If you want to create an overlay instead of an override function, the only
difference is that you write:

```nix
final: override {
  …
}
```

In other words, you prefix `overrides` with a function argument representing
the final attribute set.

For example, if you were to write something like this:

```nix
final: override {
  x = add 1;

  y = final.x;
}
```

… that would generate the same overlay as this:

```nix
final: prev: {
  x = prev.x + 1;

  y = final.x;
}
```

## Operations

- `add`

  Add a number to the existing value (or to `0` if missing):

  ```nix
  nix-repl> :print override { foo = add 2; } { }
  { foo = 2; }

  nix-repl> :print override { foo = add 3; } { foo = 2; }
  { foo = 5; }
  ```

- `subtract`

  Subtract a number from the existing value (or from `0` if missing)

  ```nix
  nix-repl> :print override { foo = subtract 3; } { }
  { foo = -3; }

  nix-repl> :print override { foo = subtract 3; } { foo = 2; }
  { foo = -1; }
  ```

- `prepend`

  Prepend a list before the existing value (or before `[]` if missing)

  ```nix
  nix-repl> :print override { foo = prepend [ 2 3 ]; } { }
  { foo = [ 3 5 ]; }

  nix-repl> :print override { foo = prepend [ 2 3 ]; } { foo = [ 5 ]; }
  { foo = [ 3 5 2 ]; }
  ```

- `append`

  Append a list after the existing value (or after `[]` if missing)

  ```nix
  nix-repl> :print override { foo = append [ 3 5 ]; } { }
  { foo = [ 3 5 ]; }

  nix-repl> :print override { foo = append [ 3 5 ]; } { foo = [ 2 ]; }
  { foo = [ 2 3 5 ]; }
  ```

- `prefix`

  Add a string prefix before the existing value (or before `""` if missing)

  ```nix
  nix-repl> :print override { foo = prefix "Nix"; } { }
  { foo = "Nix"; }

  nix-repl> :print override { foo = prefix "Nix"; } { foo = "OS"; }
  { foo = "NixOS"; }
  ```

- `suffix`

  Add a string suffix after the existing value (or after `""` if missing)

  ```nix
  nix-repl> :print override { foo = suffix "OS"; } { }
  { foo = "OS"; }

  nix-repl> :print override { foo = suffix "OS"; } { foo = "Nix"; }
  { foo = "NixOS"; }
  ```

- `prefixWords`

  Add words before the existing value (or before `""` if missing), inserting a
  space in between

  ```nix
  nix-repl> override { foo = prefixWords "hello"; } { }
  { foo = "hello"; }

  nix-repl> override { foo = prefixWords "hello"; } { foo = "world"; }
  { foo = "hello world"; }
  ```

- `suffixWords`

  Add words after the existing value (or after `""` if missing), inserting a
  space in between

  ```nix
  nix-repl> override { foo = suffixWords "world"; } { }
  { foo = "world"; }

  nix-repl> override { foo = suffixWords "world"; } { foo = "hello"; }
  { foo = "hello world"; }
  ```

- `prefixLines`

  Prepend lines before the existing value (or before `""` if missing)

  ```nix
  nix-repl> :print override { foo = prefixLines "hello"; } { }
  { foo = "hello"; }

  nix-repl> :print override { foo = prefixLines "hello"; } { foo = "world"; }
  { foo = "hello\nworld"; }
  ```

- `suffixLines`

  Append lines after the existing value (or after `""` if missing), inserting
  a newline in between

  ```nix
  nix-repl> :print override { foo = suffixLines "world"; } { }
  { foo = "world"; }

  nix-repl> :print override { foo = suffixLines "world"; } { foo = "hello"; }
  { foo = "hello\nworld"; }
  ```
