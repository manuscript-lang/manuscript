/* The @std/time natives. The calendar records come from Go's time package (oracle/time_golden.txt); the zone
 * database is faked from those same records, so this checks the C arithmetic and text, not the tz data (the
 * conformance suite runs the real zones). Direct checks cover faults, parsing limits and formatting. */
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../std/time_internal.h"
#include "fake_list.h"

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

void *msrt_alloc(size_t size) {
    void *const memory = malloc(size);
    if (memory == NULL) {
        abort();
    }
    return memory;
}
void msrt_free(void *pointer) { free(pointer); }
void msrt_fault(const void *message, size_t length) {
    if (!fault_expected) {
        printf("UNEXPECTED FAULT %.*s\n", (int)length, (const char *)message);
        exit(1);
    }
    snprintf(fault_text, sizeof fault_text, "%.*s", (int)length, (const char *)message);
    longjmp(fault_jump, 1);
}
void msrt_fault_kind(uint8_t kind, const void *message, size_t length) { msrt_fault(message, length); (void)kind; }
void msrt_string_from_bytes(const uint8_t *bytes, size_t length, void *out) {
    ms_str *const s = out;
    uint8_t *const copy = malloc(length + 1);
    memcpy(copy, bytes, length);
    s->ptr_word = copy;
    s->tagged = length;
}

/* ---- the fake zone database, filled from the golden records ---- */

typedef struct ZoneRow {
    char key[96]; /* "zone seconds" or "zone y m d h mi s ns" */
    int64_t offset;
    char name[16];
} ZoneRow;
static ZoneRow *rows;
static size_t row_count;
static char known_zones[64][40];
static size_t known_count;

static void remember_zone(const char *zone) {
    for (size_t i = 0; i < known_count; i++) {
        if (strcmp(known_zones[i], zone) == 0) {
            return;
        }
    }
    snprintf(known_zones[known_count++], sizeof known_zones[0], "%s", zone);
}

static const ZoneRow *find_row(const char *key) {
    for (size_t i = 0; i < row_count; i++) {
        if (strcmp(rows[i].key, key) == 0) {
            return &rows[i];
        }
    }
    return NULL;
}

static void zone_text(const ms_str *zone, char *out) {
    snprintf(out, 40, "%.*s", (int)ms_str_len(zone), (const char *)ms_str_data(zone));
}

uint8_t msstd_time_zone_info(const ms_str *zone, int64_t unix_seconds, MsZoneInfo *out) {
    char name[40], key[96];
    zone_text(zone, name);
    snprintf(key, sizeof key, "%s %lld", name, (long long)unix_seconds);
    const ZoneRow *row = find_row(key);
    if (row == NULL) {
        for (size_t i = 0; i < known_count; i++) {
            if (strcmp(known_zones[i], name) == 0) { /* known zone, instant not in the table */
                out->offset = 0;
                msrt_string_from_bytes((const uint8_t *)"?", 1, &out->name);
                return 0;
            }
        }
        return 1;
    }
    out->offset = row->offset;
    msrt_string_from_bytes((const uint8_t *)row->name, strlen(row->name), &out->name);
    return 0;
}

uint8_t msstd_time_zone_local_offset(const ms_str *zone, int64_t year, int64_t month, int64_t day, int64_t hour,
                                     int64_t minute, int64_t second, int64_t nanosecond, int64_t *offset) {
    char name[40], key[96];
    zone_text(zone, name);
    snprintf(key, sizeof key, "%s %lld %lld %lld %lld %lld %lld %lld", name, (long long)year, (long long)month,
             (long long)day, (long long)hour, (long long)minute, (long long)second, (long long)nanosecond);
    const ZoneRow *const row = find_row(key);
    if (row == NULL) {
        return 1;
    }
    *offset = row->offset;
    return 0;
}

static ms_str view(const char *text) {
    return (ms_str){.ptr_word = (uint8_t *)(uintptr_t)text, .tagged = strlen(text) | ((uint64_t)2 << 62)};
}

static char *owned(ms_str *s) {
    char *const copy = malloc(ms_str_len(s) + 1);
    memcpy(copy, ms_str_data(s), ms_str_len(s));
    copy[ms_str_len(s)] = 0;
    free(s->ptr_word);
    return copy;
}

