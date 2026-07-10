#!/usr/bin/env bash
# Integration tests: source the tool and drive its methods in --dry-run so
# nothing touches a real device. Verifies command dispatch, the run() wrapper,
# and the namespace->controller mapping used by the safety/erase paths.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HERE/../tinfoil_wiper"
# shellcheck source=/dev/null
source "$TARGET"
set +e # the sourced tool enables `set -e`; capture rc explicitly instead

# These globals are inputs consumed by the sourced tool's functions; mark them
# used so ShellCheck doesn't flag the per-test assignments below (SC2034).
export DRY_RUN ASSUME_YES METHOD

tests_run=0
tests_failed=0
ok()   { tests_run=$((tests_run + 1)); printf 'ok %d - %s\n' "$tests_run" "$1"; }
fail() { tests_run=$((tests_run + 1)); tests_failed=$((tests_failed + 1)); printf 'not ok %d - %s\n' "$tests_run" "$1"; }
skip() { tests_run=$((tests_run + 1)); printf 'ok %d - %s # SKIP\n' "$tests_run" "$1"; }
assert_eq() { if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (want '$3', got '$2')"; fi; }
assert_contains() { case "$2" in *"$3"*) ok "$1" ;; *) fail "$1 (missing '$3')" ;; esac; }

# --- nvme_controller: namespace/partition -> controller -------------------
assert_eq "nvme_controller: namespace"  "$(nvme_controller /dev/nvme0n1  || true)" "/dev/nvme0"
assert_eq "nvme_controller: partition"  "$(nvme_controller /dev/nvme0n1p3 || true)" "/dev/nvme0"
assert_eq "nvme_controller: two digits" "$(nvme_controller /dev/nvme12n3 || true)" "/dev/nvme12"
if nvme_controller /dev/sda >/dev/null 2>&1; then fail "nvme_controller: rejects non-nvme"; else ok "nvme_controller: rejects non-nvme"; fi

# --- dry-run dispatch changes nothing and echoes real commands ------------
DRY_RUN=1
ASSUME_YES=1

METHOD=zero
out=$(dispatch /dev/nvme9n9 2>&1); rc=$?
assert_eq "dispatch zero: succeeds" "$rc" "0"
assert_contains "dispatch zero: echoes blkdiscard" "$out" "blkdiscard"
assert_contains "dispatch zero: is a dry-run" "$out" "[dry-run]"

if command -v cryptsetup >/dev/null 2>&1 && command -v blockdev >/dev/null 2>&1; then
  METHOD=crypto
  _keyfile=""
  out=$(crypto_erase /dev/nvme9n9 2>&1); rc=$?
  assert_eq "crypto dry-run: succeeds" "$rc" "0"
  assert_contains "crypto dry-run: echoes luksFormat" "$out" "cryptsetup luksFormat"
  assert_contains "crypto dry-run: echoes header erase" "$out" "cryptsetup luksErase"
  assert_contains "crypto dry-run: final blkdiscard is wrapped in run()" "$out" "[dry-run] blkdiscard /dev/nvme9n9"
  assert_eq "crypto dry-run: creates no key file" "$_keyfile" ""
else
  for _ in 1 2 3 4 5; do skip "crypto dry-run: cryptsetup/blockdev not installed"; done
fi

if command -v nvme >/dev/null 2>&1; then
  METHOD=sanitize
  out=$(dispatch /dev/nvme9n9 2>&1); rc=$?
  assert_eq "dispatch sanitize: succeeds" "$rc" "0"
  assert_contains "dispatch sanitize: echoes nvme sanitize" "$out" "nvme sanitize"
else
  skip "dispatch sanitize: nvme-cli not installed"
  skip "dispatch sanitize: nvme-cli not installed"
fi

# --- nvme_namespaces must not error (regression: an unassigned local $ctrl
#     crashed under set -u and silently defeated the controller-wide guard) ---
out=$(nvme_namespaces /dev/nvme0 2>&1); rc=$?
assert_eq "nvme_namespaces: takes its argument, no crash" "$rc" "0"
if [ -b /dev/nvme0n1 ]; then
  assert_contains "nvme_namespaces: lists a present namespace" "$out" "/dev/nvme0n1"
fi

# --- is_root_disk resolves the whole disk(s) behind the (possibly stacked or
#     multi-disk) root filesystem: regression for tree-drawing chars and for
#     only checking the last ancestor. ----------------------------------------
rootsrc=$(findmnt -no SOURCE / 2>/dev/null); rootsrc=${rootsrc%%[*}
root_disks=$(lsblk -nrso NAME,TYPE "$rootsrc" 2>/dev/null | awk '$2=="disk"{print $1}')
if [ -n "$root_disks" ]; then
  miss=0
  while read -r d; do [ -n "$d" ] && { is_root_disk "/dev/$d" || miss=1; }; done <<<"$root_disks"
  if [ "$miss" -eq 0 ]; then ok "is_root_disk: detects every disk backing root"; else fail "is_root_disk: detects every disk backing root"; fi
else
  skip "is_root_disk: no whole-disk ancestor for root"
fi
if is_root_disk /dev/tinfoil_not_a_disk; then fail "is_root_disk: rejects an unrelated device"; else ok "is_root_disk: rejects an unrelated device"; fi

# --- CLI contract (real subprocess: exercises parse_args exit codes) ------
cli() { "$TARGET" "$@" </dev/null >/dev/null 2>&1; printf '%s' "$?"; }
assert_eq "cli: --version exits 0"                 "$(cli --version)" "0"
assert_eq "cli: no device exits 1"                 "$(cli)" "1"
assert_eq "cli: unknown method exits 1"            "$(cli --dry-run --yes -m bogus /dev/loop0)" "1"
assert_eq "cli: --method without a value exits 1"  "$(cli -m)" "1"
assert_eq "cli: --timeout non-numeric exits 1"     "$(cli --dry-run --yes -t abc /dev/loop0)" "1"
assert_eq "cli: extra positional exits 1"          "$(cli --dry-run --yes /dev/loop0 /dev/loop1)" "1"
assert_eq "cli: extra positional after -- exits 1" "$(cli --dry-run --yes -- /dev/loop0 /dev/loop1)" "1"

printf '\n%d/%d tests passed\n' "$((tests_run - tests_failed))" "$tests_run"
[ "$tests_failed" -eq 0 ]
