#!/usr/bin/env bash
# Exercise serial acceptance with controlled output, without downloading guests.
set -euo pipefail
cd "$(dirname "$0")/../.."
TEST_DIR=$(mktemp -d)
readonly TEST_DIR
trap 'rm -rf "$TEST_DIR"' EXIT

run_case() (
  local scenario=$1 expected=$2 result=0
  export QEMU_LOG_DIR="$TEST_DIR/$scenario"
  export ALPINE_BOOT_TIMEOUT_SECS=10
  if [[ "$scenario" = timeout || "$scenario" = shutdown-timeout ]]; then
    export ALPINE_BOOT_TIMEOUT_SECS=4
  fi
  # shellcheck source=.github/scripts/prototyper-alpine-boot.sh
  source .github/scripts/prototyper-alpine-boot.sh sbi
  mkdir -p "$LOG_DIR"
  RUN_DIR=$(mktemp -d "$TEST_DIR/input.XXXXXX")
  mkfifo "$RUN_DIR/input"
  exec 3<> "$RUN_DIR/input"
  (
    if [[ "$scenario" != missing-firmware ]]; then
      printf 'Hello RustSBI!\n'
    fi
    printf '%s\n' \
      'OpenRC 0.63 is starting up Linux 6.18.7-0-lts (riscv64)' \
      'Welcome to Alpine Linux 3.23' \
      'Kernel 6.18.7-0-lts on riscv64 (/dev/ttyS0)'
    if [[ "$scenario" = premature-marker ]]; then
      printf 'RUSTSBI-ALPINE-SMOKE-OK sbi\n'
      exit 0
    fi
    printf 'localhost login: '
    IFS= read -r login
    [[ "$login" = root ]] || exit 5
    printf '\nlocalhost:~# '
    IFS= read -r command
    [[ "$command" = 'if . /etc/os-release'* ]] || exit 6
    printf '\n'
    case "$scenario" in
      success) printf 'RUSTSBI-ALPINE-SMOKE-OK sbi\n' ;;
      serial-cr) printf 'RUSTSBI-ALPINE-SMOKE-OK sbi\r\r\n' ;;
      missing-marker) printf 'apk-tools 3.0\n' ;;
      echoed-marker) printf 'localhost:~# echo RUSTSBI-ALPINE-SMOKE-OK sbi\n' ;;
      wrong-path) printf 'RUSTSBI-ALPINE-SMOKE-OK edk2\n' ;;
      missing-firmware) printf 'RUSTSBI-ALPINE-SMOKE-OK sbi\n' ;;
      guest-failure) printf 'RUSTSBI-ALPINE-SMOKE-FAIL sbi\n' ;;
      panic)
        printf 'RUSTSBI-ALPINE-SMOKE-OK sbi\nKernel panic - not syncing\n'
        ;;
      nonzero-exit) printf 'RUSTSBI-ALPINE-SMOKE-OK sbi\n'; exit 7 ;;
      timeout) sleep 10 ;;
      shutdown-timeout) printf 'RUSTSBI-ALPINE-SMOKE-OK sbi\n'; sleep 10 ;;
      *) exit 4 ;;
    esac
  ) < "$RUN_DIR/input" > "$LOG_FILE" 2>&1 &
  QEMU_PID=$!
  wait_for_guest > "$LOG_DIR/result.txt" 2>&1 || result=$?
  if [[ "$expected" = pass && "$result" != 0 ]] ||
    [[ "$expected" = fail && "$result" = 0 ]]; then
    echo "FAIL: $scenario (expected=$expected, exit=$result)" >&2
    cat "$LOG_DIR/result.txt" "$LOG_FILE" >&2
    exit 1
  fi
  test -s "$LOG_FILE"
  cleanup
  test -s "$LOG_FILE"
  echo "PASS: $scenario ($expected, serial log retained)"
)

run_case success pass
run_case serial-cr pass
run_case premature-marker fail
run_case missing-marker fail
run_case echoed-marker fail
run_case wrong-path fail
run_case missing-firmware fail
run_case guest-failure fail
run_case panic fail
run_case nonzero-exit fail
run_case timeout fail
run_case shutdown-timeout fail
