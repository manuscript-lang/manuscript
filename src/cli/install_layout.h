/* cli/install_layout.h: where an installed `ms` finds the files it links programs with.
 *
 * A package unpacks to `<prefix>/bin/ms` and `<prefix>/lib/ms/`: `bin/lld`, `lib/<libLLVM>` (the shared LLVM library ms optimizes and generates code
 * with in-process), `files/` (the startup files),
 * and `runtime/` and `runtime-static/`, each with an `archives` file naming the runtime archives in link order, one
 * per line. A build tree has no `<prefix>/lib/ms`, so ms keeps the paths it was built with; the environment variables
 * (MS_LLVM, MS_LLD, MS_FILES, MS_RUNTIME) still override both. */
#ifndef MS_CLI_INSTALL_LAYOUT_H
#define MS_CLI_INSTALL_LAYOUT_H

#include "base/strbuild.h"

/* Appends `<prefix>/lib/ms` for the running executable when that directory holds `files`; false otherwise. */
MS_NODISCARD MS_NONNULL bool ms_install_root(MsStrBuild *root);
/* Appends the path of the tool `name` (`lld`) under `root`, with the host's executable suffix. */
MS_NONNULL void ms_install_tool(MsSpan root, const char *name, MsStrBuild *out);
/* Appends the path of the shared LLVM library under `root` (`lib/libLLVM.so`, `lib/libLLVM.dylib` or `bin/LLVM-C.dll`). */
MS_NONNULL void ms_install_llvm(MsSpan root, MsStrBuild *out);
/* Appends the path of the shared Cranelift library under `root` (`lib/libcranelift.so`, `lib/libcranelift.dylib` or
 * `bin/cranelift.dll`). */
MS_NONNULL void ms_install_cranelift(MsSpan root, MsStrBuild *out);
/* Appends the absolute archive paths of the dynamic or static runtime under `root`, separated like MS_RUNTIME. */
MS_NODISCARD MS_NONNULL bool ms_install_runtime(MsSpan root, bool static_libc, MsStrBuild *out);

#endif
