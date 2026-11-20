/* ms_rt/process.h: the @std/process natives for the running process (runtime/std/process.c over libuv and
 * runtime/sys): working directory, environment, signals sent, identity, resource usage and title. Fallible functions
 * return a status (0 ok, otherwise the runtime's STATUS_* code; STATUS_FAILED carries its text through `err`) and
 * write results only on success. Symbols are listed in runtime/symbols/process.txt. */
#ifndef MS_RT_PROCESS_H
#define MS_RT_PROCESS_H

#include "ms_rt/base.h"
#include "ms_rt/string.h"

/* ms: domain process */

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

#endif
