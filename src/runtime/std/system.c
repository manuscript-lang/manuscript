/* The @std/os/system natives. Every query is one libuv call (uv_os_*, uv_cpu_info, uv_interface_addresses,
 * uv_get_*_memory, uv_uptime, uv_loadavg, uv_available_parallelism), so the same code serves Linux, macOS and
 * Windows. Nothing here parks or keeps state: a native takes a snapshot, copies it into runtime values and
 * releases what libuv allocated. Text from the host must be UTF-8, otherwise the call reports
 * MS_STATUS_UNSUPPORTED. */

#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include <string.h>
#include <uv.h>
#if defined(_WIN32)
#include <iphlpapi.h>
#else
#include <net/if.h>
#endif

#include "base/alloc.h"
#include "base/list.h"
#include "base/utf8.h"
#include "runtime/std/status.h"
#include "runtime/std/system.h"

_Static_assert(sizeof(MsSystemInfo) == 40, "SystemInfoOut layout");
_Static_assert(sizeof(MsUserInfo) == 64, "UserInfoOut layout");
_Static_assert(sizeof(MsMetrics) == 64, "MetricsOut layout");

enum {
  HOST_TEXT_CAPACITY = 1024,
  NANOS_PER_SECOND = 1000000000,
  PRIORITY_HIGHEST = -20,
  PRIORITY_LOWEST = 19,
  ADDRESS_TEXT_CAPACITY = 64,
  MAC_BYTES = 6,
  MAC_TEXT_CAPACITY = 18,
};

/* ---- failures ---- */

/* Ends a failed native: stores the failure's text in `err` (empty unless `text`) and returns `status`. */
static uint8_t fail_with(uint8_t status, const char *text, MsString *err) {
  if (err != NULL) {
    *err = text == NULL ? ms_string_empty() : ms_string_from_span(ms_span_of_text(text));
  }
  return status;
}

/* The status of a libuv error: the ones callers act on keep their meaning, the rest carry libuv's text. */
static uint8_t fail_uv(int code, MsString *err) {
  switch (code) {
  case UV_EINVAL:
    return fail_with(MS_STATUS_INVALID_INPUT, NULL, err);
  case UV_ESRCH:
  case UV_ENOENT:
    return fail_with(MS_STATUS_NOT_FOUND, NULL, err);
  case UV_EPERM:
  case UV_EACCES:
    return fail_with(MS_STATUS_PERMISSION_DENIED, NULL, err);
  case UV_ENOSYS:
  case UV_ENOTSUP:
    return fail_with(MS_STATUS_UNSUPPORTED, NULL, err);
  default:
    return fail_with(MS_STATUS_FAILED, uv_strerror(code), err);
  }
}

/* ---- values ---- */

/* Stores `text` (NUL-terminated) in `out`. False, with `out` untouched, when it is not UTF-8. */
MS_NODISCARD static bool string_out(const char *text, MsString *out) {
  const MsSpan span = ms_span_of_text(text);
  if (!ms_utf8_is_valid(span.ptr, span.len)) {
    return false;
  }
  *out = ms_string_from_span(span);
  return true;
}

/* Stores `text` as a string, or fails with MS_STATUS_UNSUPPORTED. */
static uint8_t text_result(const char *text, MsString *out, MsString *err) {
  return string_out(text, out) ? MS_STATUS_OK : fail_with(MS_STATUS_UNSUPPORTED, NULL, err);
}

/* `text` with the blanks around it dropped (uname fields end with a newline on some hosts). */
static void trim_blanks(char *text) {
  size_t length = ms_span_of_text(text).len;
  while (length > 0 && (text[length - 1] == ' ' || text[length - 1] == '\n' || text[length - 1] == '\t')) {
    length--;
  }
  text[length] = '\0';
}

/* ---- constants of the target ---- */

#if defined(_WIN32)
#define OS_NAME "windows"
#define OS_CODE 2
#define NULL_DEVICE "\\\\.\\nul"
#define END_OF_LINE "\r\n"
#elif defined(__APPLE__)
#define OS_NAME "darwin"
#define OS_CODE 1
#define NULL_DEVICE "/dev/null"
#define END_OF_LINE "\n"
#elif defined(__linux__)
#define OS_NAME "linux"
#define OS_CODE 0
#define NULL_DEVICE "/dev/null"
#define END_OF_LINE "\n"
#else
#define OS_NAME "linux"
#define OS_CODE 3
#define NULL_DEVICE "/dev/null"
#define END_OF_LINE "\n"
#endif

#if defined(__aarch64__) || defined(_M_ARM64)
#define ARCHITECTURE_NAME "arm64"
#else
#define ARCHITECTURE_NAME "amd64"
#endif