static void add_row(const char *key, int64_t offset, const char *name) {
    rows = realloc(rows, (row_count + 1) * sizeof *rows);
    ZoneRow *const row = &rows[row_count++];
    snprintf(row->key, sizeof row->key, "%s", key);
    row->offset = offset;
    snprintf(row->name, sizeof row->name, "%s", name);
}

/* First pass: the zone rows each record implies. `cal` gives offset and abbreviation at an instant; `from` gives
 * the offset of local fields as local - unix. */
static void learn(char *line) {
    char *const arrow = strstr(line, " => ");
    *arrow = 0;
    const char *const answer = arrow + 4;
    char op[8], zone[40] = "";
    long long a[9] = {0};
    char key[96];
    if (strncmp(line, "cal ", 4) == 0) {
        if (sscanf(line, "%7s %lld %lld %39s", op, &a[0], &a[1], zone) < 3) {
            return;
        }
        long long f[9];
        char abbreviation[16];
        sscanf(answer, "%lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %15s", &f[0], &f[1], &f[2], &f[3], &f[4],
               &f[5], &f[6], &f[7], &f[8], &a[2], abbreviation);
        snprintf(key, sizeof key, "%s %lld", zone, a[0]);
        remember_zone(zone);
        add_row(key, a[2], abbreviation);
    } else if (strncmp(line, "from ", 5) == 0 && strcmp(answer, "ERR") != 0) {
        if (sscanf(line, "%7s %lld %lld %lld %lld %lld %lld %lld %39s", op, &a[0], &a[1], &a[2], &a[3], &a[4],
                   &a[5], &a[6], zone) < 8) {
            return;
        }
        remember_zone(zone);
        /* local seconds from the fields, independent of the code under test */
        long long y = a[1] <= 2 ? a[0] - 1 : a[0];
        long long era = (y >= 0 ? y : y - 399) / 400, yoe = y - era * 400;
        long long mp = (a[1] + 9) % 12, doy = (153 * mp + 2) / 5 + a[2] - 1;
        long long days = era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468;
        const long long local = days * 86400 + a[3] * 3600 + a[4] * 60 + a[5];
        snprintf(key, sizeof key, "%s %lld %lld %lld %lld %lld %lld %lld", zone, a[0], a[1], a[2], a[3], a[4], a[5],
                 a[6]);
        add_row(key, local - strtoll(answer, NULL, 10), "");
    } else if (strncmp(line, "from ", 5) == 0) {
        if (sscanf(line, "%7s %lld %lld %lld %lld %lld %lld %lld %39s", op, &a[0], &a[1], &a[2], &a[3], &a[4],
                   &a[5], &a[6], zone) >= 8) {
            remember_zone(zone);
        }
    }
}

