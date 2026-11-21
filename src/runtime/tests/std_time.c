/* The @std/time natives. The calendar records come from Go's time package (oracle/time_golden.txt); for UTC and fixed
 * offsets; the conformance fixtures cover IANA zones. Direct checks cover faults, parsing limits and formatting. */
#define _POSIX_C_SOURCE 200809L
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../std/time_internal.h"
#define MS_TEST_OWN_FAULTS
#include "fake_rt.h"

#ifdef _WIN32
#define setenv(name, value, overwrite) _putenv_s((name), (value))
#define unsetenv(name) _putenv_s((name), "")
#endif

static int failures;
#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            failures++; \
        } \
    } while (0)

static jmp_buf fault_jump;
static char fault_text[512];
static bool fault_expected;

_Noreturn void msrt_fault(const uint8_t *message, size_t length) {
    if (!fault_expected) {
        printf("UNEXPECTED FAULT %.*s\n", (int)length, (const char *)message);
        exit(1);
    }
    snprintf(fault_text, sizeof fault_text, "%.*s", (int)length, (const char *)message);
    longjmp(fault_jump, 1);
}

void msfault_raise(uint8_t kind, const void *message, size_t length) {
    (void)kind;
    msrt_fault(message, length);
}

static MsStr view(const char *text) {
    return (MsStr){.ptr_word = (uint8_t *)(uintptr_t)text, .tagged = strlen(text) | ((uint64_t)2 << 62)};
}

static char *owned(MsStr *s) {
    char *const copy = malloc(ms_str_len(s) + 1);
    memcpy(copy, ms_str_data(s), ms_str_len(s));
    copy[ms_str_len(s)] = 0;
    free(s->ptr_word);
    return copy;
}

/* Seconds east of UTC for `UTC`, the empty name and `+hh:mm`; false for an IANA name (zones are resolved in
 * Manuscript, so those run in the conformance fixtures). */
static bool offset_of(const char *zone, int64_t *offset) {
    if (zone[0] == 0 || strcmp(zone, "UTC") == 0) {
        *offset = 0;
        return true;
    }
    if ((zone[0] != '+' && zone[0] != '-') || strlen(zone) != 6 || zone[3] != ':') {
        return false;
    }
    const int64_t magnitude =
        ((zone[1] - '0') * 10 + (zone[2] - '0')) * 3600 + ((zone[4] - '0') * 10 + (zone[5] - '0')) * 60;
    *offset = zone[0] == '-' ? -magnitude : magnitude;
    return true;
}

static void golden_string(const char *line, char *got, size_t size) {
    char op[8];
    long long a[2];
    sscanf(line, "%7s %lld %lld", op, &a[0], &a[1]);
    const MsTimestamp t = {a[0], a[1]};
    MsStr s;
    msstd_time_timestamp_to_string(&t, &s);
    char *const text = owned(&s);
    snprintf(got, size, "%s", text);
    free(text);
}

static bool golden_calendar(const char *line, char *got, size_t size) {
    char op[8], zone[40] = "";
    long long a[2];
    int64_t offset;
    sscanf(line, "%7s %lld %lld %39s", op, &a[0], &a[1], zone);
    if (!offset_of(zone, &offset)) {
        return false;
    }
    const MsTimestamp t = {a[0], a[1]};
    const MsStr z = view(zone[0] == 0 ? "UTC" : zone);
    MsCalendar c;
    msstd_time_timestamp_calendar(&t, offset, &z, &c);
    char *const name = owned(&c.zone);
    snprintf(got, size, "%lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %s", (long long)c.year,
             (long long)c.month, (long long)c.day, (long long)c.hour, (long long)c.minute, (long long)c.second,
             (long long)c.nanosecond, (long long)c.weekday, (long long)c.day_of_year, (long long)c.offset_seconds,
             name);
    free(name);
    return true;
}

static bool golden_local(const char *line, char *got, size_t size) {
    char op[8], zone[40] = "";
    long long a[7] = {0};
    int64_t offset;
    sscanf(line, "%7s %lld %lld %lld %lld %lld %lld %lld %39s", op, &a[0], &a[1], &a[2], &a[3], &a[4], &a[5], &a[6],
           zone);
    if (!offset_of(zone, &offset)) {
        return false;
    }
    int64_t local;
    MsTimestamp t;
    if (msstd_time_local_from_calendar(a[0], a[1], a[2], a[3], a[4], a[5], a[6], &local) == 0 &&
        msstd_time_from_local(local, a[6], offset, &t) == 0) {
        snprintf(got, size, "%lld", (long long)t.seconds);
    } else {
        snprintf(got, size, "ERR");
    }
    return true;
}