static void static_text(const char *text, MsString *out) {
  *out = ms_string_from_span(ms_span_of_text(text));
}

void msstd_system_endianness(MsString *out) {
  const uint16_t probe = 1;
  uint8_t first = 0;
  memcpy(&first, &probe, 1);
  static_text(first == 1 ? "LE" : "BE", out);
}

void msstd_system_end_of_line(MsString *out) {
  static_text(END_OF_LINE, out);
}

void msstd_system_dev_null(MsString *out) {
  static_text(NULL_DEVICE, out);
}

int64_t msstd_system_os(void) {
  return OS_CODE;
}

/* ---- host names ---- */

uint8_t msstd_system_hostname(MsString *out, MsString *err) {
  char name[UV_MAXHOSTNAMESIZE];
  size_t size = sizeof name;
  const int code = uv_os_gethostname(name, &size);
  return code < 0 ? fail_uv(code, err) : text_result(name, out, err);
}

/* One field of uname. */
typedef enum { UNAME_RELEASE, UNAME_VERSION, UNAME_MACHINE } UnameField;

static uint8_t uname_result(UnameField field, MsString *out, MsString *err) {
  uv_utsname_t names;
  const int code = uv_os_uname(&names);
  if (code < 0) {
    return fail_uv(code, err);
  }
  char *text = names.machine;
  switch (field) {
  case UNAME_RELEASE:
    text = names.release;
    break;
  case UNAME_VERSION:
    text = names.version;
    break;
  case UNAME_MACHINE:
    break;
  }
  trim_blanks(text);
  return text_result(text, out, err);
}

uint8_t msstd_system_os_release(MsString *out, MsString *err) {
  return uname_result(UNAME_RELEASE, out, err);
}

uint8_t msstd_system_os_version(MsString *out, MsString *err) {
  return uname_result(UNAME_VERSION, out, err);
}

uint8_t msstd_system_machine(MsString *out, MsString *err) {
  return uname_result(UNAME_MACHINE, out, err);
}

/* ---- users ---- */

uint8_t msstd_system_home_directory(MsString *out, MsString *err) {
  char home[HOST_TEXT_CAPACITY];
  size_t size = sizeof home;
  const int code = uv_os_homedir(home, &size);
  return code < 0 ? fail_uv(code, err) : text_result(home, out, err);
}

/* An id as the language reads it: -1 where libuv has none (Windows reports the maximum value). */
static int64_t id_value(unsigned long id) {
  return id == (unsigned long)-1 ? -1 : (int64_t)id;
}

static void user_free(MsUserInfo *user) {
  ms_string_release(&user->username);
  ms_string_release(&user->home);
  ms_string_release(&user->shell);
}

uint8_t msstd_system_user_info(MsUserInfo *out, MsString *err) {
  uv_passwd_t passwd;
  const int code = uv_os_get_passwd(&passwd);
  if (code < 0) {
    return fail_uv(code, err);
  }
  MsUserInfo user = {.uid = id_value(passwd.uid), .gid = id_value(passwd.gid)};
  const char *shell = passwd.shell != NULL ? passwd.shell : "";
  const bool converted = string_out(passwd.username, &user.username) &&
                         string_out(passwd.homedir, &user.home) && string_out(shell, &user.shell);
  uv_os_free_passwd(&passwd);
  if (!converted) {
    user_free(&user);
    return fail_with(MS_STATUS_UNSUPPORTED, NULL, err);
  }
  *out = user;
  return MS_STATUS_OK;
}

/* ---- priorities ---- */

/* The process a priority call names: 0 is the caller, a negative or oversized id is invalid. */
MS_NODISCARD static bool process_id(int64_t pid, uv_pid_t *out) {
  if (pid < 0 || pid > INT32_MAX) {
    return false;
  }
  *out = (uv_pid_t)pid;
  return true;
}

uint8_t msstd_system_get_priority(int64_t pid, int64_t *out, MsString *err) {
  uv_pid_t process = 0;
  if (!process_id(pid, &process)) {
    return fail_with(MS_STATUS_INVALID_INPUT, NULL, err);
  }
  int priority = 0;
  const int code = uv_os_getpriority(process, &priority);
  if (code < 0) {
    return fail_uv(code, err);
  }
  *out = priority;
  return MS_STATUS_OK;
}

uint8_t msstd_system_set_priority(int64_t pid, int64_t priority, MsString *err) {
  uv_pid_t process = 0;
  if (!process_id(pid, &process) || priority < PRIORITY_HIGHEST || priority > PRIORITY_LOWEST) {
    return fail_with(MS_STATUS_INVALID_INPUT, NULL, err);
  }
  const int code = uv_os_setpriority(process, (int)priority);
  return code < 0 ? fail_uv(code, err) : MS_STATUS_OK;
}

