/* ms_rt/process.h: the child-process natives of @std/process (runtime/std/process_spawn.c over libuv): `run`, `spawn`
 * and the Subprocess handle, and `replace`. Fallible functions return a status (0 ok, otherwise the runtime's STATUS_*
 * code; STATUS_FAILED carries its text through `err`) and write their result through `out` only on success. `Stdio`
 * arguments are the case index of the enum: 0 pipe, 1 inherit, 2 null. A Subprocess handle (`object`) is an MsObj whose `drop`
 * kills the child's group, waits for it and frees it. Symbols are listed in runtime/symbols/process.txt. */
/* ms: domain process */
#ifndef MS_RT_PROCESS_H
#define MS_RT_PROCESS_H

#include "ms_rt/base.h"
#include "ms_rt/string.h"

/* CommandOutput flattened: the exit code (-1 when a signal ended the child), the captured streams and the peak
 * resident set size in bytes (0 when unknown). */
typedef struct MsCommandOut {
    int64_t exit_code;
    MsVec out;
    MsVec err;
    int64_t max_resident_bytes;
} MsCommandOut;

/* ms-sig: msstd_process_command_run(program: *const StrVal, arguments: *const VecVal, input: *const VecVal, has_max: HasRaw, max: i64, has_timeout: HasRaw, timeout_ns: i64, has_cwd: HasRaw, cwd: *const StrVal, env_names: *const VecVal, env_values: *const VecVal, out: *mut CommandOut, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_command_run(const MsStr *program, const MsVec *arguments, const MsVec *input, uint8_t has_max, int64_t max, uint8_t has_timeout, int64_t timeout_ns, uint8_t has_cwd, const MsStr *cwd, const MsVec *env_names, const MsVec *env_values, MsCommandOut *out, MsStr *err);
/* ms-sig: msstd_process_command_spawn(program: *const StrVal, arguments: *const VecVal, stdin: i64, stdout: i64, stderr: i64, has_cwd: HasRaw, cwd: *const StrVal, env_names: *const VecVal, env_values: *const VecVal, out: *mut *mut ObjCell<Child>, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_command_spawn(const MsStr *program, const MsVec *arguments, int64_t stdin_mode, int64_t stdout_mode, int64_t stderr_mode, uint8_t has_cwd, const MsStr *cwd, const MsVec *env_names, const MsVec *env_values, MsObj **out, MsStr *err);
/* ms-sig: msstd_process_replace(program: *const StrVal, arguments: *const VecVal, env_names: *const VecVal, env_values: *const VecVal, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_replace(const MsStr *program, const MsVec *arguments, const MsVec *env_names, const MsVec *env_values, MsStr *err);
/* ms-sig: msstd_process_subprocess_close(handle h: *mut ObjCell<Child>) @domain=process */
void msstd_process_subprocess_close(MsObj *object);
/* ms-sig: msstd_process_subprocess_kill(handle h: *mut ObjCell<Child>) @domain=process */
void msstd_process_subprocess_kill(MsObj *object);
/* ms-sig: msstd_process_subprocess_max_resident(handle h: *const ObjCell<Child>) -> i64 @domain=process */
int64_t msstd_process_subprocess_max_resident(MsObj *object);
/* ms-sig: msstd_process_subprocess_stream_id(handle h: *mut ObjCell<Child>, which: i64) -> i64 @domain=process */
int64_t msstd_process_subprocess_stream_id(MsObj *object, int64_t which);
/* ms-sig: msstd_process_subprocess_terminate(handle h: *mut ObjCell<Child>) @domain=process */
void msstd_process_subprocess_terminate(MsObj *object);
/* ms-sig: msstd_process_subprocess_wait(handle h: *mut ObjCell<Child>, has_timeout: HasRaw, timeout_ns: i64, out: *mut i64, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_subprocess_wait(MsObj *object, uint8_t has_timeout, int64_t timeout_ns, int64_t *out, MsStr *err);

#endif
