/* The @std/time natives for timestamps as text and as calendar fields (ms_rt/time.h): RFC 3339 parsing and
 * printing, breaking a timestamp down in a zone, formatting with a pattern and building one from fields. */
#include <string.h>

#include "time_internal.h"

enum {
    PARSE_MIN_LENGTH = 20, /* 2024-02-29T12:30:45Z */
    PARSE_MAX_LENGTH = 35, /* ...45.123456789+05:30 */
    DATE_TIME_LENGTH = 19, /* the part before the fraction and the zone */
    MAX_FRACTION_DIGITS = 9,
    NUMBER_TEXT_MAX = 24, /* a padded int64_t and its sign */
};

/* ---- a growable byte buffer owned by the caller of the function that fills it ---- */

typedef struct TextBuffer {
    uint8_t *ptr; /* from the runtime allocator; NULL until the first append */
    size_t len;
    size_t cap;
} TextBuffer;

static void buffer_reserve(TextBuffer *buffer, size_t extra) {
    size_t needed = 0;
    if (!ms_size_add(buffer->len, extra, &needed)) {
        ms_fault_text("time: output too large", 22);
    }
    if (needed <= buffer->cap && buffer->ptr != NULL) {
        return;
    }
    size_t cap = buffer->cap == 0 ? 64 : buffer->cap;
    while (cap < needed) {
        if (!ms_size_mul(cap, 2, &cap)) {
            ms_fault_text("time: output too large", 22);
        }
    }
    uint8_t *const grown = msrt_alloc(cap);
    if (buffer->len != 0) {
        memcpy(grown, buffer->ptr, buffer->len);
    }
    msrt_free(buffer->ptr);
    buffer->ptr = grown;
    buffer->cap = cap;
}

static void buffer_append(TextBuffer *buffer, const uint8_t *bytes, size_t length) {
    buffer_reserve(buffer, length);
    if (length != 0) {
        memcpy(buffer->ptr + buffer->len, bytes, length);
    }
    buffer->len += length;
}

/* Appends an integer with at least `width` characters, zero padded after the sign, as printf("%0*lld") does. */
static void buffer_append_padded(TextBuffer *buffer, int64_t number, size_t width) {
    uint8_t digits[NUMBER_TEXT_MAX];
    size_t at = sizeof digits;
    uint64_t magnitude = number < 0 ? -(uint64_t)number : (uint64_t)number;
    do {
        digits[--at] = (uint8_t)('0' + magnitude % 10);
        magnitude /= 10;
    } while (magnitude != 0);
    const size_t count = sizeof digits - at;
    const size_t sign = number < 0 ? 1 : 0;
    const size_t padding = width > count + sign ? width - count - sign : 0;
    buffer_reserve(buffer, sign + padding + count);
    if (sign != 0) {
        buffer->ptr[buffer->len++] = '-';
    }
    memset(buffer->ptr + buffer->len, '0', padding);
    buffer->len += padding;
    buffer_append(buffer, digits + at, count);
}

static void buffer_to_string(TextBuffer *buffer, MsStr *out) {
    static const uint8_t empty[1] = {0}; /* an empty buffer has no allocation, but the callee wants a pointer */
    msrt_string_from_bytes(buffer->ptr != NULL ? buffer->ptr : empty, buffer->len, out);
    msrt_free(buffer->ptr);
    *buffer = (TextBuffer){0};
}

/* ---- parse and print ---- */

static bool digits_value(MsBytes text, size_t start, size_t end, int64_t *value) {
    int64_t result = 0;
    for (size_t i = start; i < end; i++) {
        if (text.ptr[i] < '0' || text.ptr[i] > '9') {
            return false;
        }
        result = result * 10 + (text.ptr[i] - '0');
    }
    *value = result;
    return true;
}

typedef struct DateTimeFields {
    int64_t year, month, day, hour, minute, second;
} DateTimeFields;

