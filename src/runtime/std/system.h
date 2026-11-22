/* runtime/std/system.h: the @std/os/system natives (src/runtime/std/system.c) over libuv. Fallible functions
 * return a status (0 ok, otherwise the runtime's MS_STATUS_* code) and write their result through `out` only
 * on success; MS_STATUS_FAILED carries its text through `err`. Records cross as one record, or a list of
 * them, per call. Symbols are listed in src/runtime/symbols/system.txt. */
/* ms: domain system */
#ifndef MS_RUNTIME_STD_SYSTEM_H
#define MS_RUNTIME_STD_SYSTEM_H

#include "abi/status.h"
#include "base/bytes.h"
#include "base/map.h"
#include "base/string.h"

/* `SystemInfo`: the target's `os` and `architecture` names and the logical CPU count. */
typedef struct MsSystemInfo {
  MsString os;
  MsString architecture;
  int64_t cpu_count;
} MsSystemInfo;

/* `UserInfo`; the numeric ids read -1 where the host has none. */
typedef struct MsUserInfo {
  MsString username;
  int64_t uid;
  int64_t gid;
  MsString home;
  MsString shell;
} MsUserInfo;

/* `MetricsSnapshot`: the fields of `SystemMetrics` with the uptime in nanoseconds and the load averages
 * flattened. */
typedef struct MsMetrics {
  int64_t total_memory;
  int64_t free_memory;
  int64_t available_memory;
  int64_t uptime_nanos;
  double load_1;
  double load_5;
  double load_15;
  int64_t available_parallelism;
} MsMetrics;

/* ms-sig: msstd_system_constants(out: *mut MapVal) @domain=system */
void msstd_system_constants(MsMap *out);
/* ms-sig: msstd_system_cpus(out: *mut VecVal, err: ErrSlot) -> u8 @domain=system */
uint8_t msstd_system_cpus(MsBytes *out, MsString *err);
/* ms-sig: msstd_system_dev_null(out: *mut StrVal) @domain=system */
void msstd_system_dev_null(MsString *out);
/* ms-sig: msstd_system_end_of_line(out: *mut StrVal) @domain=system */
void msstd_system_end_of_line(MsString *out);
/* ms-sig: msstd_system_endianness(out: *mut StrVal) @domain=system */
void msstd_system_endianness(MsString *out);
/* ms-sig: msstd_system_get_priority(pid: i64, out: *mut i64, err: ErrSlot) -> u8 @domain=system */
uint8_t msstd_system_get_priority(int64_t pid, int64_t *out, MsString *err);
/* ms-sig: msstd_system_home_directory(out: *mut StrVal, err: ErrSlot) -> u8 @domain=system */
uint8_t msstd_system_home_directory(MsString *out, MsString *err);
/* ms-sig: msstd_system_hostname(out: *mut StrVal, err: ErrSlot) -> u8 @domain=system */
uint8_t msstd_system_hostname(MsString *out, MsString *err);
/* ms-sig: msstd_system_info(out: *mut SystemInfoOut) @domain=system */
void msstd_system_info(MsSystemInfo *out);
/* ms-sig: msstd_system_machine(out: *mut StrVal, err: ErrSlot) -> u8 @domain=system */
uint8_t msstd_system_machine(MsString *out, MsString *err);
/* ms-sig: msstd_system_metrics(out: *mut MetricsOut, err: ErrSlot) -> u8 @domain=system */
uint8_t msstd_system_metrics(MsMetrics *out, MsString *err);
/* ms-sig: msstd_system_network_interfaces(out: *mut VecVal, err: ErrSlot) -> u8 @domain=system */
uint8_t msstd_system_network_interfaces(MsBytes *out, MsString *err);
/* ms-sig: msstd_system_os() -> i64 @domain=system */
int64_t msstd_system_os(void);
/* ms-sig: msstd_system_os_release(out: *mut StrVal, err: ErrSlot) -> u8 @domain=system */
uint8_t msstd_system_os_release(MsString *out, MsString *err);
/* ms-sig: msstd_system_os_version(out: *mut StrVal, err: ErrSlot) -> u8 @domain=system */
uint8_t msstd_system_os_version(MsString *out, MsString *err);
/* ms-sig: msstd_system_set_priority(pid: i64, priority: i64, err: ErrSlot) -> u8 @domain=system */
uint8_t msstd_system_set_priority(int64_t pid, int64_t priority, MsString *err);
/* ms-sig: msstd_system_user_info(out: *mut UserInfoOut, err: ErrSlot) -> u8 @domain=system */
uint8_t msstd_system_user_info(MsUserInfo *out, MsString *err);

#endif
