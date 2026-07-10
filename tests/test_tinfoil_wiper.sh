#!/usr/bin/env bash
# Dependency-free unit tests for tinfoil_wiper's pure helper functions.
# Sourcing the tool defines its functions without running main() (main is
# guarded behind a BASH_SOURCE/$0 check).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HERE/../tinfoil_wiper"

# shellcheck source=/dev/null
source "$TARGET"
set +e # the sourced tool enables `set -e`; the harness handles failures itself

tests_run=0
tests_failed=0
ok()   { tests_run=$((tests_run + 1)); printf 'ok %d - %s\n' "$tests_run" "$1"; }
fail() { tests_run=$((tests_run + 1)); tests_failed=$((tests_failed + 1)); printf 'not ok %d - %s\n' "$tests_run" "$1"; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# --- region_is_zero -------------------------------------------------------
# A correct erase-verification predicate: true only when every sampled byte
# is 0x00. The original script's `hexdump -C | grep -E '[^00]'` reported
# non-zero (== "verification failed") even on perfectly zeroed input.

zero="$tmpdir/zero.bin"
dd if=/dev/zero of="$zero" bs=1024 count=64 status=none
if region_is_zero "$zero" 0 65536; then
  ok "region_is_zero: true on all-zero region"
else
  fail "region_is_zero: true on all-zero region"
fi

mixed="$tmpdir/mixed.bin"
dd if=/dev/zero of="$mixed" bs=1024 count=64 status=none
printf '\xff' | dd of="$mixed" bs=1 seek=40000 count=1 conv=notrunc status=none
if region_is_zero "$mixed" 0 65536; then
  fail "region_is_zero: detects a single non-zero byte"
else
  ok "region_is_zero: detects a single non-zero byte"
fi

# A non-zero byte outside the sampled window must not trip the check.
if region_is_zero "$mixed" 0 1024; then
  ok "region_is_zero: honors the sample window (offset/length)"
else
  fail "region_is_zero: honors the sample window (offset/length)"
fi

# Sampling at a byte offset must see the non-zero byte at 40000.
if region_is_zero "$mixed" 39936 1024; then
  fail "region_is_zero: samples at a byte offset"
else
  ok "region_is_zero: samples at a byte offset"
fi

# An unreadable region must NOT be reported as zero (a failed read returns 2).
region_is_zero /nonexistent/path 0 4096
if [ "$?" -eq 2 ]; then
  ok "region_is_zero: unreadable path returns 'unreadable' (2), not zero"
else
  fail "region_is_zero: unreadable path returns 'unreadable' (2), not zero"
fi

# Root-sensitive temporary material must never use a caller-controlled runtime
# directory. Mock mktemp so this test creates no file.
untrusted_runtime="$tmpdir/user-runtime"
XDG_RUNTIME_DIR="$untrusted_runtime"
# shellcheck disable=SC2329
mktemp() { printf '%s\n' "$1"; }
export XDG_RUNTIME_DIR
export -f mktemp
keyfile=$(create_keyfile); rc=$?
unset -f mktemp
unset XDG_RUNTIME_DIR
if [ "$rc" -eq 0 ]; then
  case "$keyfile" in
    /run/tinfoil.XXXXXX | /dev/shm/tinfoil.XXXXXX)
      ok "create_keyfile: ignores inherited XDG_RUNTIME_DIR"
      ;;
    *)
      fail "create_keyfile: ignores inherited XDG_RUNTIME_DIR (got '$keyfile')"
      ;;
  esac
else
  fail "create_keyfile: selects a system runtime directory"
fi

printf '\n%d/%d tests passed\n' "$((tests_run - tests_failed))" "$tests_run"
[ "$tests_failed" -eq 0 ]
