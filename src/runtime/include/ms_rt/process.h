/* ms_rt/process.h: the process natives: working directory, environment, signals, identity, resource usage and title (src/runtime/std/process.c), and the child-process natives of @std/process (src/runtime/std/process_spawn.c over libuv): `run`, `spawn`
 * and the Subprocess handle, and `replace`. Fallible functions return a status (0 ok, otherwise the runtime's STATUS_*
 * code; STATUS_FAILED carries its text through `err`) and write their result through `out` only on success. `Stdio`
 * arguments are the case index of the enum: 0 pipe, 1 inherit, 2 null. A Subprocess handle (`object`) is an MsObj whose `drop`
 * kills the child's group, waits for it and frees it. Symbols are listed in src/runtime/symbols/process.txt. */
/* ms: domain process */
#ifndef MS_RT_PROCESS_H
#define MS_RT_PROCESS_H

#include "ms_rt/base.h"
#include "ms_rt/string.h"

typedef struct MsMap MsMap;

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
/* ms-sig: msstd_process_subprocess_pid(handle h: *const ObjCell<Child>) -> i64 @domain=process */
int64_t msstd_process_subprocess_pid(MsObj *object);
/* ms-sig: msstd_process_subprocess_stream_id(handle h: *mut ObjCell<Child>, which: i64) -> i64 @domain=process */
int64_t msstd_process_subprocess_stream_id(MsObj *object, int64_t which);
/* ms-sig: msstd_process_subprocess_terminate(handle h: *mut ObjCell<Child>) @domain=process */
void msstd_process_subprocess_terminate(MsObj *object);
/* ms-sig: msstd_process_subprocess_wait(handle h: *mut ObjCell<Child>, has_timeout: HasRaw, timeout_ns: i64, out: *mut i64, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_subprocess_wait(MsObj *object, uint8_t has_timeout, int64_t timeout_ns, int64_t *out, MsStr *err);

/* Process state, from src/runtime/std/process.c over libuv and src/runtime/sys. */
/* Flattened ResourceUsage: microseconds, bytes and counters, all 64-bit. */
typedef struct MsProcessResources {
    int64_t user_microseconds, system_microseconds, max_resident_bytes, minor_faults, major_faults;
    int64_t filesystem_reads, filesystem_writes, voluntary_switches, involuntary_switches;
} MsProcessResources;

/* Flattened CpuUsage. */
typedef struct MsProcessCpu {
    int64_t user_microseconds, system_microseconds;
} MsProcessCpu;

/* ms-sig: msstd_process_environment(out: *mut VecVal, out2: *mut VecVal, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_environment(MsVec *names, MsVec *values, MsStr *err);
/* ms-sig: msstd_process_set_environment(name: *const StrVal, has_value: HasRaw, value: *const StrVal, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_set_environment(const MsStr *name, uint8_t has_value, const MsStr *value, MsStr *err);
/* ms-sig: msstd_process_environment_is_set(name: *const StrVal) -> u8 @domain=process */
uint8_t msstd_process_environment_is_set(const MsStr *name);
/* ms-sig: msstd_process_working_directory(out: *mut StrVal, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_working_directory(MsStr *out, MsStr *err);
/* ms-sig: msstd_process_change_directory(path: *const StrVal, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_change_directory(const MsStr *path, MsStr *err);
/* ms-sig: msstd_process_send_signal(pid: i64, signal: i64, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_send_signal(int64_t pid, int64_t signal, MsStr *err);
/* ms-sig: msstd_process_groups(out: *mut VecVal, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_groups(MsVec *out, MsStr *err);
/* ms-sig: msstd_process_set_groups(groups: *const VecVal, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_set_groups(const MsVec *groups, MsStr *err);
/* ms-sig: msstd_process_initialize_groups(username: *const StrVal, gid: i64, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_initialize_groups(const MsStr *username, int64_t gid, MsStr *err);
/* ms-sig: msstd_process_umask(mask: i64, out: *mut i64, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_umask(int64_t mask, int64_t *out, MsStr *err);
/* ms-sig: msstd_process_set_identity(kind: *const StrVal, id: i64, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_set_identity(const MsStr *kind, int64_t id, MsStr *err);
/* ms-sig: msstd_process_title(out: *mut StrVal, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_title(MsStr *out, MsStr *err);
/* ms-sig: msstd_process_set_title(title: *const StrVal, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_set_title(const MsStr *title, MsStr *err);
/* ms-sig: msstd_process_constrained_memory(out: *mut i64, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_constrained_memory(int64_t *out, MsStr *err);
/* ms-sig: msstd_process_available_memory(out: *mut i64, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_available_memory(int64_t *out, MsStr *err);
/* ms-sig: msstd_process_resource_usage(out: *mut ResourceOut, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_resource_usage(MsProcessResources *out, MsStr *err);
/* ms-sig: msstd_process_cpu_usage(out: *mut CpuOut, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_cpu_usage(MsProcessCpu *out, MsStr *err);

/* Flattened ProcessInfo, in declaration order. `uid` and the other ids are -1 where the platform has none. */
typedef struct MsProcessInfo {
    int64_t pid, parent_pid;
    MsStr executable;
    MsVec arguments;
    MsStr os, architecture;
    int64_t uid, gid, effective_uid, effective_gid;
} MsProcessInfo;

/* Flattened MemoryUsage: heap bytes in use, the heap's size, the heap's system bytes, bytes outside the heap and the
 * resident set size. */
typedef struct MsProcessMemory {
    int64_t heap_used, heap_total, heap_system, external, resident;
} MsProcessMemory;

/* Flattened RuntimeCounts: the runtime's work counters. */
typedef struct MsProcessCounts {
    int64_t allocations, allocated_bytes, list_copies, list_copy_bytes, string_clones, string_clone_bytes, operations;
} MsProcessCounts;

/* ms-sig: msstd_process_info(out: *mut ProcessInfoOut, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_info(MsProcessInfo *out, MsStr *err);
/* ms-sig: msstd_process_memory_usage(out: *mut MemoryOut, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_memory_usage(MsProcessMemory *out, MsStr *err);
/* ms-sig: msstd_process_runtime_counts(out: *mut CountsOut) -> u8 @domain=process */
uint8_t msstd_process_runtime_counts(MsProcessCounts *out);
/* ms-sig: msstd_process_uptime() -> i64 @domain=process */
int64_t msstd_process_uptime(void);
/* ms-sig: msstd_process_elapsed(out: *mut i64) -> u8 @domain=process */
uint8_t msstd_process_elapsed(int64_t *out);
/* ms-sig: msstd_process_environment_map(out: *mut MapVal, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_environment_map(MsMap *out, MsStr *err);

#endif