static void run_golden(const char *path) {
    FILE *const file = fopen(path, "r");
    if (file == NULL) {
        printf("cannot open %s\n", path);
        exit(1);
    }
    char line[200];
    size_t checked = 0;
    while (fgets(line, sizeof line, file) != NULL) {
        line[strcspn(line, "\n")] = 0;
        char *const arrow = strstr(line, " => ");
        *arrow = 0;
        char got[200] = "";
        bool ran = true;
        if (strncmp(line, "str ", 4) == 0) {
            golden_string(line, got, sizeof got);
        } else if (strncmp(line, "cal ", 4) == 0) {
            ran = golden_calendar(line, got, sizeof got);
        } else {
            ran = golden_local(line, got, sizeof got);
        }
        if (!ran) {
            continue;
        }
        checked++;
        if (strcmp(got, arrow + 4) != 0) {
            printf("FAIL %s\n  got  %s\n  want %s\n", line, got, arrow + 4);
            failures++;
        }
    }
    fclose(file);
    printf("%zu golden records\n", checked);
}

/* ---- direct checks ---- */

static bool faults(void (*run)(void), const char *message) {
    fault_expected = true;
    fault_text[0] = 0;
    volatile bool faulted = false;
    if (setjmp(fault_jump) == 0) {
        run();
    } else {
        faulted = true;
    }
    fault_expected = false;
    if (faulted && strcmp(fault_text, message) != 0) {
        printf("FAIL fault text\n  got  %s\n  want %s\n", fault_text, message);
        failures++;
    }
    return faulted;
}

static void add_overflow(void) { (void)msstd_time_duration_add(INT64_MAX, 1); }
static void multiply_overflow(void) { (void)msstd_time_duration_multiply(INT64_C(1) << 62, 2); }
static void divide_zero(void) { (void)msstd_time_duration_divide(1, 0); }
static void divide_overflow(void) { (void)msstd_time_duration_divide(INT64_MIN, -1); }
static void abs_min(void) { (void)msstd_time_duration_abs(INT64_MIN); }
static void seconds_range(void) { (void)msstd_time_int_seconds(INT64_MAX); }
static void other_clock(void) {
    const MsInstant a = {1, 0}, b = {2, 0};
    (void)msstd_time_instant_compare(&a, &b);
}

static MsTimestamp parse_ok(const char *text) {
    const MsStr s = view(text);
    MsTimestamp t = {0, 0};
    CHECK(msstd_time_parse_timestamp(&s, &t) == 0);
    return t;
}

static uint8_t parse_status(const char *text) {
    const MsStr s = view(text);
    MsTimestamp t;
    return msstd_time_parse_timestamp(&s, &t);
}

static char *format_text(const char *pattern, int64_t seconds, int64_t nanos, int64_t offset, const char *zone) {
    const MsTimestamp t = {seconds, nanos};
    const MsStr p = view(pattern), z = view(zone);
    MsStr out;
    msstd_time_timestamp_format(&t, &p, offset, &z, &out);
    return owned(&out);
}

/* The system zone answer for a TZ setting, as text (the String is freed here). */
static int system_zone_is(const char *setting, const char *expected) {
    setenv("TZ", setting, 1);
    MsStr zone;
    msstd_time_system_zone(&zone);
    const int same = ms_str_len(&zone) == strlen(expected) && memcmp(ms_str_data(&zone), expected, strlen(expected)) == 0;
    msrt_string_free(&zone);
    unsetenv("TZ");
    return same;
}

static void system_zone_checks(void) {
    CHECK(system_zone_is("Europe/Paris", "tz:Europe/Paris"));
    CHECK(system_zone_is(":/usr/share/zoneinfo/Asia/Tokyo", "tz:Asia/Tokyo"));
    char *const long_name = malloc(6001);
    memset(long_name, 'A', 6000);
    long_name[6000] = 0;
    CHECK(system_zone_is(long_name, "")); /* too long for a zone name: no over-read, an empty answer */
    free(long_name);
#ifndef _WIN32 /* the Windows environment is UTF-16: a byte string that is not UTF-8 cannot be set */
    CHECK(system_zone_is("\xff\xfe", "")); /* not UTF-8 */
#endif
}