/* `YYYY-MM-DDTHH:MM:SS` at the start of `text`, with the separators and digits checked. */
static bool parse_date_time(MsBytes text, DateTimeFields *f) {
    return text.ptr[4] == '-' && text.ptr[7] == '-' && text.ptr[10] == 'T' && text.ptr[13] == ':' &&
           text.ptr[16] == ':' && digits_value(text, 0, 4, &f->year) && digits_value(text, 5, 7, &f->month) &&
           digits_value(text, 8, 10, &f->day) && digits_value(text, 11, 13, &f->hour) &&
           digits_value(text, 14, 16, &f->minute) && digits_value(text, 17, 19, &f->second);
}

/* The optional `.fraction` at *at (1 to 9 digits) as nanoseconds; advances *at past it. */
static bool parse_fraction(MsBytes text, size_t *at, int64_t *nanos) {
    *nanos = 0;
    if (text.ptr[*at] != '.') {
        return true;
    }
    const size_t start = *at + 1;
    size_t end = start;
    while (end < text.len && text.ptr[end] >= '0' && text.ptr[end] <= '9') {
        end++;
    }
    const size_t width = end - start;
    if (width < 1 || width > MAX_FRACTION_DIGITS || !digits_value(text, start, end, nanos)) {
        return false;
    }
    for (size_t i = width; i < MAX_FRACTION_DIGITS; i++) {
        *nanos *= 10;
    }
    *at = end;
    return true;
}

/* `Z` or `+hh:mm` from *at to the end, as seconds east of UTC. */
static bool parse_offset(MsBytes text, size_t at, int64_t *offset) {
    if (text.len - at == 1 && text.ptr[at] == 'Z') {
        *offset = 0;
        return true;
    }
    int64_t hours = 0;
    int64_t minutes = 0;
    if (text.len - at != 6 || (text.ptr[at] != '+' && text.ptr[at] != '-') || text.ptr[at + 3] != ':' ||
        !digits_value(text, at + 1, at + 3, &hours) || !digits_value(text, at + 4, at + 6, &minutes) || hours > 23 ||
        minutes > 59) {
        return false;
    }
    const int64_t seconds = hours * 3600 + minutes * 60;
    *offset = text.ptr[at] == '-' ? -seconds : seconds;
    return true;
}

static bool fields_are_valid(const DateTimeFields *f) {
    return f->year >= 1 && f->month >= 1 && f->month <= 12 && f->day >= 1 && f->day <= ms_days_in_month(f->year, f->month) &&
           f->hour <= 23 && f->minute <= 59 && f->second <= 59;
}

/* RFC 3339 with an optional fraction of 1 to 9 digits and a `Z` or `+hh:mm` zone. */
uint8_t msstd_time_parse_timestamp(const MsStr *text, MsTimestamp *out) {
    const MsBytes bytes = ms_bytes_of(ms_str_data(text), ms_str_len(text));
    DateTimeFields f = {0};
    size_t at = DATE_TIME_LENGTH;
    int64_t nanos = 0;
    int64_t offset = 0;
    /* The longest accepted form has a nine-digit fraction and a numeric offset. */
    if (bytes.len < PARSE_MIN_LENGTH || bytes.len > PARSE_MAX_LENGTH || !parse_date_time(bytes, &f) ||
        !parse_fraction(bytes, &at, &nanos) || !parse_offset(bytes, at, &offset) || !fields_are_valid(&f)) {
        return MS_STATUS_INVALID_DATA;
    }
    const int64_t seconds = ms_local_seconds(f.year, f.month, f.day, f.hour, f.minute, f.second) - offset;
    if (seconds < MS_MIN_SECONDS || seconds > MS_MAX_SECONDS) {
        return MS_STATUS_OUT_OF_RANGE;
    }
    *out = (MsTimestamp){.seconds = seconds, .nanos = nanos};
    return MS_STATUS_OK;
}

