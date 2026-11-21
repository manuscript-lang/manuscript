# src/third_party

Vendored C libraries, pinned in `c-libs.lock` (version, tag, commit, SHA-256 of the vendored tree).

| Library | Version | Use |
| --- | --- | --- |
| mimalloc | 3.6.1 | Runtime allocator, bound through `ms_alloc_install` in `runtime/core/alloc.c`. CMake target `mimalloc`. |
| llhttp | 9.4.3 | HTTP parser for the net layer. CMake target `llhttp`. |

Check offline: `cmake -DSOURCE_DIR=. -P cmake/FetchCLibs.cmake` (also the `third_party_lock` ctest).
Update a pin: edit the tag and commit in the lock, run with `-DMODE=fetch`, then put the printed digest in the lock.
`ms_lint` skips this directory; do not edit vendored files by hand.
