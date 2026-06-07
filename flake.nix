{ inputs = {
    flake-compat = {
      url = "github:NixOS/flake-compat";
      flake = false;
    };

    nixpkgs.url = "github:NixOS/nixpkgs/26.05";
  };

  outputs = { nixpkgs, self, ... }:
    let
      inherit (nixpkgs) lib;

      renderAttributePath =
        lib.concatMapStringsSep "." lib.strings.escapeNixIdentifier;

      libWith = { system ? null }: rec {
        overlay = f: final: override (f final);

        override =
          let
            loop = names: argument:
              let
                adapt = name: value:
                  let
                    newNames = names ++ [ name ];

                    missingAttribute = abort
                      ''


                      override-utils: Missing attribute

                      You attempted to modify this attribute:

                          ${renderAttributePath names}

                      … but this attribute does not exist.
                      '';

                    notAnAttributeSet = abort
                      ''


                      override-utils: Not an attribute set

                      You wrote something like this:

                          override {
                            ${renderAttributePath newNames} = …;
                          }

                      … but this is not an attribute set:

                          ${renderAttributePath ([ "prev" ] ++ names)}

                      … and therefore cannot store an attribute named `${renderAttributePath [ name ]}`.
                      '';

                    missingSystem = abort
                      ''


                      override-utils: Missing system

                      You wrote something like this:
                      
                        override-utils.lib.override {
                          ${renderAttributePath newNames} = …;
                        };

                      … but the top-level `lib` attribute does not support `overrideCabal` by
                      default because that feature needs a specific `system`.  To fix this
                      error, do this instead:
                      
                        override-utils.lib."''${system}".override {
                                           ━━━━━━━━━━━
                          ${renderAttributePath newNames} = …;
                        };
                      '';

                    default = name:
                      if builtins.match "[0-9]+" name != null
                      then
                        { input ? [ ] }:
                          let
                            index = builtins.fromJSON name;

                          in
                            if builtins.length input <= index
                            then abort
                              ''
                              override-utils: Index out of bounds

                              The following index:

                                  ${renderAttributePath newNames}

                              … is out of bounds.
                              ''
                            else
                              let
                                prefix = lib.take index input;

                                element = builtins.elemAt input index;

                                suffix = lib.drop (index + 1) input;

                              in
                                    prefix
                                ++  [ (loop newNames value element) ]
                                ++  suffix

                      else
                        { input ? { } }:
                          if builtins.isAttrs input
                          then
                            let
                              arg =
                                if builtins.hasAttr name input
                                then { input = input."${name}"; }
                                else { };

                            in
                              input // {
                                "${name}" = loop newNames value arg;
                              }

                          else
                            notAnAttributeSet;

                  in
                    { modify = value;

                      "*" = { input ? [] }:
                        map (old: loop newNames value { input = old; })
                          input;

                      "<name>" = { input ? { } }:
                        lib.mapAttrs (_: old: loop newNames value { input = old; })
                          input;

                      override = { input ? missingAttribute }:
                        input.override (old:
                          loop newNames value { input = old; }
                        );

                      overrideAttrs = { input ? missingAttribute }:
                        input.overrideAttrs (old:
                          loop newNames value { input = old; }
                        );

                      overrideDerivation = { input ? missingAttribute }:
                        input.overrideDerivation (old:
                          loop newNames value { input = old; }
                        );

                      overrideCabal = { input ? missingAttribute }:
                        if system == null
                          then
                            missingSystem
                          else
                            nixpkgs.legacyPackages."${system}".haskell.lib.overrideCabal input (old:
                              loop newNames value { input = old; }
                            );
                    }."${name}" or (default name);

              in
                if builtins.isAttrs argument
                then
                  x:
                    (lib.foldl (x: f: { input = f x; }) x
                      (lib.mapAttrsToList adapt argument)
                    ).input

                else
                  if names == []
                  then
                    abort
                      ''


                      override-utils: Invalid input

                      You wrote something like this:

                          override
                            ${lib.generators.toPretty { indent = "      "; } argument}

                      … which is not allowed because `override` only accepts an attribute set
                      as input.
                      ''
                  else
                    abort
                      ''


                      override-utils: No operation specified

                      You wrote something like this:

                          override {
                            ${renderAttributePath names} =
                              ${lib.generators.toPretty { indent = "        "; } argument};
                          }

                      … but you need to specify an operation like this:

                          override {
                            ${renderAttributePath names} =
                              set ${lib.generators.toPretty { indent = "            "; } argument};
                              ━━━
                          }
                      '';

          in
            argument: input: loop [] argument { inherit input; };

        modify = f: { modify = f; };

        set = value: modify (_: value);

        add      = x: modify ({ input ? 0 }: input + x);
        subtract = x: modify ({ input ? 0 }: input - x);

        append  = suffix: modify ({ input ? [] }: input  ++ suffix);
        prepend = prefix: modify ({ input ? [] }: prefix ++ input );

        prefixWith = separator: prefix: modify ({ input ? "" }:
          if input == "" then prefix else "${prefix}${separator}${input}"
        );

        suffixWith = separator: suffix: modify ({ input ? "" }:
          if input == "" then suffix else "${input}${separator}${suffix}"
        );

        prefix = prefixWith "";
        suffix = suffixWith "";

        prefixLines = prefixWith "\n";
        suffixLines = suffixWith "\n";

        prefixWords = prefixWith " ";
        suffixWords = suffixWith " ";
      };

    in
      { lib =
              libWith { }
          //  lib.genAttrs lib.systems.flakeExposed (system:
                libWith { inherit system; }
              );

        checks = lib.genAttrs lib.systems.flakeExposed (system:
          let
            pkgs = nixpkgs.legacyPackages."${system}";

            extract = f: pkgs.appendOverlays [ f ];

            failures =
              with (self.lib."${system}");

            lib.debug.runTests {
              testEmptyOverride = {
                expr = override { } { };

                expected = { };
              };

              testFreshAttribute = {
                expr = override { foo = set 2; } { };

                expected = { foo = 2; };
              };

              testMultipleAttributes = {
                expr = override { foo = set 2; bar = set 3; } { };

                expected = { foo = 2; bar = 3; };
              };

              testAttributeOverride = {
                expr = override { foo = set 3; } { foo = 2; };

                expected = { foo = 3; };
              };

              testFreshNestedAttribute = {
                expr = override { foo.bar = set 2; } { };

                expected = { foo.bar = 2; };
              };

              testFreshSiblingAttribute = {
                expr = override { foo.baz = set 3; } { foo.bar = 2; };

                expected = { foo = { bar = 2; baz = 3; }; };
              };

              testMapAbsent = {
                expr = override { foo."*" = add 1; } { };

                expected = { foo = [ ]; };
              };

              testMapPresent = {
                expr = override { foo."*" = add 1; } { foo = [ 2 3 5 ]; };

                expected = { foo = [ 3 4 6 ]; };
              };

              testNameAbsent = {
                expr = override { foo."<name>" = add 1; } { };

                expected = { foo = { }; };
              };

              testNamePresent = {
                expr = override { foo."<name>" = add 1; } { foo = { x = 2; y = 3; }; };

                expected = { foo = { x = 3; y = 4; }; };
              };

              testModifyAbsent = {
                expr =
                  override { foo = modify ({ input ? 0 }: input + 3); } { };

                expected = { foo = 3; };
              };

              testModifyPresent = {
                expr =
                  override { foo = modify ({ input ? 0 }: input + 3); } { foo = 2; };
                expected = { foo = 5; };
              };

              testAddAbsent = {
                expr = override { foo = add 2; } { };

                expected = { foo = 2; };
              };

              testAddPresent = {
                expr = override { foo = add 3; } { foo = 2; };

                expected = { foo = 5; };
              };

              testSubtractAbsent = {
                expr = override { foo = subtract 2; } { };

                expected = { foo = -2; };
              };

              testSubtractPresent = {
                expr = override { foo = subtract 3; } { foo = 2; };

                expected = { foo = -1; };
              };

              testPrependAbsent = {
                expr = override { foo = prepend [ 2 3 ]; } { };

                expected = { foo = [ 2 3 ]; };
              };

              testPrependPresent = {
                expr = override { foo = prepend [ 2 3 ]; } { foo = [ 5 ]; };

                expected = { foo = [ 2 3 5 ]; };
              };

              testAppendAbsent = {
                expr = override { foo = append [ 3 5 ]; } { };

                expected = { foo = [ 3 5 ]; };
              };

              testAppendPresent = {
                expr = override { foo = append [ 3 5 ]; } { foo = [ 2 ]; };

                expected = { foo = [ 2 3 5 ]; };
              };

              testPrefixAbsent = {
                expr = override { foo = prefix "A"; } { };

                expected = { foo = "A"; };
              };

              testPrefixPresent = {
                expr = override { foo = prefix "A"; } { foo = "B"; };

                expected = { foo = "AB"; };
              };

              testSuffixAbsent = {
                expr = override { foo = suffix "B"; } { };

                expected = { foo = "B"; };
              };

              testSuffixPresent = {
                expr = override { foo = suffix "B"; } { foo = "A"; };

                expected = { foo = "AB"; };
              };

              testPrefixWordsAbsent = {
                expr = override { foo = prefixWords "A"; } { };

                expected = { foo = "A"; };
              };

              testPrefixWordsPresent = {
                expr = override { foo = prefixWords "A"; } { foo = "B"; };

                expected = { foo = "A B"; };
              };

              testSuffixWordsAbsent = {
                expr = override { foo = suffixWords "B"; } { };

                expected = { foo = "B"; };
              };

              testSuffixWordsPresent = {
                expr = override { foo = suffixWords "B"; } { foo = "A"; };

                expected = { foo = "A B"; };
              };

              testPrefixLinesAbsent = {
                expr = override { foo = prefixLines "A"; } { };

                expected = { foo = "A"; };
              };

              testPrefixLinesPresent = {
                expr = override { foo = prefixLines "A"; } { foo = "B"; };

                expected = { foo = "A\nB"; };
              };

              testSuffixLinesAbsent = {
                expr = override { foo = suffixLines "B"; } { };

                expected = { foo = "B"; };
              };

              testSuffixLinesPresent = {
                expr = override { foo = suffixLines "B"; } { foo = "A"; };

                expected = { foo = "A\nB"; };
              };

              testPrefixWithAbsent = {
                expr = override { foo = prefixWith "." "A"; } { };

                expected = { foo = "A"; };
              };

              testPrefixWithPresent = {
                expr = override { foo = prefixWith "." "A"; } { foo = "B"; };

                expected = { foo = "A.B"; };
              };

              testSuffixWithAbsent = {
                expr = override { foo = suffixWith "." "B"; } { };

                expected = { foo = "B"; };
              };

              testSuffixWithPresent = {
                expr = override { foo = suffixWith "." "B"; } { foo = "A"; };

                expected = { foo = "A.B"; };
              };

              testPkgsNoop = {
                expr = (extract (final: override { })).dhall.name;

                expected = "dhall-1.42.3";
              };

              testOverridePname = {
                expr =
                  (extract (final: override {
                    dhall.overrideAttrs.pname = set "dhall-ng";
                  })).dhall.name;

                expected = "dhall-ng-1.42.3";
              };

              testOverridePhase = {
                expr =
                  (extract (final: override {
                    dhall.overrideAttrs.patchPhase =
                      suffixLines "echo 'end of patchPhase'";
                  })).dhall.patchPhase;

                expected = "echo 'end of patchPhase'";
              };

              testOverrideHaskellPackageSet = {
                expr =
                  (extract (final: override {
                    haskellPackages.override.overrides = set (hfinal: override {
                      dhall.overrideCabal.pname = set "dhall-ng";
                    });
                  })).dhall.name;

                expected = "dhall-ng-1.42.3";
              };

              testFinal = {
                expr =
                  (extract (final: override {
                    nix-serve = set final.nix-serve-ng;

                    nix-serve-ng.overrideAttrs.name = set "best-nix-serve";
                  })).nix-serve.name;

                expected = "best-nix-serve";
              };

              testPotpourri = {
                expr =
                  let
                    final = extract (final: override {
                      dhall.overrideAttrs.nativeBuildInputs."*".overrideAttrs.env.FOO = set 1;
                    });

                  in
                    (builtins.head final.dhall.nativeBuildInputs).env.FOO;

                expected = 1;
              };
            };

          in
            { tests =
                if failures == []
                then pkgs.runCommand "override-utils-tests" { } ''
                  touch $out
                ''
                else throw ''
                  override-utils: Test failures

                  ${lib.generators.toPretty { } failures}
                '';
            }
        );
      };
}
