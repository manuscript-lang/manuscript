/* Zones for the @std/time natives. UTC and `+hh:mm` offsets are resolved here; `Local` and IANA names go to the
 * zone database (crates/ms-std-time) until it is read in C. */
#include "time_internal.h"

enum { FIXED_OFFSET_LENGTH = 6 }; /* +hh:mm */

static bool bytes_are(MsBytes bytes, const char *text) {
    size_t length = 0;
    while (text[length] != 0) {
        length++;
    }
    return bytes.len == length && (length == 0 || __builtin_memcmp(bytes.ptr, text, length) == 0);
}

static bool two_digits(const uint8_t *p, int *value) {
    if (p[0] < '0' || p[0] > '9' || p[1] < '0' || p[1] > '9') {
        return false;
    }
    *value = (p[0] - '0') * 10 + (p[1] - '0');
    return true;
}

/* `^[+-](?:[01][0-9]|2[0-3]):[0-5][0-9]$` as seconds east of UTC. */
static bool fixed_offset(MsBytes zone, int64_t *seconds) {
    int hours = 0;
    int minutes = 0;
    if (zone.len != FIXED_OFFSET_LENGTH || (zone.ptr[0] != '+' && zone.ptr[0] != '-') || zone.ptr[3] != ':' ||
        !two_digits(zone.ptr + 1, &hours) || !two_digits(zone.ptr + 4, &minutes) || hours > 23 || minutes > 59) {
        return false;
    }
    const int64_t magnitude = hours * 3600 + minutes * 60;
    *seconds = zone.ptr[0] == '-' ? -magnitude : magnitude;
    return true;
}

static MsZoneInfo info_of(int64_t offset, MsBytes name) {
    MsZoneInfo info = {.offset = offset};
    msrt_string_from_bytes(name.ptr, name.len, &info.name);
    return info;
}

bool ms_zone_info_at(const ms_str *zone, int64_t unix_seconds, MsZoneInfo *out) {
    const MsBytes name = ms_bytes(ms_str_data(zone), ms_str_len(zone));
    int64_t offset = 0;
    if (name.len == 0 || bytes_are(name, "UTC")) {
        *out = info_of(0, ms_bytes((const uint8_t *)"UTC", 3));
        return true;
    }
    if (fixed_offset(name, &offset)) {
        *out = info_of(offset, name);
        return true;
    }
    return msstd_time_zone_info(zone, unix_seconds, out) == MS_STATUS_OK;
}

bool ms_zone_local_offset(const ms_str *zone, const MsCivil *local, int64_t *offset) {
    const MsBytes name = ms_bytes(ms_str_data(zone), ms_str_len(zone));
    if (name.len == 0 || bytes_are(name, "UTC")) {
        *offset = 0;
        return true;
    }
    if (fixed_offset(name, offset)) {
        return true;
    }
    return msstd_time_zone_local_offset(zone, local->year, local->month, local->day, local->hour, local->minute,
                                        local->second, local->nanosecond, offset) == MS_STATUS_OK;
}

bool ms_zone_known(const ms_str *zone) {
    MsZoneInfo info;
    if (!ms_zone_info_at(zone, 0, &info)) {
        return false;
    }
    ms_zone_info_release(&info);
    return true;
}

void ms_zone_info_release(MsZoneInfo *info) {
    if ((info->name.tagged >> 62) == 0 && info->name.ptr_word != NULL) { /* owned (tag 00); the others own nothing */
        msrt_free(info->name.ptr_word);
    }
}