/* ---- records in lists ---- */

/* One CpuInfo as compiled code lays the record out. */
typedef struct CpuRow {
  MsString model;
  int64_t speed_mhz, user, nice, system, idle, irq;
} CpuRow;

/* One NetworkInterface: `family` is the case index of IpFamily (0 for IPv4, 1 for IPv6). */
typedef struct InterfaceRow {
  MsString name;
  MsString address;
  MsString netmask;
  int64_t family;
  MsString mac;
  uint8_t internal;
  int64_t scope_id;
} InterfaceRow;

_Static_assert(sizeof(CpuRow) == 64, "CpuOut layout");
_Static_assert(sizeof(InterfaceRow) == 88, "InterfaceOut layout");

static void interface_row_drop(InterfaceRow *row) {
  ms_string_release(&row->name);
  ms_string_release(&row->address);
  ms_string_release(&row->netmask);
  ms_string_release(&row->mac);
}

/* ---- CPUs ---- */

/* The logical CPU count: what libuv lists (online processors, whatever the affinity mask says). */
static int64_t cpu_count(void) {
  uv_cpu_info_t *cpus = NULL;
  int count = 0;
  if (uv_cpu_info(&cpus, &count) < 0) {
    return 1;
  }
  uv_free_cpu_info(cpus, count);
  return count > 0 ? count : 1;
}

void msstd_system_info(MsSystemInfo *out) {
  static_text(OS_NAME, &out->os);
  static_text(ARCHITECTURE_NAME, &out->architecture);
  out->cpu_count = cpu_count();
}

uint8_t msstd_system_cpus(MsBytes *out, MsString *err) {
  uv_cpu_info_t *cpus = NULL;
  int count = 0;
  const int code = uv_cpu_info(&cpus, &count);
  if (code < 0) {
    return fail_uv(code, err);
  }
  for (int i = 0; i < count; i++) {
    if (!ms_utf8_is_valid(ms_span_of_text(cpus[i].model).ptr, ms_span_of_text(cpus[i].model).len)) {
      uv_free_cpu_info(cpus, count);
      return fail_with(MS_STATUS_UNSUPPORTED, NULL, err);
    }
  }
  *out = (MsBytes){0};
  ms_list_reserve(out, sizeof(CpuRow), (size_t)count);
  for (int i = 0; i < count; i++) {
    const uv_cpu_info_t *cpu = &cpus[i];
    CpuRow row = {
        .speed_mhz = cpu->speed,
        .user = (int64_t)cpu->cpu_times.user,
        .nice = (int64_t)cpu->cpu_times.nice,
        .system = (int64_t)cpu->cpu_times.sys,
        .idle = (int64_t)cpu->cpu_times.idle,
        .irq = (int64_t)cpu->cpu_times.irq,
    };
    static_text(cpu->model, &row.model);
    ms_list_push(out, sizeof row, &row);
  }
  uv_free_cpu_info(cpus, count);
  return MS_STATUS_OK;
}

/* ---- metrics ---- */

static int64_t clamp_to_int64(uint64_t value) {
  return value > (uint64_t)INT64_MAX ? INT64_MAX : (int64_t)value;
}

/* The host's free memory is what new allocations can use, so libuv's one figure serves both fields. */
uint8_t msstd_system_metrics(MsMetrics *out, MsString *err) {
  double uptime = 0;
  const int code = uv_uptime(&uptime);
  if (code < 0) {
    return fail_uv(code, err);
  }
  double load[3] = {0, 0, 0};
  uv_loadavg(load);
  const int64_t free_memory = clamp_to_int64(uv_get_free_memory());
  *out = (MsMetrics){
      .total_memory = clamp_to_int64(uv_get_total_memory()),
      .free_memory = free_memory,
      .available_memory = free_memory,
      .uptime_nanos = (int64_t)(uptime * NANOS_PER_SECOND),
      .load_1 = load[0],
      .load_5 = load[1],
      .load_15 = load[2],
      .available_parallelism = uv_available_parallelism(),
  };
  return MS_STATUS_OK;
}

/* ---- network interfaces ---- */

/* The address in `address` as text; false when libuv cannot print it. */
MS_NODISCARD static bool address_text(const uv_interface_address_t *item, bool netmask, char *text,
                                      size_t size) {
  const struct sockaddr *socket =
      netmask ? (const struct sockaddr *)&item->netmask : (const struct sockaddr *)&item->address;
  if (socket->sa_family == AF_INET6) {
    const struct sockaddr_in6 *v6 = netmask ? &item->netmask.netmask6 : &item->address.address6;
    return uv_ip6_name(v6, text, size) == 0;
  }
  const struct sockaddr_in *v4 = netmask ? &item->netmask.netmask4 : &item->address.address4;
  return uv_ip4_name(v4, text, size) == 0;
}

