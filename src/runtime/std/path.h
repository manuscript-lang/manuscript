/* runtime/std/path.h: the @std/os/path natives (path_glob.c and path_brace.c). A glob is compiled once into a
 * handle, then matched against many values. Fallible functions return a status (0 ok, 1 InvalidInput, 11
 * Failed) and write their result through `out` only on success. `windows` selects the dialect: backslashes
 * read as slashes. The handle's header is a MsObj whose `drop` frees it. */
/* ms: domain path */
#ifndef MS_RUNTIME_STD_PATH_H
#define MS_RUNTIME_STD_PATH_H

#include "abi/status.h"
#include "base/desc.h"
#include "base/string.h"

/* ms-sig: msstd_path_host_windows() -> u8 @leaf */
uint8_t msstd_path_host_windows(void);
/* ms-sig: msstd_path_compile_glob(windows: u8, pattern: *const StrVal, out: *mut *mut ObjCell<CompiledGlob>)
 * -> u8 @leaf */
uint8_t msstd_path_compile_glob(uint8_t windows, const MsString *pattern, MsObj **out);
/* ms-sig: msstd_path_glob_matches(handle glob: *const ObjCell<CompiledGlob>, value: *const StrVal, out: *mut
 * u8)
 * -> u8 @leaf */
uint8_t msstd_path_glob_matches(const MsObj *glob, const MsString *value, uint8_t *out);

#endif
