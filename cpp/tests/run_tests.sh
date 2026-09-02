#!/usr/bin/env bash
# Builds and runs the shared-core golden tests.
set -euo pipefail

cd "$(dirname "$0")"

BUILD_DIR="${TMPDIR:-/tmp}/jetmarkdown-tests"
mkdir -p "$BUILD_DIR"

clang -c -O1 -o "$BUILD_DIR/md4c.o" ../md4c/md4c.c

clang++ -std=c++17 -O1 -Wall -Wextra \
  -o "$BUILD_DIR/parser_tests" \
  parser_tests.cpp \
  ../core/Parser.cpp \
  ../core/Preprocess.cpp \
  ../core/InlineExtensions.cpp \
  ../core/AstJson.cpp \
  ../core/AstSerializer.cpp \
  "$BUILD_DIR/md4c.o"

"$BUILD_DIR/parser_tests"
