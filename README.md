# Tinfoil Wiper 🧹

Tinfoil Wiper securely erases an NVMe SSD. It prefers the drive controller's
own sanitize and format commands, which are the methods that actually reach
every flash cell, and falls back to a software crypto-erase when the hardware
commands are unavailable.

## Why not a multi-pass overwrite?

Multi-pass overwrite schemes such as the Gutmann method were designed for the
magnetic encoding of 1990s hard drives. They do not fit SSDs:

* An SSD's Flash Translation Layer remaps writes for wear leveling, so
  overwriting a logical block does not overwrite the physical cell that held
  the old data. Over-provisioned and retired cells keep their contents.
* Writing the whole visible capacity many times wears the drive and still
  cannot guarantee that remapped cells were touched.

NIST SP 800-88 Rev. 1 (Guidelines for Media Sanitization) therefore recommends
using the device's built-in sanitize or cryptographic-erase commands for flash
media. Tinfoil Wiper follows that guidance.

## Requirements

* A Linux system, run as root
* `nvme-cli` for the hardware methods (`nvme`)
* `util-linux` (`lsblk`, `findmnt`, `blockdev`, `blkdiscard`, `wipefs`)
* `cryptsetup` for the software crypto-erase fallback
* `coreutils` (`dd`, `tr`, `wc`)
* `gnugrep` (`grep`) and `gnused` (`sed`)

Only the tools for the method you actually use are required. A dry run makes
no changes to any device; it still runs read-only tools (`lsblk`, `blockdev`)
to describe the target and prints the exact commands a real run would execute.

## Nix and NixOS

The flake exposes `packages.<system>.tinfoil-wiper`, a default package and app,
an overlay, and a NixOS module. Build and test the package directly with:

```bash
nix build
nix run . -- --version
nix flake check
```

Add it to a flake-based NixOS configuration as an input:

```nix
inputs.tinfoil-wiper = {
  url = "github:Bad3r/Tinfoil-Wiper";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Import the module into the target system and enable it:

```nix
{
  imports = [ inputs.tinfoil-wiper.nixosModules.default ];
  programs.tinfoil-wiper.enable = true;
}
```

Configurations that own their package options can consume the package directly:

```nix
environment.systemPackages = [
  inputs.tinfoil-wiper.packages.${pkgs.stdenv.hostPlatform.system}.tinfoil-wiper
];
```

The Nix package wraps a fixed runtime `PATH`, so the declared commands remain
available after `sudo` applies its secure path. It does not grant privileges:
real wipes still require an explicit `sudo tinfoil_wiper ...` invocation.

## Usage

```bash
sudo tinfoil_wiper /dev/nvme0n1            # auto-select the best method
sudo tinfoil_wiper --dry-run /dev/nvme0n1  # print the plan, change nothing
sudo tinfoil_wiper -m sanitize /dev/nvme0n1
```

The tool refuses to touch a device that is mounted, is used as swap, or backs
the running root filesystem unless you pass `--force`. Before erasing it prints
the device model, serial, and size, then asks you to retype the full device
path. Pass `--yes` to skip the prompt for automation.

NVMe Sanitize erases the entire controller, that is every namespace on the
drive, not just the node you name. So the hardware methods (and `auto`) accept
only a whole namespace such as `/dev/nvme0n1`, never a partition, and they check
every namespace on the controller for in-use state before proceeding. To wipe a
single partition, use `-m crypto` or `-m zero`.

### Options

```
-m, --method M   auto | sanitize | sanitize-block | format-crypto |
                 format-user | crypto | zero            (default: auto)
-y, --yes        skip the interactive confirmation
-n, --dry-run    print the commands that would run; change nothing
-f, --force      allow a mounted or root-backing device (dangerous)
-t, --timeout S  seconds to wait for a hardware sanitize (default: 3600)
-h, --help       show help
-V, --version    show version
```

### Methods

| Method           | What it does                                                        |
| ---------------- | ------------------------------------------------------------------- |
| `auto`           | sanitize (crypto, then block), then format, then software crypto    |
| `sanitize`       | NVMe Sanitize, crypto erase if supported else block erase           |
| `sanitize-block` | NVMe Sanitize, block erase                                          |
| `format-crypto`  | NVMe Format, cryptographic erase (one namespace, or all on FNA drives) |
| `format-user`    | NVMe Format, user-data erase (one namespace, or all on FNA drives)     |
| `crypto`         | LUKS2 with a throwaway key, overwrite once, then destroy the key    |
| `zero`           | `blkdiscard -z` (or `dd` zeros); weakest, use only as a last resort |

`auto` tries the strongest available method first and falls back on failure.

## How the software crypto-erase works

When no NVMe hardware erase is available, the `crypto` method:

1. Formats the device as LUKS2 with a random key read from `/dev/urandom`. The
   key is not printed; it is held in a temporary file under `/run` or `/dev/shm`
   and removed on exit.
2. Opens the volume and overwrites the entire mapping once, replacing any
   previous plaintext across the visible capacity.
3. Closes the volume and erases the LUKS header, discarding the key. The
   key destruction is what makes this a crypto-erase: without it the volume
   is unrecoverable.

This is far stronger than a plaintext overwrite, but like any software method it
cannot reach cells the controller has already remapped. Prefer the hardware
methods when the drive supports them.

## Verification

After the `zero` method, which writes zeros itself, the tool samples several
regions (start, quarter points, and the last megabyte) and confirms they read
back as all zeros, failing loudly if any sampled byte is non-zero or the device
cannot be read.

Sanitize, format, and crypto erase do not guarantee a zero read (a crypto erase
in particular does not), so those get a single advisory sample that reports what
the device now returns without treating non-zero data as an error. No software
check can prove that data is physically unrecoverable from the flash; treat
verification as a sanity check, not a guarantee.

## Testing

```bash
bash tests/test_tinfoil_wiper.sh   # pure helpers (verification predicate)
bash tests/test_dryrun.sh          # dry-run dispatch and safety mapping
shellcheck tinfoil_wiper tests/*.sh
nix flake check                    # package build, tests, and module evaluation
```

## Notes

* Erasing a disk is destructive and irreversible. Back up anything important
  first, and double-check the device path.
* This script is provided as-is, with no warranty of any kind. Use at your own
  risk.
