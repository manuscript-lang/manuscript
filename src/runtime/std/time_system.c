/* The host's local-zone setting for the @std/time natives: how it names its zone, and the system zone file.
 * src/stdlib/internal/zone.ms turns the answer into rules. */
#ifndef __APPLE__ /* Apple hides some of its names once _POSIX_C_SOURCE is set */
#define _POSIX_C_SOURCE 200809L // NOLINT(cert-dcl37-c,cert-dcl51-cpp): getenv, readlink and fileno under -std=c11
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <uv.h>

#include "ms_rt/time.h"
#include "ms_rt/utf8.h"

enum {
    ZONE_NAME_MAX = 4096, /* longer TZ values and link targets are not zone names */
    ZONE_FILE_CHUNK = 4096,
};

static const char zoneinfo_marker[] = "zoneinfo/";

/* The text after the last "zoneinfo/" of `text`, or all of it when there is none. */
static const char *after_zoneinfo(const char *text, bool *found) {
    const char *last = NULL;
    for (const char *at = strstr(text, zoneinfo_marker); at != NULL; at = strstr(at + 1, zoneinfo_marker)) {
        last = at;
    }
    *found = last != NULL;
    return last != NULL ? last + sizeof zoneinfo_marker - 1 : text;
}

/* `prefix` and `name` as a String; a name that is too long or not UTF-8 is not a zone name, so the answer is empty. */
static void write_string(MsStr *out, const char *prefix, const char *name) {
    char text[ZONE_NAME_MAX + 16];
    const size_t name_length = strlen(name);
    if (name_length > ZONE_NAME_MAX || !ms_utf8_is_valid((const uint8_t *)name, name_length)) {
        msrt_string_from_bytes((const uint8_t *)text, 0, out);
        return;
    }
    const int length = snprintf(text, sizeof text, "%s%s", prefix, name); /* both fit: checked above */
    msrt_string_from_bytes((const uint8_t *)text, length > 0 ? (size_t)length : 0, out);
}

/* The zone a TZ setting names, read live (libuv sees what the process sets on every platform); false when TZ is unset. */
static bool zone_from_environment(MsStr *out) {
    char tz[ZONE_NAME_MAX + 1];
    size_t size = sizeof tz;
    const int code = uv_os_getenv("TZ", tz, &size);
    if (code == UV_ENOENT) {
        return false;
    }
    if (code != 0) { /* longer than any zone name */
        write_string(out, "", "");
        return true;
    }
    bool found = false;
    const char *name = after_zoneinfo(tz[0] == ':' ? tz + 1 : tz, &found);
    write_string(out, "tz:", name[0] == 0 ? "UTC" : name);
    return true;
}

#ifdef _WIN32
#include <windows.h>

void msstd_time_system_zone(MsStr *out) {
    if (zone_from_environment(out)) {
        return;
    }
    DYNAMIC_TIME_ZONE_INFORMATION info;
    char key[ZONE_NAME_MAX];
    if (GetDynamicTimeZoneInformation(&info) == TIME_ZONE_ID_INVALID ||
        WideCharToMultiByte(CP_UTF8, 0, info.TimeZoneKeyName, -1, key, (int)sizeof key, NULL, NULL) == 0) {
        write_string(out, "", "");
        return;
    }
    write_string(out, "windows:", key);
}

uint8_t msstd_time_system_zone_file(MsVec *out) {
    *out = (MsVec){0};
    return MS_STATUS_OK;
}
#else
#include <unistd.h>

void msstd_time_system_zone(MsStr *out) {
    if (zone_from_environment(out)) {
        return;
    }
    char target[ZONE_NAME_MAX];
    const ssize_t length = readlink("/etc/localtime", target, sizeof target - 1);
    if (length > 0) {
        target[length] = 0;
        bool found = false;
        const char *name = after_zoneinfo(target, &found);
        if (found) {
            write_string(out, "link:", name);
            return;
        }
    }
    write_string(out, "", "");
}

/* The whole of /etc/localtime in an allocation of exactly its length, or an empty Bytes when there is none. */
uint8_t msstd_time_system_zone_file(MsVec *out) {
    *out = (MsVec){0};
    FILE *const file = fopen("/etc/localtime", "rb"); // NOLINT(android-cloexec-fopen): mode "e" is glibc-only; the descriptor lives for this call
    if (file == NULL) {
        return MS_STATUS_OK;
    }
    uint8_t *data = NULL;
    size_t length = 0;
    size_t capacity = 0;
    for (;;) {
        if (capacity - length < ZONE_FILE_CHUNK) {
            const size_t grown = capacity == 0 ? (size_t)ZONE_FILE_CHUNK * 2 : capacity * 2;
            uint8_t *const bigger = msrt_alloc(grown);
            if (length != 0) {
                memcpy(bigger, data, length);
            }
            msrt_free(data);
            data = bigger;
            capacity = grown;
        }
        const size_t got = fread(data + length, 1, capacity - length, file);
        length += got;
        if (got == 0) {
            break;
        }
    }
    (void)fclose(file);
    if (length == 0) {
        msrt_free(data);
        return MS_STATUS_OK;
    }
    uint8_t *const exact = msrt_alloc(length);
    memcpy(exact, data, length);
    msrt_free(data);
    *out = (MsVec){.ptr = exact, .len = length, .cap = length};
    return MS_STATUS_OK;
}
#endif
