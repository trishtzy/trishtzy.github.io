---
layout: post
title:  "Contributing to Nixpkgs Part 2"
---

**Table of Contents**
- [Upgrading old packages](#upgrading-old-packages)
  - [Add a local patch file](#add-a-local-patch-file)
  - [Find and replace code with `substituteInPlace`](#find-and-replace-code-with-substituteinplace)
  - [Submit patch upstream and pull to nixpkgs](#submit-patch-upstream-and-pull-to-nixpkgs)
    - [torproject/stem](#torprojectstem)
- [Footnotes](#footnotes)


## Upgrading old packages

There are many programs that become unmaintained due to whatever reason. This causes downstream builds like nixpkgs to fail. As other programs progress and evolve, attrition rate increases. In most operating systems, old programs are entirely removed and become unsupported.

One of the ways to support old programs in modern systems like NixOS is to contribute to upstream packages or create a patch in nixpkgs.

Here are three ways you can implement patches in nixpkgs.

### Add a local patch file

Add a local patch like [NixOS/nixpkgs PR#186349](https://github.com/NixOS/nixpkgs/pull/186349)[^1] if the package can't be built specifically on NixOS.

### Find and replace code with [`substituteInPlace`](https://nixos.org/manual/nixpkgs/stable/#fun-substituteInPlace)

```nix
# https://github.com/NixOS/nixpkgs/blob/4275fc290aaecb6072abcdfc75741373ecfa0fdc/pkgs/tools/misc/xflux/gui.nix#L31C3-L33C12
postPatch = ''
     substituteInPlace src/fluxgui/xfluxcontroller.py \
       --replace "pexpect.spawn(\"xflux\"" "pexpect.spawn(\"${xflux}/bin/xflux\""
  '';
```

This is usually used when you want to replace file paths across many files in the nix store. [Mic92](https://discourse.nixos.org/u/Mic92), NixOS release manager, explains it best [here](https://discourse.nixos.org/t/when-to-use-substituteinplace-functions-vs-a-patch/11073/2).

### Submit patch upstream and pull to nixpkgs

#### [torproject/stem](https://github.com/torproject/stem)

stem package has [discussions about project maintenance](https://github.com/torproject/stem/issues/154) and it doesn't seem to have a conclusion yet. What we do know is, the [build](https://hydra.nixos.org/build/258236266) breaks on hydra CI and it breaks other packages that depends on it, like [torrequest](https://hydra.nixos.org/build/258310228#tabs-summary).

How do we understand more about the failure? We can run nix build to see the output error messages.
```bash
$ nix-build -A python312Packages.stem
...
======================================================================
ERROR: test_index_malformed_compression
----------------------------------------------------------------------
Traceback (most recent call last):
  File "/private/tmp/nix-build-python3.12-stem-1.8.3-unstable-2024-02-13.drv-0/source/test/unit/descriptor/collector.py", line 126, in test_index_malformed_compression
    self.assertRaisesRegexp(OSError, 'Failed to decompress as %s' % compression, collector.index, compression)
    ^^^^^^^^^^^^^^^^^^^^^^^
AttributeError: '_TestWrapper' object has no attribute 'assertRaisesRegexp'. Did you mean: 'assertRaisesRegex'?

====
```

After investigating, it is revealed Python3 has deprecated `assertRaisesRegexp` in its `unittest` library. But `torproject/stem` supports both Python2 and 3.

In this case, we should make a PR contribution to `torproject/stem` (see [PR#155](https://github.com/torproject/stem/pull/155)). We replace all instances of `assertRaisesRegexp` with `assertRaisesRegex` and add this check to support Python2.

```python
# Allow test cases to run on both Python2 and Python3
if not hasattr(TestCase, 'assertRaisesRegex'):
    TestCase.assertRaisesRegex = TestCase.assertRaisesRegexp
```

Then in `default.nix`, you can use [fetchpatch](https://nixos.org/manual/nixpkgs/stable/#fetchpatch) attribute to *fetch* from remote repository into nix build.

```nix
  patches = [
    # fixes deprecated test assertion, assertRaisesRegexp in python 3
    (fetchpatch {
      url = "https://github.com/trishtzy/stem/commit/d5012a1039f05c69ebe832723ce96ecbe8f79fe1.patch";
      hash = "sha256-ozOTx4/c86sW/9Ss5eZ6ZxX63ByJT5x7JF6wBBd+VFY=";
    })
  ];
```
From [NixOS/nixpkgs PR#311118](https://github.com/NixOS/nixpkgs/pull/311118)

Run nix build again.

```bash
$ nix-build -A python312Packages.stem
...
Executing pythonImportsCheckPhase
/nix/store/3qk6z4zfp1n62qmsf1h09shs91f95bjg-python3.12-stem-1.8.3-unstable-2024-02-13
```

The build suceeds! And now, in a [newer hydra evaluation](https://hydra.nixos.org/eval/1806276#tabs-now-succeed), you'll be able to see `python312Packages.stem.*` is newly succeeded. Even better, any packages depending on `stem` that failed, like [torrequest build](https://hydra.nixos.org/build/259631481), succeeds too.[^2]


# Footnotes

[^1]: You should read the linked issue [#186294](https://github.com/NixOS/nixpkgs/issues/186294) for context
[^2]: A big thanks to [@RaghavSood](https://github.com/RaghavSood) who gave guidance on this nixpkg contribution and the previous too.
