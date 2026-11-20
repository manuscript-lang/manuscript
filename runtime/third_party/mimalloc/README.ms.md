# mimalloc

mimalloc 3.7.0 (MIT, see LICENSE), the allocator behind `msrt_alloc` (runtime/core/alloc.c) and the compiler's
malloc (compiler/include/ms_mimalloc.h). Vendored from upstream tag v3.7.0, commit
1ed67b5156a763441d2ec3c20221a7b3cd866129 (https://github.com/microsoft/mimalloc). Only `include/`, `src/` (without
the readme files and the Windows ETW manifest) and `LICENSE` are kept. Built as one object from `src/static.c`
(cmake/MsLibs.cmake). To bump it, replace these folders from the new release and update the version in
tools/repo-check/licenses.ms and documentation/contributing/dependency-licenses.json.
