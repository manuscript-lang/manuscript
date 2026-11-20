# mimalloc

mimalloc 2.3.2 (MIT, see LICENSE), the allocator behind `msrt_alloc` (runtime/core/alloc.c). Vendored from the
`c_src/mimalloc/v2` folder of the crates.io package `libmimalloc-sys` 0.1.49 (sha256
6a45a52f43e1c16f667ccfe4dd8c85b7f7c204fd5e3bf46c5b0db9a5c3c0b8e9, https://static.crates.io/crates/libmimalloc-sys/libmimalloc-sys-0.1.49.crate),
which bundles mimalloc 2.3.2 (the upstream v2 branch release); github.com was not reachable when it was added. Only
`include/`, `src/` (without the emscripten and wasi ports) and `LICENSE` are kept. Built as one object from
`src/static.c` (cmake/MsLibs.cmake). To bump it, replace these folders from the new release and update the version in
tools/repo-check/licenses.ms and documentation/contributing/dependency-licenses.json.