/* UTC RFC 3339 with the fraction trimmed of trailing zeros. */
void msstd_time_timestamp_to_string(const MsTimestamp *value, MsStr *out) {
    const MsCivil c = ms_civil_of(value->seconds, value->nanos);
    TextBuffer buffer = {0};
    buffer_append_padded(&buffer, c.year, 4);
    buffer_append(&buffer, (const uint8_t *)"-", 1);
    buffer_append_padded(&buffer, c.month, 2);
    buffer_append(&buffer, (const uint8_t *)"-", 1);
    buffer_append_padded(&buffer, c.day, 2);
    buffer_append(&buffer, (const uint8_t *)"T", 1);
    buffer_append_padded(&buffer, c.hour, 2);
    buffer_append(&buffer, (const uint8_t *)":", 1);
    buffer_append_padded(&buffer, c.minute, 2);
    buffer_append(&buffer, (const uint8_t *)":", 1);
    buffer_append_padded(&buffer, c.second, 2);
    if (value->nanos != 0) {
        buffer_append(&buffer, (const uint8_t *)".", 1);
        buffer_append_padded(&buffer, value->nanos, MAX_FRACTION_DIGITS);
        while (buffer.ptr[buffer.len - 1] == '0') {
            buffer.len--;
        }
    }
    buffer_append(&buffer, (const uint8_t *)"Z", 1);
    buffer_to_string(&buffer, out);
}

/* ---- calendar fields and formatting ---- */

/* A timestamp broken down in a zone `offset` seconds east of UTC and called `zone`. */
typedef struct Date {
    MsCivil civil;
    int64_t offset;
    MsBytes zone;
} Date;

static Date date_in_zone(const MsTimestamp *value, int64_t offset, const MsStr *zone) {
    /* Saturating, as the Rust arithmetic was: timestamps and offsets are small, so the clamp is never reached. */
    int64_t local = 0;
    if (__builtin_add_overflow(value->seconds, offset, &local)) {
        local = offset > 0 ? INT64_MAX : INT64_MIN;
    }
    return (Date){.civil = ms_civil_of(local, value->nanos),
                  .offset = offset,
                  .zone = ms_bytes_of(ms_str_data(zone), ms_str_len(zone))};
}

void msstd_time_timestamp_calendar(const MsTimestamp *value, int64_t offset, const MsStr *zone, MsCalendar *out) {
    const Date date = date_in_zone(value, offset, zone);
    const MsCivil *const c = &date.civil;
    *out = (MsCalendar){.year = c->year,
                        .month = c->month,
                        .day = c->day,
                        .hour = c->hour,
                        .minute = c->minute,
                        .second = c->second,
                        .nanosecond = c->nanosecond,
                        .weekday = c->weekday,
                        .day_of_year = c->day_of_year,
                        .offset_seconds = offset};
    msrt_string_from_bytes(date.zone.ptr, date.zone.len, &out->zone);
}

/* The pattern tokens, tried in this order at each position: the first that matches wins. */
typedef enum Token {
    TOKEN_YEAR,
    TOKEN_MONTH,
    TOKEN_DAY,
    TOKEN_HOUR,
    TOKEN_MINUTE,
    TOKEN_SECOND,
    TOKEN_MILLI,
    TOKEN_OFFSET,
    TOKEN_ZONE,
    TOKEN_COUNT, /* no token */
} Token;

static const char *const token_text[TOKEN_COUNT] = {"YYYY", "MM", "DD", "HH", "mm", "ss", "SSS", "ZZ", "zone"};

static bool starts_with(MsBytes bytes, size_t at, const char *token) {
    const size_t length = strlen(token);
    return bytes.len - at >= length && memcmp(bytes.ptr + at, token, length) == 0;
}