static void direct_checks(void) {
    system_zone_checks();
    CHECK(msstd_time_duration_add(2, 3) == 5);
    CHECK(msstd_time_duration_to_milliseconds(2500000) == 2);
    CHECK(msstd_time_duration_to_seconds(1500000000) == 1.5);
    CHECK(msstd_time_int_minutes(2) == 120000000000);
    CHECK(faults(add_overflow,
                 "Duration.add: overflow; found value (nanoseconds) 9223372036854775807 and other (nanoseconds) 1; "
                 "result nanoseconds must be between -9223372036854775808 and 9223372036854775807"));
    CHECK(faults(multiply_overflow,
                 "Duration.multiply: overflow; found value (nanoseconds) 4611686018427387904 and factor 2; result "
                 "nanoseconds must be between -9223372036854775808 and 9223372036854775807"));
    CHECK(faults(divide_zero, "Duration.divide: division by zero; divisor must be nonzero, found 0"));
    CHECK(faults(divide_overflow,
                 "Duration.divide: overflow; found value (nanoseconds) -9223372036854775808 and divisor -1; result "
                 "nanoseconds must be between -9223372036854775808 and 9223372036854775807"));
    CHECK(faults(abs_min,
                 "Duration.abs: value (nanoseconds) must be between -9223372036854775807 and 9223372036854775807, "
                 "found -9223372036854775808"));
    CHECK(faults(seconds_range, "Int.seconds: value must be between -9223372036 and 9223372036, found "
                                "9223372036854775807"));
    CHECK(faults(other_clock, "instants belong to different clock domains"));

    MsInstant a, b;
    msstd_time_clock_now(&a);
    msstd_time_instant_shift(&a, 5, &b);
    CHECK(msstd_time_instant_difference(&b, &a) == 5);
    CHECK(msstd_time_instant_compare(&a, &b) == -1);
    CHECK(msstd_time_instant_equal(&a, &a) == 1);
    MsTimestamp wall;
    msstd_time_wall_clock_now(&wall);
    CHECK(wall.seconds > 1700000000 && wall.nanos >= 0 && wall.nanos < MS_NANOS_PER_SECOND);

    CHECK(parse_ok("1970-01-01T00:00:00Z").seconds == 0);
    const MsTimestamp t = parse_ok("2024-02-29T12:30:45.5+02:00");
    CHECK(t.seconds == 1709202645 && t.nanos == 500000000);
    CHECK(parse_status("2023-02-29T00:00:00Z") == MS_STATUS_INVALID_DATA);
    CHECK(parse_status("2024-01-01T00:00:60Z") == MS_STATUS_INVALID_DATA);
    CHECK(parse_status("2024-01-01T00:00:00.1234567890Z") == MS_STATUS_INVALID_DATA);
    CHECK(parse_status("2024-01-01t00:00:00z") == MS_STATUS_INVALID_DATA);
    CHECK(parse_status("0000-01-01T00:00:00Z") == MS_STATUS_INVALID_DATA);
    CHECK(parse_status("2024-02-29T12:30:45.Z") == MS_STATUS_INVALID_DATA);
    CHECK(parse_status("2024-02-29T12:30:45") == MS_STATUS_INVALID_DATA);
    CHECK(parse_status("2024-02-29T12:30:45.123456789+00:000") == MS_STATUS_INVALID_DATA);
    CHECK(parse_status("0001-01-01T00:00:00+01:00") == MS_STATUS_OUT_OF_RANGE);
    CHECK(parse_status("9999-12-31T23:59:59-01:00") == MS_STATUS_OUT_OF_RANGE);
    CHECK(parse_status("9999-12-31T23:59:59.123456789Z") == MS_STATUS_OK);

    char *text = format_text("YYYY-MM-DD HH:mm:ss.SSS ZZ [zone] SS", 1709202645, 120000000, 19800, "+05:30");
    CHECK(text != NULL && strcmp(text, "2024-02-29 16:00:45.120 +05:30 [+05:30] SS") == 0);
    free(text);
    text = format_text("YYYYZZzone", MS_MAX_SECONDS, 999999999, 86340, "+23:59");
    CHECK(text != NULL && strcmp(text, "10000+23:59+23:59") == 0);
    free(text);
    text = format_text("YYYY-MM-DD HH:mm:ss.SSS ZZ [zone]", MS_MIN_SECONDS, 0, -86340, "-23:59");
    CHECK(text != NULL && strcmp(text, "0000-12-31 00:01:00.000 -23:59 [-23:59]") == 0);
    free(text);
    text = format_text("YYYY SSS", -62198755200 + 86400 * 365, INT64_MIN, 0, "UTC"); /* year 0 */
    CHECK(text != NULL);
    free(text);
    text = format_text("", 0, 0, 0, "UTC");
    CHECK(text != NULL && text[0] == 0);
    free(text);
    char *const long_pattern = malloc(10 * 256 + 1);
    for (size_t i = 0; i < 256; i++) {
        memcpy(long_pattern + 10 * i, "YYYYZZzone", 10);
    }
    long_pattern[2560] = 0;
    text = format_text(long_pattern, MS_MAX_SECONDS, 999999999, 86340, "+23:59");
    CHECK(text != NULL && strlen(text) == 17 * 256);
    free(text);
    free(long_pattern);

    MsStr message;
    msstd_time_error_message(MS_STATUS_OUT_OF_RANGE, &message);
    char *const m = owned(&message);
    CHECK(strcmp(m, "time: value out of range") == 0);
    free(m);
}

int main(int argc, char **argv) {
    run_golden(argc > 1 ? argv[1] : "src/runtime/tests/oracle/time_golden.txt");
    direct_checks();
    printf("%d failures\n", failures);
    return failures != 0;
}
