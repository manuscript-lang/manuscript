# The C build compiles MIR text to an object in C

`ms_build_object` (`compiler/src/build/object.c`, `ms/build_object.h`) is the LLVM half of `ms build`, ported from the Rust `c_backend::compile`: `ms_backend_ir`, pinned `opt` (release only), `llc` to assembly, `ms_backend_tables`, the assembly wrapped as `module asm` lines, `llc` to an object. It takes the LLVM tools directory as an argument; fetching the pinned release stays with the link code. POSIX only; Windows builds still go through the Rust `ms`.

Prove it with `compiler/tests/build-object-diff.sh`: `ms emit` MIR text, C object, `cc -nostartfiles` against `libms_native.a` (with `--defsym=__dso_handle=0`), and compare output and status with `ms run` on `phase=run` fixtures. Do not compare `.ll` text with the Rust build's `ms-keep.ll`: `ms emit` prints different string-literal bytes from the in-process module, so literal padding differs although the programs behave the same.

Next steps for `ms_tool_build`: load and check (`ms_project_load_packages`, `ms_graph_check`), `ms_lower_program` to MIR text, this step, then the link (owned by the link thread). A program the C lowering declines is handed to the Rust `ms`.
