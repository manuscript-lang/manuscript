[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A Debug link is lld `-O0` on Linux and nothing else elsewhere

Verified (CI probe, 2026-11-25, median of 3 to 6 runs of `MS_BUILD_TIMES=1 ms build --build-type debug`): ELF lld's default `-O1` merges strings across the archives; `-O0` cuts the link of a 9 MB program from 62 to 48 ms and of hello from 30 to 26 ms (amd64 and arm64 alike). `--threads=1` adds nothing once `-O0` is set. The mingw flavor (`-O0`, `--threads=1`) changed nothing on Windows amd64; macOS is left as is. Do not add flags there without a CI probe that shows a gain.

`MS_BUILD_TIMES=1` prints codegen, object and link milliseconds of a build (`src/cli/pipeline.c`). Linking dominates a small Debug build (hello: front end 17, codegen 2, link 30), so measure it with this before changing the back end.

Apply when: changing linker flags, or looking for Debug build time.
