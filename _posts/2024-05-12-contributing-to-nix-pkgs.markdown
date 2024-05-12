---
layout: post
title:  "Contributing to Nixpkgs"
---

I've been starting to use [nix flake](https://nixos.wiki/wiki/Flakes) or [devenv](https://devenv.sh/) to manage my development environments. It saves me a lot of hassle when I need to develop on a new machine, which happened once (that's more than enough!) or when you've got an uncooperative teammate who decides to use a different psql version from the rest of the team and you got to upgrade yours to ensure generated files output the same version.

Regardless, nix flakes solves this problem. Everyone will now have the same dev environment (assuming you managed to convince the team to use nix flake). That means, the same psql version or any tooling needed.

I've been enjoying Flakes so much that a good friend of mine has encouraged me to contribute to Nixpkgs! So here's a guide if you ever want to help update an outdated package or even add one that does not exist in the repository.

**Table of Contents**
- [Upgrading an outdated upstream package](#upgrading-an-outdated-upstream-package)
    - [goose: 3.19.2 -\> 3.20.0](#goose-3192---3200)
    - [flyctl: 0.2.51 -\> 0.2.52](#flyctl-0251---0252)
- [Adding a new nix package](#adding-a-new-nix-package)
    - [binance-connector-python v3.7.0](#binance-connector-python-v370)
- [Footnotes](#footnotes)


# Upgrading an outdated upstream package

### [goose: 3.19.2 -> 3.20.0](https://github.com/NixOS/nixpkgs/pull/310792)

[goose](https://github.com/pressly/goose) is a Go migration tool that I use to manage database versioning and it has recently been updated to version 3.20. However `nixos-unstable` branch is on an older version:
```Nix
# https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/tools/misc/goose/default.nix#L9
buildGoModule rec {
  pname = "goose";
  version = "3.19.2";
```

1. First step is to fork the [NixOS/nixpkgs](https://github.com/NixOS/nixpkgs) repository.
   1. Setup your upstream branch:
      1. `git remote add upstream git@github.com:NixOS/nixpkgs.git`
      2. `git pull upstream master` (since there's likely a bunch of changes merged while cloning the repo)
2. In the forked repository, checkout to a new branch with this naming convention.
   1. `git checkout -b package-name/version`[^1]
3. Then update line 9 to version 3.20.0.
4. You will also want to replace one of the characters in `hash` and `vendorHash` with another random char just so `nix-build` regenerates a new hash for you to update.
5. Then run  `nix-build -A goose`
6. You will encounter something like:
   ```text
   error: hash mismatch in fixed-output derivation '/nix/store/k7yk2xdwl63hjnlwg5pgvc0zc6fab7kq-source.drv':
          specified: sha256-xGa3vZSFQ8Dgndc0qRnFnQwlU2hst6j3UFUXw+tfYR0=
              got:    sha256-DgxFczS2YAnicf8RTMf7gDzCtDyj/zqzrGfeb3YcYzg=
   ```
7. Copy `got` value and update it to `hash`.
8. Run `nix-build -A goose` again. This time, you realise it can't be built!
   ```text
   error: builder for '/nix/store/4xdw5n6j0z41yp5jn6pz6hdfq6bghm4b-goose-3.20.0-go-modules.drv' failed with exit code 1;
       last 6 log lines:
       > Running phase: unpackPhase
       > unpacking source archive /nix/store/sw0109pjb6yl8qnqxmvpnk2wx8c2ibrs-source
       > source root is source
       > Running phase: patchPhase
       > rm: cannot remove 'tests/e2e': No such file or directory
       > /nix/store/g3ikambclkcz7z9sxy1ijy8pxwbybvac-stdenv-darwin/setup: line 140: pop_var_context: head of shell_variables not a function context
       For full logs, run 'nix-store -l /nix/store/4xdw5n6j0z41yp5jn6pz6hdfq6bghm4b-goose-3.20.0-go-modules.drv'.
   error: 1 dependencies of derivation '/nix/store/7krgsihmn75nlflzdg1wxs6fg09vr7b8-goose-3.20.0.drv' failed to build
   ```

9. This line, `rm: cannot remove 'tests/e2e': No such file or directory`, tells you to look at the source code.
10. You debug by finding for suspect commit between the previous and latest version.
    1. [b2c483a](https://github.com/pressly/goose/commit/b2c483ada4b3450f4b95396455aaae33c42d2b78): looks like this commit removes the `tests/` folder and introduces `internal/testing/integration/`.
11. You update `postPatch` and run `nix-build` again.
12. This time it prompts you to update the second hash - `vendorHash`. Do the same in step 7.
13. Run `nix-build` again.
14. You get another error:
    ```
    error: builder for '/nix/store/m2ipqgjni8di8v2r99080h8ww2b2p68i-goose-3.20.0.drv' failed with exit code 1;
       last 25 log lines:
       > go: downloading ...
       > Building subPackage ./database
       > Building subPackage ./internal/cfg
       > Building subPackage ./internal/check
       > Building subPackage ./internal/dialect
       > Building subPackage ./internal/dialect/dialectquery
       > Building subPackage ./internal/migrationstats
       > Building subPackage ./internal/sqlparser
       > Building subPackage ./internal/testing/integration
       > main module (github.com/pressly/goose/v3) does not contain package github.com/pressly/goose/v3/internal/testing/integration
       For full logs, run 'nix-store -l /nix/store/m2ipqgjni8di8v2r99080h8ww2b2p68i-goose-3.20.0.drv'.
       ```
15. Looks like nix is building all of `goose/v3`. We should build only the main package and its dependencies.
    1.  You do that by using `subPackages` attribute.[^2]
          ```Nix
          subPackages = [
            "cmd/goose"
          ];
          ```
16. Run `nix-build -A goose` again.
17. This time it builds successfully!
```
➜  nixpkgs git:(goose/3.20.0) ✗ nix-build -A goose
/nix/store/gf3c6hhlmsqyff0kgq4318xcp8f3sr39-goose-3.20.0
```
18. You can find the build output in `./result` folder.
19. Run a quick test by using the output goose cli: `./result/bin/goose`
20. I try to check goose version:
```
➜  nixpkgs git:(goose/3.20.0) ✗ ./result/bin/goose -version
goose version: (devel)
```

21. Strangely it does not output version 3.20.0.
22. You check goose's source code and notice they are using `version` instead of `gooseVersion`.

    ```go
      // https://github.com/pressly/goose/commit/9c73699c6590b91215b4dd22a5ba32221bb7929d
      if *versionFlag {
        buildInfo, ok := debug.ReadBuildInfo()
        if ok && buildInfo != nil && buildInfo.Main.Version != "" {
          version = buildInfo.Main.Version
        }
        fmt.Printf("goose version: %s\n", strings.TrimSpace(version))
        return
      }
    ```

23. Replace `gooseVersion` in the link flag[^3] with the updated variable, `version`:

    ```diff
    diff --git a/pkgs/tools/misc/goose/default.nix b/pkgs/tools/misc/goose/default.nix
    index dcb6acec4d9e..994aa5df6ec5 100644
    --- a/pkgs/tools/misc/goose/default.nix
    +++ b/pkgs/tools/misc/goose/default.nix
    @@ -6,29 +6,31 @@
      ldflags = [
        "-s"
        "-w"
    -    "-X=main.gooseVersion=${version}"
    +    "-X=main.version=${version}"
      ];

      checkFlags = [
    ```

### [flyctl: 0.2.51 -> 0.2.52](https://github.com/NixOS/nixpkgs/pull/310803)

Fret not, there are other package upgrades that don't require debugging. For example, when I upgraded flyctl, it only requires version and hash update.

Going a little off tangent, here's an interesting fact: you can generate hash using `nix-hash`.
```bash
➜  nixpkgs git:(goose/3.20.0) ✗ nix-prefetch-url https://github.com/superfly/flyctl/archive/v0.2.52.tar.gz
path is '/nix/store/2vm781064v4wsc0n9d6l29cz9w5xrihd-v0.2.52.tar.gz'
00nrggb9p1mcjgf7zn1z35m5z2was8ygp67xz83k4wfjn4xrvxkg
# copy the output and call,
➜  nixpkgs git:(goose/3.20.0) ✗ nix-hash --to-sri  --type sha256 00nrggb9p1mcjgf7zn1z35m5z2was8ygp67xz83k4wfjn4xrvxkg
warning: The old format conversion sub commands of `nix hash` where deprecated in favor of `nix hash convert`.
sha256-b/adO7HScTIH+v2Y+zzSiotfahk/2H/ck6yGm9Z72QI=
```
This is an alternative to get the new `sha256` hash from the latest package version.

Finally, ensure you **follow commit convention** for package update type of changes:
```
(pkg-name): (from -> to | init at version | refactor | etc)

(Motivation for change. Link to release notes. Additional information.)
```

See [nixpkgs/pkgs/README.md#commit-conventions](https://github.com/NixOS/nixpkgs/blob/master/pkgs/README.md#commit-conventions)

# Adding a new nix package

### [binance-connector-python v3.7.0](https://github.com/binance/binance-connector-python)

1. Create `python-modules/binance-connector/` directory.
2. Copy any prior default.nix in any modules from `pkgs/development/python-modules` into `binance-connector/` folder. This will be your starting point.
3. Go to binance-connector source code and find out supported python versions from https://github.com/binance/binance-connector-python/blob/master/tox.ini.
4. Update information in `fetchFromGithub` attribute.
5. Trim any dependencies that you think are not necessary.
6. Run `nix-build -A python3Packages.binance-connector`. Notice the output error:
    ```bash
    ➜  nixpkgs git:(d216d87a311e) ✗ nix-build -A pythonPackages.binance-connector
    error: attribute 'binance-connector' in selection path 'pythonPackages.binance-connector' not found
    ```
7. You will need to modify `pkgs/top-level/python-packages.nix` to include `binance-connector`:
    ```Nix
    binance-connector = callPackage ../development/python-modules/binance-connector { };
    ```
8. Run nix build again.
9. You will likely get more errors compiling the module.
10. Some things you need to check in `binance-connector` source code,
    1.  [requirements/](https://github.com/binance/binance-connector-python/tree/master/requirements)
        1.  You only need dependencies in requirements.txt and requirements-test.txt
    2. Check how tests are run. If they require network access, disable them in default.nix.
    3. Check how the python modules are imported. In this case, we needed `binance.spot` and `binance.websocket`.
11. After wrapping up default.nix, you'll get a nice compiled output:
    ```bash
    ➜  nixpkgs git:(d216d87a311e) nix-build -A  python3Packages.binance-connector
    /nix/store/il7sxz41gn8fijjv3axfvm2m2vhgjn2a-python3.11-binance-connector-3.7.0
    ```
12. Lastly you might want to add yourself as a maintainer of this package.
    1. Modify `maintainers/maintainer-list.nix`. Insert your github handle according to alphabetical order.
    2. Find your githubId by going to https://api.github.com/users/ghost. Replace "ghost" with your github handle.
    3. More information about nixpkgs maintainers [here](https://github.com/NixOS/nixpkgs/blob/master/maintainers/README.md)


# Footnotes

[^1]: nixpkgs/CONTRIBUTING.md has a [Branch conventions section](https://github.com/NixOS/nixpkgs/blob/master/CONTRIBUTING.md#branch-conventions) that explains when to branch out from master or from staging branch. But I couldn't find any branch naming convention.
[^2]: [Nixpkgs Reference Manual: Go Attributes](https://nixos.org/manual/nixpkgs/unstable/#ssec-go-common-attributes)
[^3]: [https://pkg.go.dev/cmd/link](https://pkg.go.dev/cmd/link)
