#!/usr/bin/env bash
set -xe

INPUT_MCC="example.mcc"
OUTPUT_WAV="example"
SRC_FILE="musicc.v"
BIN_FILE="./musicc"

if [ ! -f "$SRC_FILE" ]; then
    if [ -f "main.v" ]; then
        SRC_FILE="main.v"
    else
        exit 1
    fi
fi

if [ ! -f "$BIN_FILE" ] || [ "$SRC_FILE" -nt "$BIN_FILE" ]; then
    rm -f "$BIN_FILE"
    v "$SRC_FILE" -o "$BIN_FILE"
fi

if [ ! -f "$INPUT_MCC" ]; then
    exit 1
fi

rm -f "$OUTPUT_WAV"
"$BIN_FILE" "$INPUT_MCC" "$OUTPUT_WAV"

if [ ! -f "$OUTPUT_WAV" ]; then
    exit 1
fi

FILE_SIZE=$(wc -c < "$OUTPUT_WAV")
if [ "$FILE_SIZE" -le 44 ]; then
    exit 1
fi

HEADER_RIFF=$(od -An -N4 -tx1 "$OUTPUT_WAV" | tr -d ' ')
if [ "$HEADER_RIFF" != "52494646" ]; then
    exit 1
fi

HEADER_WAVE=$(od -An -j8 -N4 -tx1 "$OUTPUT_WAV" | tr -d ' ')
if [ "$HEADER_WAVE" != "57415645" ]; then
    exit 1
fi

rm -f "$OUTPUT_WAV"
