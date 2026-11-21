/* runtime/std/process.h: the @std/process natives for the running process (process.c): signals sent, identity, resource
 * usage and title. Fallible natives return a status (0 ok) and always fill `err`: empty unless the status is
 * MS_STATUS_FAILED, which carries the host's text. The working directory and the environment are in process_env.h,
 * the signal watchers in signals.h. */
#ifndef MS_RUNTIME_STD_PROCESS_H
#define MS_RUNTIME_STD_PROCESS_H

#include "abi/status.h"
#include "base/bytes.h"
#include "base/string.h"

/* Flattened ResourceUsage: microseconds, bytes and counters, all 64-bit. */
typedef struct MsProcessResources {
  int64_t user_microseconds, system_microseconds, max_resident_bytes, minor_faults, major_faults;
  int64_t filesystem_reads, filesystem_writes, voluntary_switches, involuntary_switches;
} MsProcessResources;

/* Flattened CpuUsage. */
typedef struct MsProcessCpu {
  int64_t user_microseconds, system_microseconds;
} MsProcessCpu;

/* Flattened ProcessInfo, in declaration order. `uid` and the other ids are -1 where the platform has none. */
typedef struct MsProcessInfo {
  int64_t pid, parent_pid;
  MsString executable;
  MsList arguments;
  MsString os, architecture;
  int64_t uid, gid, effective_uid, effective_gid;
} MsProcessInfo;

/* Flattened MemoryUsage: heap bytes in use, the heap's size, the heap's system bytes, bytes outside the heap and the
 * resident set size. */
typedef struct MsProcessMemory {
  int64_t heap_used, heap_total, heap_system, external, resident;
} MsProcessMemory;

/* Flattened RuntimeCounts: the runtime's work counters, which only a counting build keeps (all zero otherwise). */
typedef struct MsProcessCounts {
  int64_t allocations, allocated_bytes, list_copies, list_copy_bytes, string_clones, string_clone_bytes, operations;
} MsProcessCounts;

/* ms-sig: msstd_process_send_signal(pid: i64, signal: i64, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_send_signal(int64_t pid, int64_t signal, MsString *err);
/* ms-sig: msstd_process_groups(out: *mut VecVal, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_groups(MsList *out, MsString *err);
/* ms-sig: msstd_process_set_groups(groups: *const VecVal, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_set_groups(const MsList *groups, MsString *err);
/* ms-sig: msstd_process_initialize_groups(username: *const StrVal, gid: i64, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_initialize_groups(const MsString *username, int64_t gid, MsString *err);
/* ms-sig: msstd_process_umask(mask: i64, out: *mut i64, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_umask(int64_t mask, int64_t *out, MsString *err);
/* ms-sig: msstd_process_set_identity(kind: *const StrVal, id: i64, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_set_identity(const MsString *kind, int64_t id, MsString *err);
/* ms-sig: msstd_process_title(out: *mut StrVal, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_title(MsString *out, MsString *err);
/* ms-sig: msstd_process_set_title(title: *const StrVal, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_set_title(const MsString *title, MsString *err);
/* ms-sig: msstd_process_constrained_memory(out: *mut i64, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_constrained_memory(int64_t *out, MsString *err);
/* ms-sig: msstd_process_available_memory(out: *mut i64, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_available_memory(int64_t *out, MsString *err);
/* ms-sig: msstd_process_resource_usage(out: *mut ResourceOut, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_resource_usage(MsProcessResources *out, MsString *err);
/* ms-sig: msstd_process_cpu_usage(out: *mut CpuOut, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_cpu_usage(MsProcessCpu *out, MsString *err);
/* ms-sig: msstd_process_info(out: *mut ProcessInfoOut, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_info(MsProcessInfo *out, MsString *err);
/* ms-sig: msstd_process_memory_usage(out: *mut MemoryOut, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_memory_usage(MsProcessMemory *out, MsString *err);
/* ms-sig: msstd_process_runtime_counts(out: *mut CountsOut) -> u8 @domain=process */
uint8_t msstd_process_runtime_counts(MsProcessCounts *out);
/* ms-sig: msstd_process_uptime() -> i64 @domain=process */
int64_t msstd_process_uptime(void);
/* ms-sig: msstd_process_elapsed(out: *mut i64) -> u8 @domain=process */
uint8_t msstd_process_elapsed(int64_t *out);

#endif
