/* compiler/link/sdk_stubs.h: text stubs of the macOS system libraries. Apple's SDK is not redistributable and
 * is absent without Xcode tools, so the stubs (`.tbd` files, which lld reads like the real ones) export
 * exactly the symbols the program and runtime import but do not define; dyld binds those names in the real
 * libSystem, Security, CoreFoundation and SystemConfiguration. */
#ifndef MS_COMPILER_LINK_SDK_STUBS_H
#define MS_COMPILER_LINK_SDK_STUBS_H

#include "base/strbuild.h"
#include "compiler/link/macho.h"

/* Writes the stubs under the directory `sdk` for the symbols of `symbols`. False with `why` set when a file
 * or directory cannot be written. */
MS_NODISCARD MS_NONNULL bool link_sdk_stubs(MsSpan sdk, const MachoSymbols *symbols, MsStrBuild *why);

#endif