/* The hardware address as `aa:bb:cc:dd:ee:ff`; empty for an interface without one (loopback reports zeros).
 */
static void mac_text(const char *physical, char *text) {
  static const char digits[] = "0123456789abcdef";
  bool any = false;
  size_t length = 0;
  for (size_t i = 0; i < MAC_BYTES; i++) {
    const uint8_t byte = (uint8_t)physical[i];
    any = any || byte != 0;
    if (i > 0) {
      text[length++] = ':';
    }
    text[length++] = digits[byte >> 4];
    text[length++] = digits[byte & 15];
  }
  text[any ? length : 0] = '\0';
}

/* The row of one libuv address, its text owned by the row. False when a name is not UTF-8 or an address
 * cannot be printed; nothing is then owned. */
MS_NODISCARD static bool interface_row(const uv_interface_address_t *item, int64_t scope_id,
                                       InterfaceRow *row) {
  char address[ADDRESS_TEXT_CAPACITY];
  char netmask[ADDRESS_TEXT_CAPACITY];
  char mac[MAC_TEXT_CAPACITY];
  if (!address_text(item, false, address, sizeof address) ||
      !address_text(item, true, netmask, sizeof netmask) ||
      !ms_utf8_is_valid(ms_span_of_text(item->name).ptr, ms_span_of_text(item->name).len)) {
    return false;
  }
  mac_text(item->phys_addr, mac);
  *row = (InterfaceRow){
      .family = ((const struct sockaddr *)&item->address)->sa_family == AF_INET6 ? 1 : 0,
      .internal = item->is_internal != 0,
      .scope_id = scope_id,
  };
  static_text(item->name, &row->name);
  static_text(address, &row->address);
  static_text(netmask, &row->netmask);
  static_text(mac, &row->mac);
  return true;
}

/* The index each address reports: the system's index of its interface, or its position when the host has
 * none. */
static int64_t scope_of(const uv_interface_address_t *item, int position) {
  const uint32_t index = if_nametoindex(item->name);
  return index != 0 ? (int64_t)index : (int64_t)position + 1;
}

/* Orders `order` (positions into `scopes`) by scope, keeping the host's order among equal scopes. */
static void order_by_scope(size_t *order, const int64_t *scopes, size_t count) {
  for (size_t i = 1; i < count; i++) {
    const size_t moving = order[i];
    size_t at = i;
    while (at > 0 && scopes[order[at - 1]] > scopes[moving]) {
      order[at] = order[at - 1];
      at--;
    }
    order[at] = moving;
  }
}

/* Every address must convert before any row is pushed, so a failure leaves `out` untouched and leaks nothing.
 */
static bool all_convertible(const uv_interface_address_t *items, int count) {
  for (int i = 0; i < count; i++) {
    InterfaceRow row;
    if (!interface_row(&items[i], 0, &row)) {
      return false;
    }
    interface_row_drop(&row);
  }
  return true;
}

uint8_t msstd_system_network_interfaces(MsBytes *out, MsString *err) {
  uv_interface_address_t *items = NULL;
  int count = 0;
  const int code = uv_interface_addresses(&items, &count);
  if (code < 0) {
    return fail_uv(code, err);
  }
  if (!all_convertible(items, count)) {
    uv_free_interface_addresses(items, count);
    return fail_with(MS_STATUS_UNSUPPORTED, NULL, err);
  }
  const size_t total = (size_t)count;
  size_t order_bytes = 0;
  size_t scope_bytes = 0;
  if (!ms_size_mul(total + 1, sizeof(size_t), &order_bytes) ||
      !ms_size_mul(total + 1, sizeof(int64_t), &scope_bytes)) {
    uv_free_interface_addresses(items, count);
    return fail_with(MS_STATUS_FAILED, "too many network interfaces", err);
  }
  size_t *order = ms_alloc(order_bytes);
  int64_t *scopes = ms_alloc(scope_bytes);
  for (size_t i = 0; i < total; i++) {
    order[i] = i;
    scopes[i] = scope_of(&items[i], (int)i);
  }
  order_by_scope(order, scopes, total);
  *out = (MsBytes){0};
  ms_list_reserve(out, sizeof(InterfaceRow), total);
  for (size_t i = 0; i < total; i++) {
    InterfaceRow row;
    if (interface_row(&items[order[i]], scopes[order[i]], &row)) {
      ms_list_push(out, sizeof row, &row);
    }
  }
  ms_free(order);
  ms_free(scopes);
  uv_free_interface_addresses(items, count);
  return MS_STATUS_OK;
}
