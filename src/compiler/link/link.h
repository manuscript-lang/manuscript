/* compiler/link/link.h: the last step of a build, joining the program's object file and the runtime into an
 * executable with the pinned lld.
 *
 * Linux links against stand-ins for glibc 2.28's shared libraries made from the table of its exports, so the
 * build machine's glibc is not the program's minimum; with `musl` it links static over musl's startup files.
 * macOS links over text stubs of the system libraries; Windows over the mingw-w64 CRT. `lld` runs as a child process. */
#ifndef MS_COMPILER_LINK_LINK_H
#define MS_COMPILER_LINK_LINK_H

#include "base/strbuild.h"

typedef struct LinkOptions {
  MsSpan lld;   /* the `lld` executable */
  MsSpan llvm;  /* the shared LLVM library, already loaded, that makes the glibc stubs in this process */
  MsSpan files; /* the directory with the startup files, runtime libraries and the glibc export table */
  bool strip;   /* drop the symbol table */
  bool musl;    /* static musl instead of the glibc 2.28 stubs; the inputs must be the musl runtime */
} LinkOptions;

typedef struct LinkRequest {
  MsSpan object;        /* the program's object file */
  const MsSpan *inputs; /* borrowed: the runtime archive and any `--link` files, in order */
  size_t input_count;
  MsSpan output;        /* the executable to write */
} LinkRequest;

/* Links the request. On failure `why` gets the reason, with the linker's output and advice. */
MS_NODISCARD MS_NONNULL bool link_executable(const LinkOptions *options, const LinkRequest *request,
                                             MsStrBuild *why);

#endif
