/* runtime/std/spawn.h: `spawn` and its Subprocess handle, and `replace`, for @std/process. A spawned child's piped
 * streams are plain descriptors that the program reads and writes through the stream table (streams.h). */
#ifndef MS_RUNTIME_STD_SPAWN_H
#define MS_RUNTIME_STD_SPAWN_H

#include "base/desc.h"
#include "base/list.h"
#include "base/string.h"

/* ms-sig: msstd_process_command_spawn(program: *const StrVal, arguments: *const VecVal, stdin: i64, stdout: i64, stderr: i64, has_cwd: HasRaw, cwd: *const StrVal, env_names: *const VecVal, env_values: *const VecVal, out: *mut *mut ObjCell<Child>, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_command_spawn(const MsString *program, const MsList *arguments, int64_t stdin_mode,
                                    int64_t stdout_mode, int64_t stderr_mode, uint8_t has_cwd, const MsString *cwd,
                                    const MsList *env_names, const MsList *env_values, MsObj **out, MsString *err);
/* The stream-table id of a piped stream (0 input, 1 output, 2 error): the first call moves the descriptor into the
 * table; -1 when the stream is not piped. */
/* ms-sig: msstd_process_subprocess_stream_id(handle h: *mut ObjCell<Child>, which: i64) -> i64 @domain=process */
int64_t msstd_process_subprocess_stream_id(MsObj *handle, int64_t which);
/* ms-sig: msstd_process_subprocess_max_resident(handle h: *const ObjCell<Child>) -> i64 @domain=process */
int64_t msstd_process_subprocess_max_resident(MsObj *handle);
/* ms-sig: msstd_process_subprocess_terminate(handle h: *mut ObjCell<Child>) @domain=process */
void msstd_process_subprocess_terminate(MsObj *handle);
/* ms-sig: msstd_process_subprocess_kill(handle h: *mut ObjCell<Child>) @domain=process */
void msstd_process_subprocess_kill(MsObj *handle);
/* Kills the group, joins the child and closes the pipes not yet handed to the table. Idempotent. */
/* ms-sig: msstd_process_subprocess_close(handle h: *mut ObjCell<Child>) @domain=process */
void msstd_process_subprocess_close(MsObj *handle);
/* Waits for the exit, or MS_STATUS_TIMED_OUT when `timeout_ns` passes first (the child keeps running). */
/* ms-sig: msstd_process_subprocess_wait(handle h: *mut ObjCell<Child>, has_timeout: HasRaw, timeout_ns: i64, out: *mut i64, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_subprocess_wait(MsObj *handle, uint8_t has_timeout, int64_t timeout_ns, int64_t *out,
                                      MsString *err);
/* Replaces the process image; returns only on failure. The environment is exactly the given variables. */
/* ms-sig: msstd_process_replace(program: *const StrVal, arguments: *const VecVal, env_names: *const VecVal, env_values: *const VecVal, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_replace(const MsString *program, const MsList *arguments, const MsList *env_names,
                              const MsList *env_values, MsString *err);

#endif
