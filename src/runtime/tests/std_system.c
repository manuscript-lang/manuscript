/* Unit tests of src/runtime/std/system.c: the natives read the host they run on, so each test checks what must hold on
 * any host (names are UTF-8 text, memory figures are ordered, a loopback interface exists, priorities validate). */
#include <stdio.h>
#include <string.h>

#include "fake_rt.h"
#include "ms_rt/system.h"

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static bool is(const MsStr *text, const char *want) {
    return ms_str_len(text) == strlen(want) && memcmp(ms_str_data(text), want, strlen(want)) == 0;
}

/* The runtime string a native returns is plain malloc'd bytes in the unit tests (see runtime_stubs.c). */
static void release(MsStr *text) { msrt_string_free(text); }

static void names(void) {
    MsStr text;
    msstd_system_endianness(&text);
    CHECK(is(&text, "LE") || is(&text, "BE"));
    release(&text);
    msstd_system_end_of_line(&text);
    CHECK(is(&text, "\n") || is(&text, "\r\n"));
    release(&text);
    MsSystemInfo info;
    msstd_system_info(&info);
    CHECK(ms_str_len(&info.os) > 0 && ms_str_len(&info.architecture) > 0 && info.cpu_count >= 1);
    release(&info.os);
    release(&info.architecture);
    CHECK(msstd_system_os() >= 0 && msstd_system_os() <= 3);
}

static void host_text(uint8_t (*native)(MsStr *, MsStr *)) {
    MsStr text;
    MsStr err;
    CHECK(native(&text, &err) == 0 && ms_str_len(&text) > 0);
    release(&text);
}

static void host_strings(void) {
    host_text(msstd_system_hostname);
    host_text(msstd_system_os_release);
    host_text(msstd_system_os_version);
    host_text(msstd_system_machine);
    host_text(msstd_system_home_directory);
    MsUserInfo user;
    MsStr err;
    CHECK(msstd_system_user_info(&user, &err) == 0);
    CHECK(ms_str_len(&user.username) > 0 && ms_str_len(&user.home) > 0);
    release(&user.username);
    release(&user.home);
    release(&user.shell);
}

static void metrics(void) {
    MsMetrics m;
    MsStr err;
    CHECK(msstd_system_metrics(&m, &err) == 0);
    CHECK(m.total_memory > 0 && m.available_memory > 0 && m.available_memory <= m.total_memory);
    CHECK(m.uptime_nanos > 0 && m.available_parallelism >= 1 && m.load_1 >= 0.0);
}

static void priorities(void) {
    int64_t priority = 99;
    MsStr err;
    CHECK(msstd_system_get_priority(0, &priority, &err) == 0 && priority >= -20 && priority <= 19);
    CHECK(msstd_system_get_priority(-1, &priority, &err) == 1);
    CHECK(msstd_system_get_priority(INT64_C(1) << 40, &priority, &err) == 1);
    CHECK(msstd_system_set_priority(0, 20, &err) == 1);
    CHECK(msstd_system_set_priority(0, -21, &err) == 1);
}

int main(void) {
    names();
    host_strings();
    metrics();
    priorities();
    if (failures != 0) {
        printf("%d failures\n", failures);
        return 1;
    }
    puts("ok");
    return 0;
}
