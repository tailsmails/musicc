#!/usr/bin/env bash
export PS4='\033[0;33m+ >>>>> (${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }\033[0m'
set -xe

TEST_SCRIPT="./test_musicc.sh"
SRC_FILE="musicc.v"

if [ ! -f "$SRC_FILE" ]; then
    if [ -f "main.v" ]; then
        SRC_FILE="main.v"
    else
        exit 1
    fi
fi

chmod +x "$TEST_SCRIPT"

export DEBUG_OPTS="-keepc -cg -cflags -fno-omit-frame-pointer"
export VFLAGS="-cc clang -d no_backtrace -enable-globals -gc none"

v ${VFLAGS} ${DEBUG_OPTS} -cflags "-fsanitize=memory" -o musicc "$SRC_FILE"
touch musicc
MSAN_OPTIONS="halt_on_error=1" "$TEST_SCRIPT"
rm -f musicc

v ${VFLAGS} ${DEBUG_OPTS} -cflags "-fsanitize=undefined" -o musicc "$SRC_FILE"
touch musicc
UBSAN_OPTIONS="print_stacktrace=1:halt_on_error=1" "$TEST_SCRIPT"
rm -f musicc

v ${VFLAGS} ${DEBUG_OPTS} -cflags "-fsanitize=thread" -o musicc "$SRC_FILE"
touch musicc
TSAN_OPTIONS="halt_on_error=1" "$TEST_SCRIPT"
rm -f musicc

v ${VFLAGS} ${DEBUG_OPTS} -cflags "-fsanitize=address,pointer-compare,pointer-subtract" -o musicc "$SRC_FILE"
touch musicc
ASAN_OPTIONS="detect_leaks=0:halt_on_error=1" UBSAN_OPTIONS="print_stacktrace=1:halt_on_error=1" "$TEST_SCRIPT"
rm -f musicc
