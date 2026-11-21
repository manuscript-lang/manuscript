/* runtime/std/process_env.h: the @std/process natives for the working directory and the environment
 * (src/runtime/std/process_env.c), on libuv. Fallible natives return a status (0 ok) and always fill `err`:
 * empty unless the status is MS_STATUS_FAILED, which carries the host's text. */
#ifndef MS_RUNTIME_STD_PROCESS_ENV_H
#define MS_RUNTIME_STD_PROCESS_ENV_H

#include "abi/status.h"
#include "base/bytes.h"
#include "base/map.h"
#include "base/string.h"

/* ms-sig: msstd_process_working_directory(out: *mut StrVal, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_working_directory(MsString *out, MsString *err);
/* ms-sig: msstd_process_change_directory(path: *const StrVal, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_change_directory(const MsString *path, MsString *err);
/* ms-sig: msstd_process_environment(out: *mut VecVal, out2: *mut VecVal, err: ErrSlot) -> u8 @domain=process
 */
uint8_t msstd_process_environment(MsBytes *names, MsBytes *values, MsString *err);
/* ms-sig: msstd_process_environment_map(out: *mut MapVal, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_environment_map(MsMap *out, MsString *err);
/* ms-sig: msstd_process_set_environment(name: *const StrVal, has_value: HasRaw, value: *const StrVal, err:
 * ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_set_environment(const MsString *name, uint8_t has_value, const MsString *value,
                                      MsString *err);
/* ms-sig: msstd_process_environment_is_set(name: *const StrVal) -> u8 @domain=process */
uint8_t msstd_process_environment_is_set(const MsString *name);

#endif
