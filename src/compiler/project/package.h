/* compiler/project/package.h: package dependencies: the spec a dependency value pins, the lock file, the package
 * cache and the content hash. Port of crates/ms-driver/src/project/packages.rs. */
#ifndef MS_PROJECT_PACKAGE_H
#define MS_PROJECT_PACKAGE_H

#include "base/arena.h"
#include "base/safe.h"

/* Whether `text` is `len` lowercase hexadecimal digits. */
bool ms_package_is_hex(MsSpan text, size_t len);

/* A dependency value is `url#tag`: an `https://` or `file://` URL, never one that starts with `-` or names another
 * git transport, and a tag or commit that is not an option or a path. On failure `*why` says what is wrong. */
MS_NODISCARD bool ms_package_check_spec(MsArena *arena, MsSpan spec, MsSpan *why);

#endif
