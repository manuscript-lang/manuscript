#!/bin/sh
# Builds the named CMake targets (tools and tests of src/compiler/, see cmake/MsCompiler.cmake) with the sanitizers on,
# into target/cmake/test (override with MS_C_BUILD); the scripts then run <build>/compiler/<target>.
# Usage (from the repository root): sh src/compiler/tests/cbuild.sh <target>...
set -eu
build=${MS_C_BUILD:-target/cmake/test}
cmake -S . -B "$build" -G Ninja -DMS_SANITIZE=ON > /dev/null
cmake --build "$build" --target "$@"
