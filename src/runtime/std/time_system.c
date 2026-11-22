/* The host's local-zone setting for the @std/time natives: how it names its zone, and the system zone file.
 * stdlib/internal/zone.ms turns the answer into rules. */
#ifndef __APPLE__               /* Apple hides some of its names once _POSIX_C_SOURCE is set */
#define _POSIX_C_SOURCE 200809L // NOLINT(cert-dcl37-c,cert-dcl51-cpp): readlink under -std=c17
#endif
#include "base/env.h"
#include "base/file.h"
#include "base/strbuild.h"
#include "base/utf8.h"
#include "runtime/std/time.h"

enum {
  ZONE_NAME_MAX = 4096, /* longer TZ values and link targets are not zone names */
};

/* The text after the last "zoneinfo/" of `text`, or all of it when there is none. */
static MsSpan after_zoneinfo(MsSpan text, bool *found) {
  const MsSpan marker = ms_span_of_text("zoneinfo/");
  size_t last = 0;
  size_t from = 0;
  *found = false;
  size_t at = 0;
  while (from < text.len && ms_span_find(ms_span_of(text.ptr + from, text.len - from), marker, &at)) {
    last = from + at;
    *found = true;
    from = last + 1;
  }
  return *found ? ms_span_of(text.ptr + last + marker.len, text.len - last - marker.len) : text;
}

/* `prefix` and `name` as a String; a name that is too long or not UTF-8 is not a zone name, so the answer is
 * empty. */
static void write_string(MsString *out, const char *prefix, MsSpan name) {
  if (name.len > ZONE_NAME_MAX || !ms_utf8_is_valid(name.ptr, name.len)) {
    *out = ms_string_empty();
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, prefix);
  ms_strbuild_append(&text, name);
  *out = ms_strbuild_finish(&text);
  ms_strbuild_free(&text);
}

/* The zone a TZ setting names, read live; false when TZ is unset. */
static bool zone_from_environment(MsString *out) {
  MsString tz = ms_string_empty();
  if (!ms_env_get("TZ", &tz)) {
    return false;
  }
  MsSpan value = ms_string_span(&tz);
  if (value.len > 0 && value.ptr[0] == ':') {
    value = ms_span_of(value.ptr + 1, value.len - 1);
  }
  if (value.len > ZONE_NAME_MAX) { /* longer than any zone name */
    write_string(out, "", ms_span_of(NULL, 0));
  } else {
    bool found = false;
    const MsSpan name = after_zoneinfo(value, &found);
    write_string(out, "tz:", name.len == 0 ? ms_span_of_text("UTC") : name);
  }
  ms_string_release(&tz);
  return true;
}

#ifdef _WIN32
#include <windows.h>

void msstd_time_system_zone(MsString *out) {
  if (zone_from_environment(out)) {
    return;
  }
  DYNAMIC_TIME_ZONE_INFORMATION info;
  char key[ZONE_NAME_MAX];
  if (GetDynamicTimeZoneInformation(&info) == TIME_ZONE_ID_INVALID ||
      WideCharToMultiByte(CP_UTF8, 0, info.TimeZoneKeyName, -1, key, (int)sizeof key, NULL, NULL) == 0) {
    write_string(out, "", ms_span_of(NULL, 0));
    return;
  }
  write_string(out, "windows:", ms_span_of_text(key));
}

uint8_t msstd_time_system_zone_file(MsList *out) {
  *out = (MsList){0};
  return MS_STATUS_OK;
}
#else
#include <unistd.h>

void msstd_time_system_zone(MsString *out) {
  if (zone_from_environment(out)) {
    return;
  }
  char target[ZONE_NAME_MAX];
  const ssize_t length = readlink("/etc/localtime", target, sizeof target - 1);
  if (length > 0) {
    bool found = false;
    const MsSpan name = after_zoneinfo(ms_span_of((const uint8_t *)target, (size_t)length), &found);
    if (found) {
      write_string(out, "link:", name);
      return;
    }
  }
  write_string(out, "", ms_span_of(NULL, 0));
}

/* The whole of /etc/localtime, or an empty Bytes when there is none. */
uint8_t msstd_time_system_zone_file(MsList *out) {
  *out = (MsList){0};
  MsBytes data = {0};
  if (ms_file_read(ms_span_of_text("/etc/localtime"), &data)) {
    *out = data;
  }
  return MS_STATUS_OK;
}
#endif
