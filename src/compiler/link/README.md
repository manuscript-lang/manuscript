# src/compiler/link

Links a program's object file and the runtime into an executable with the pinned lld, as child processes.
Allowed includes: see `src/layers.txt`.

- `link.h`, `link.c`: `link_executable`, the steps every host shares (prepare, run lld, finish).
- `object.c`: IR to object through the loaded LLVM library; with fault tables the assembly goes through `asm_tables` first.
- `asm_scan.c`, `asm_tables.c`: labels at functions and `.loc` places in the generated assembly, then the tables
  (`mir_fault_tables`) as assembly data defining `ms_tables`. ELF is tested; Mach-O and COFF are written, not run.
- `link_job.h`, `link_job.c`: the argument list and the advice for a missing symbol.
- `link_linux.c`, `glibc_stubs.c`, `glibc_table.c`: glibc 2.28 stand-in libraries made from `glibc.symbols`, or static musl.
- `link_macos.c`, `sdk_stubs.c`, `macho.c`: text stubs of the system libraries from the symbols the program imports; dSYM.
- `link_windows.c`: lld over the mingw-w64 CRT.

CMake builds only the files of the host. Tools run through `base/process`; nothing here calls libc directly.
