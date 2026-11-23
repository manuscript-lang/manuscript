/* compiler/link/glibc_stubs.h: stand-ins for glibc 2.28's shared libraries, so a program links against the
 * 2.28 ABI whatever glibc the build machine has. They are generated once from the table of exports
 * (`glibc.symbols`: `soname version name kind [size [alias-of]]` per line) with `llc` and `lld`. */
#ifndef MS_COMPILER_LINK_GLIBC_STUBS_H
#define MS_COMPILER_LINK_GLIBC_STUBS_H

#include "compiler/link/link.h"

/* The libraries in the order a program lists them: libpthread first, so that before glibc 2.34 its
 * definitions of names libc also exports win, as with `cc -lpthread`. */
extern const char *const link_glibc_libraries[];
extern const size_t link_glibc_library_count;

/* Makes the stubs in `files/glibc` when they are not there yet and leaves their directory in `*directory`.
 * A concurrent build never sees a partial set. False with `why` set when they cannot be made. */
MS_NODISCARD MS_NONNULL bool link_glibc_stubs(const LinkOptions *options, MsString *directory, MsStrBuild *why);

#endif
