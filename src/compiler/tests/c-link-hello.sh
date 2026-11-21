#!/bin/sh
# Hello world through the C object and link steps: `ms emit` MIR text, ms_build_object, ms_build_link, run. One cheap
# check that the C link works on the host (the corpus diff is src/compiler/tests/build-object-diff.sh).
# Needs a built `ms` whose cache holds the pinned lld and LLVM tools (any `ms build` fills it) and the runtime
# archive; run from the repository root. MS_LINKER_FILES names the linker files (the output of
# `cmake -DMS_MODE=linker -P cmake/BuildRuntime.cmake`); without it the cache's, which `ms build` extracts, are used.
#   sh src/compiler/tests/c-link-hello.sh [RUST_MS] [TOOLS_DIR] [RUNTIME_ARCHIVE] [WORKDIR]
set -eu
ms=${1:-target/release/ms}
tools_dir=${2:-target/cmake/tools/compiler}
runtime=${3:-target/ms-native/libms_native.a}
work=${4:-target/c-link-hello}
exe=
case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) exe=.exe ;; esac
if [ -n "${LOCALAPPDATA:-}" ] && [ -n "$exe" ]; then
	cache=$(cygpath -u "$LOCALAPPDATA")/ms
else
	cache=${XDG_CACHE_HOME:-$HOME/.cache}/ms
fi
llvm=$(ls -d "$cache"/llvm/*/ | head -n 1)
lld=$(ls "$cache"/lld/*/lld$exe | head -n 1)
files=${MS_LINKER_FILES:-$(ls -d "$cache"/linker/*/ 2>/dev/null | head -n 1 || true)}
mkdir -p "$work"
if [ -z "$files" ]; then
	files=$work/linker
	mkdir -p "$files"
fi
printf 'fn main() Int:\n    return 3\n' >"$work/hello.ms"
(cd "$work" && "$OLDPWD/$ms" emit hello.ms >hello.mir)
"$tools_dir/ms_build_object$exe" "$work/hello.mir" "$work/hello.o" "$llvm"
"$tools_dir/ms_build_link$exe" "$work/hello.o" "$work/hello$exe" "$lld" "$llvm/llc$exe" "$files" --input "$runtime"
status=0
"$work/hello$exe" || status=$?
if [ "$status" != 3 ]; then
	echo "c-link-hello: the program exited with $status, not 3" >&2
	exit 1
fi
echo "c-link-hello: ok"