static void run_golden(const char *path) {
    FILE *const file = fopen(path, "r");
    if (file == NULL) {
        printf("cannot open %s\n", path);
        exit(1);
    }
    static char lines[1000][160];
    size_t count = 0;
    while (count < 1000 && fgets(lines[count], sizeof lines[0], file) != NULL) {
        lines[count][strcspn(lines[count], "\n")] = 0;
        char copy[160];
        memcpy(copy, lines[count], sizeof copy);
        learn(copy);
        count++;
    }
    fclose(file);
    for (size_t i = 0; i < count; i++) {
        char *const arrow = strstr(lines[i], " => ");
        *arrow = 0;
        const char *const want = arrow + 4;
        char got[200] = "";
        char op[8], zone[40] = "";
        long long a[9] = {0};
        if (strncmp(lines[i], "str ", 4) == 0) {
            sscanf(lines[i], "%7s %lld %lld", op, &a[0], &a[1]);
            const MsTimestamp t = {a[0], a[1]};
            ms_str s;
            msstd_time_timestamp_to_string(&t, &s);
            char *const text = owned(&s);
            snprintf(got, sizeof got, "%s", text);
            free(text);
        } else if (strncmp(lines[i], "cal ", 4) == 0) {
            sscanf(lines[i], "%7s %lld %lld %39s", op, &a[0], &a[1], zone);
            const MsTimestamp t = {a[0], a[1]};
            const ms_str z = view(zone);
            MsCalendar c;
            CHECK(msstd_time_timestamp_calendar(&t, &z, &c) == 0);
            char *const name = owned(&c.zone);
            snprintf(got, sizeof got, "%lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %s", (long long)c.year,
                     (long long)c.month, (long long)c.day, (long long)c.hour, (long long)c.minute,
                     (long long)c.second, (long long)c.nanosecond, (long long)c.weekday, (long long)c.day_of_year,
                     (long long)c.offset_seconds, name);
            free(name);
        } else {
            sscanf(lines[i], "%7s %lld %lld %lld %lld %lld %lld %lld %39s", op, &a[0], &a[1], &a[2], &a[3], &a[4],
                   &a[5], &a[6], zone);
            const ms_str z = view(zone);
            MsTimestamp t;
            const uint8_t status = msstd_time_from_calendar(a[0], a[1], a[2], a[3], a[4], a[5], a[6], &z, &t);
            if (status == 0) {
                snprintf(got, sizeof got, "%lld", (long long)t.seconds);
            } else {
                snprintf(got, sizeof got, "ERR");
            }
        }
        if (strcmp(got, want) != 0) {
            printf("FAIL %s\n  got  %s\n  want %s\n", lines[i], got, want);
            failures++;
        }
    }
    printf("%zu golden records\n", count);
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
    const ms_str s = view(text);
    MsTimestamp t = {0, 0};
    CHECK(msstd_time_parse_timestamp(&s, &t) == 0);
    return t;
}

static uint8_t parse_status(const char *text) {
    const ms_str s = view(text);
    MsTimestamp t;
    return msstd_time_parse_timestamp(&s, &t);
}

static char *format_text(const char *pattern, int64_t seconds, int64_t nanos, const char *zone) {
    const MsTimestamp t = {seconds, nanos};
    const ms_str p = view(pattern), z = view(zone);
    ms_str out;
    if (msstd_time_timestamp_format(&t, &p, &z, &out) != 0) {
        return NULL;
    }
    return owned(&out);
}

static void direct_checks(void) {
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

    char *text = format_text("YYYY-MM-DD HH:mm:ss.SSS ZZ [zone] SS", 1709202645, 120000000, "+05:30");
    CHECK(text != NULL && strcmp(text, "2024-02-29 16:00:45.120 +05:30 [+05:30] SS") == 0);
    free(text);
    text = format_text("YYYYZZzone", MS_MAX_SECONDS, 999999999, "+23:59");
    CHECK(text != NULL && strcmp(text, "10000+23:59+23:59") == 0);
    free(text);
    text = format_text("YYYY-MM-DD HH:mm:ss.SSS ZZ [zone]", MS_MIN_SECONDS, 0, "-23:59");
    CHECK(text != NULL && strcmp(text, "0000-12-31 00:01:00.000 -23:59 [-23:59]") == 0);
    free(text);
    text = format_text("YYYY SSS", -62198755200 + 86400 * 365, INT64_MIN, "UTC"); /* year 0 */
    CHECK(text != NULL);
    free(text);
    CHECK(format_text("literal", 0, 0, "Nowhere/City") == NULL);
    CHECK(format_text("", 0, 0, "utc") == NULL);
    char *const long_pattern = malloc(10 * 256 + 1);
    for (size_t i = 0; i < 256; i++) {
        memcpy(long_pattern + 10 * i, "YYYYZZzone", 10);
    }
    long_pattern[2560] = 0;
    text = format_text(long_pattern, MS_MAX_SECONDS, 999999999, "+23:59");
    CHECK(text != NULL && strlen(text) == 17 * 256);
    free(text);
    free(long_pattern);

    ms_str message;
    msstd_time_error_message(MS_STATUS_OUT_OF_RANGE, &message);
    char *const m = owned(&message);
    CHECK(strcmp(m, "time: value out of range") == 0);
    free(m);
}

int main(int argc, char **argv) {
    run_golden(argc > 1 ? argv[1] : "runtime/tests/oracle/time_golden.txt");
    direct_checks();
    printf("%d failures\n", failures);
    return failures != 0;
}
