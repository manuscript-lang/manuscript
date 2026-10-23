#!/bin/sh
# Run before saving the cargo cache: drop the large linked binaries (the `ms` executables and the
# integration-test binaries that embed it, about 150-215 MB each). They depend on nearly every
# crate, so a run that restores them has almost always changed something below them and relinks
# anyway, while they make up about a fifth of the cache. Libraries, metadata and build-script
# output stay: those are what unchanged crates reuse.
set -eu
for dir in target/debug/deps target/release/deps; do
    [ -d "$dir" ] || continue
    find "$dir" -maxdepth 1 -type f -size +30M \
        ! -name '*.rlib' ! -name '*.rmeta' ! -name '*.so' ! -name '*.dylib' \
        ! -name '*.dll' ! -name '*.lib' ! -name '*.a' -delete
done
# The copies cargo places next to the build directories (hard links of the files above).
rm -f target/debug/ms target/debug/ms.exe target/release/ms target/release/ms.exe
du -sh target
