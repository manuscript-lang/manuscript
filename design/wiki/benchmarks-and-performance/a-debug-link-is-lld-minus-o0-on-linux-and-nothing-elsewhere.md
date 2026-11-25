[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A Debug link is lld `-O0` on Linux and nothing else elsewhere

Verified (CI probe, 2026-11-25, median of 3 to 6 runs of `MS_BUILD_TIMES=1 ms build --build-type debug`): ELF lld's default `-O1` merges strings across the archives; `-O0` cuts the link of a 9 MB program from 62 to 48 ms and of hello from 30 to 26 ms (amd64 and arm64 alike). `--threads=1` adds nothing once `-O0` is set. The mingw flavor (`-O0`, `--threads=1`) changed nothing on Windows amd64; macOS lld takes 35 to 95 ms on arm64 (190 to 260 on Intel runners), and `--time-trace` shows no one lld phase to cut.

On macOS the larger step is `finish`: `dsymutil` plus reading the object's symbols took 115 to 157 ms of a 175 to 270 ms link on arm64 (155 to 290 ms on Intel). Only a debugger reads the dSYM, so `run`, `test` and `bench` (`MsLinkRequest.temporary`) skip it; `ms build` keeps it. Windows is all lld (70 ms for hello, 100 for a 5 MB program). Do not add other flags there without a CI probe that shows a gain.

`MS_BUILD_TIMES=1` prints codegen, object and link milliseconds of a build (`src/cli/pipeline.c`). Linking dominates a small Debug build (hello: front end 17, codegen 2, link 30), so measure it with this before changing the back end.

Apply when: changing linker flags, or looking for Debug build time.