static void append_offset(TextBuffer *buffer, int64_t offset_seconds) {
    const uint64_t magnitude = offset_seconds < 0 ? -(uint64_t)offset_seconds : (uint64_t)offset_seconds;
    buffer_append(buffer, (const uint8_t *)(offset_seconds < 0 ? "-" : "+"), 1);
    buffer_append_padded(buffer, (int64_t)(magnitude / 3600), 2);
    buffer_append(buffer, (const uint8_t *)":", 1);
    buffer_append_padded(buffer, (int64_t)(magnitude % 3600 / 60), 2);
}

static void append_token(TextBuffer *buffer, Token token, const Date *date) {
    const MsCivil *const c = &date->civil;
    switch (token) {
    case TOKEN_YEAR:
        buffer_append_padded(buffer, c->year, 4);
        break;
    case TOKEN_MONTH:
        buffer_append_padded(buffer, c->month, 2);
        break;
    case TOKEN_DAY:
        buffer_append_padded(buffer, c->day, 2);
        break;
    case TOKEN_HOUR:
        buffer_append_padded(buffer, c->hour, 2);
        break;
    case TOKEN_MINUTE:
        buffer_append_padded(buffer, c->minute, 2);
        break;
    case TOKEN_SECOND:
        buffer_append_padded(buffer, c->second, 2);
        break;
    case TOKEN_MILLI:
        buffer_append_padded(buffer, c->nanosecond / 1000000, 3);
        break;
    case TOKEN_OFFSET:
        append_offset(buffer, date->offset);
        break;
    case TOKEN_ZONE:
    case TOKEN_COUNT:
        buffer_append(buffer, date->zone.ptr, date->zone.len);
        break;
    }
}

/* The token that starts at `at`, or TOKEN_COUNT. */
static Token token_at(MsBytes pattern, size_t at) {
    for (int token = 0; token < TOKEN_COUNT; token++) {
        if (starts_with(pattern, at, token_text[token])) {
            return (Token)token;
        }
    }
    return TOKEN_COUNT;
}

void msstd_time_timestamp_format(const MsTimestamp *value, const MsStr *pattern, int64_t offset, const MsStr *zone, MsStr *out) {
    const Date date = date_in_zone(value, offset, zone);
    const MsBytes bytes = ms_bytes_of(ms_str_data(pattern), ms_str_len(pattern));
    TextBuffer buffer = {0};
    size_t at = 0;
    while (at < bytes.len) {
        const Token token = token_at(bytes, at);
        if (token == TOKEN_COUNT) {
            buffer_append(&buffer, bytes.ptr + at, 1);
            at++;
        } else {
            append_token(&buffer, token, &date);
            at += strlen(token_text[token]);
        }
    }
    buffer_to_string(&buffer, out);
}

/* Validates calendar fields strictly and returns their local seconds (the fields read as UTC). */
uint8_t msstd_time_local_from_calendar(int64_t year, int64_t month, int64_t day, int64_t hour, int64_t minute, int64_t second, int64_t nanosecond, int64_t *out) {
    if (year < 1 || year > 9999 || month < 1 || month > 12 || day < 1 || hour < 0 || hour > 23 || minute < 0 ||
        minute > 59 || second < 0 || second > 59 || nanosecond < 0 || nanosecond >= MS_NANOS_PER_SECOND ||
        day > ms_days_in_month(year, month)) {
        return MS_STATUS_OUT_OF_RANGE;
    }
    *out = ms_local_seconds(year, month, day, hour, minute, second);
    return MS_STATUS_OK;
}

/* The timestamp of local seconds in a zone `offset` seconds east of UTC; outside years 1 to 9999 is out of range. */
uint8_t msstd_time_from_local(int64_t local, int64_t nanosecond, int64_t offset, MsTimestamp *out) {
    int64_t unix_seconds = 0;
    if (__builtin_sub_overflow(local, offset, &unix_seconds) || unix_seconds < MS_MIN_SECONDS ||
        unix_seconds > MS_MAX_SECONDS) {
        return MS_STATUS_OUT_OF_RANGE;
    }
    *out = (MsTimestamp){.seconds = unix_seconds, .nanos = nanosecond};
    return MS_STATUS_OK;
}
