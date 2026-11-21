/* The @std/io/archive natives: path rules, duplicate and conflict checks, limits, and the choice of format.
 */
#include "base/alloc.h"
#include "base/list.h"
#include "base/map.h"
#include "base/bytes.h"
#include "base/utf8.h"
#include "runtime/std/archive.h"
#include "runtime/std/archive_internal.h"

/* ---- paths ---- */

static bool has_byte(MsSpan s, uint8_t b) {
  for (size_t i = 0; i < s.len; i++) {
    if (s.ptr[i] == b) {
      return true;
    }
  }
  return false;
}

static bool components_valid(MsSpan s) {
  size_t start = 0;
  for (size_t i = 0; i <= s.len; i++) {
    if (i < s.len && s.ptr[i] != '/') {
      continue;
    }
    const MsSpan part = ms_span_of(s.ptr + start, i - start);
    if (part.len == 0 || ms_span_is_text(part, ".") || ms_span_is_text(part, "..")) {
      return false;
    }
    start = i + 1;
  }
  return true;
}

static bool path_valid(MsSpan s, bool directory) {
  if (s.len == 0 || !ms_utf8_is_valid(s.ptr, s.len) || has_byte(s, '\\') || has_byte(s, ':') ||
      has_byte(s, 0) || s.ptr[0] == '/') {
    return false;
  }
  const bool slash = s.ptr[s.len - 1] == '/';
  if (directory) {
    s = slash ? ms_span_of(s.ptr, s.len - 1) : s;
  } else if (slash) {
    return false;
  }
  return components_valid(s);
}

/* The path without the trailing slash of a directory. */
static MsSpan clean(MsSpan name, bool directory) {
  return directory && name.len != 0 && name.ptr[name.len - 1] == '/' ? ms_span_of(name.ptr, name.len - 1)
                                                                     : name;
}

/* ---- names: cleaned path to "is a directory" ---- */

typedef struct Names {
  MsMap map;
} Names;

static bool names_has(const Names *names, MsSpan key) {
  const MsString view = ms_string_view(key);
  return ms_map_has(&names->map, &ms_desc_string, &ms_desc_bool, (const uint8_t *)&view);
}

/* Adds `key`; false when it is already there. */
static bool names_add(Names *names, MsSpan key, bool directory) {
  if (names_has(names, key)) {
    return false;
  }
  MsString owned = ms_string_from_span(key);
  uint8_t value = directory ? 1 : 0;
  ms_map_insert(&names->map, &ms_desc_string, &ms_desc_bool, (uint8_t *)&owned, &value);
  return true;
}

/* 1 for a directory, 0 for a file, -1 for no such name. */
static int names_kind(const Names *names, MsSpan key) {
  const MsString view = ms_string_view(key);
  const uint8_t *value = ms_map_get(&names->map, &ms_desc_string, &ms_desc_bool, (const uint8_t *)&view);
  return value == NULL ? -1 : (*value != 0 ? 1 : 0);
}

static void names_free(Names *names) {
  ms_map_drop(&names->map, &ms_desc_string, &ms_desc_bool);
}

/* A regular file sharing a normalised path with an ancestor directory of another entry. */
static bool names_conflict(const Names *names) {
  const MsMapLayout layout = ms_map_layout(&ms_desc_string, &ms_desc_bool);
  for (size_t n = 0; n < names->map.used; n++) {
    const uint8_t *entry = ms_table_entry(&names->map, &layout, n);
    if (!ms_table_entry_is_live(entry)) {
      continue;
    }
    MsString key;
    __builtin_memcpy(&key, entry + layout.key_offset, sizeof key);
    MsSpan dir = ms_string_span(&key);
    for (size_t i = dir.len; i > 0; i--) {
      if (dir.ptr[i - 1] == '/') {
        dir = ms_span_of(dir.ptr, i - 1);
        if (names_kind(names, dir) == 0) {
          return true;
        }
      }
    }
  }
  return false;
}

/* ---- limits ---- */

/* A budget: unbounded when absent, InvalidInput (false) when negative. */
static bool budget(bool present, int64_t value, size_t *out) {
  *out = SIZE_MAX;
  if (!present) {
    return true;
  }
  if (value < 0) {
    return false;
  }
  *out = (uint64_t)value > SIZE_MAX ? SIZE_MAX : (size_t)value;
  return true;
}

/* ---- pack ---- */

static MsArchiveEntry entry_at(const MsBytes *list, size_t index) {
  MsArchiveEntry entry;
  __builtin_memcpy(&entry, list->ptr + index * sizeof entry, sizeof entry);
  return entry;
}

/* Validates every entry and records its name; the status of the first problem. */
static uint8_t check_entries(const MsBytes *entries, Names *names) {
  for (size_t i = 0; i < entries->len; i++) {
    const MsArchiveEntry e = entry_at(entries, i);
    const MsSpan path = ms_string_span(&e.path);
    if (!path_valid(path, e.directory != 0) || (e.directory != 0 && e.data.len != 0)) {
      return MS_STATUS_INVALID_INPUT;
    }
    if (!names_add(names, clean(path, e.directory != 0), e.directory != 0)) {
      return MS_STATUS_INVALID_DATA;
    }
  }
  return names_conflict(names) ? MS_STATUS_INVALID_DATA : MS_STATUS_OK;
}

/* The archive name of each entry: the cleaned path, with a slash for a directory. */
static MsStrBuild *archive_names(const MsBytes *entries) {
  MsStrBuild *names = ms_alloc((entries->len + 1) * sizeof *names);
  for (size_t i = 0; i < entries->len; i++) {
    const MsArchiveEntry e = entry_at(entries, i);
    names[i] = ms_strbuild_new();
    ms_strbuild_append(&names[i], clean(ms_string_span(&e.path), e.directory != 0));
    if (e.directory != 0) {
      ms_strbuild_append_byte(&names[i], '/');
    }
  }
  return names;
}

static uint8_t pack_zip(const MsBytes *entries, const MsStrBuild *names, MsStrBuild *out) {
  ZipMember *members = ms_alloc((entries->len + 1) * sizeof *members);
  uint8_t status = MS_STATUS_OK;
  for (size_t i = 0; i < entries->len; i++) {
    const MsArchiveEntry e = entry_at(entries, i);
    members[i] =
        (ZipMember){ms_strbuild_span(&names[i]), ms_span_of(e.data.ptr, e.data.len), e.directory != 0};
    if (members[i].name.len > 0xffff) {
      status = MS_STATUS_INVALID_INPUT;
    }
  }
  if (status == MS_STATUS_OK) {
    zip_pack(out, members, entries->len);
  }
  ms_free(members);
  return status;
}

static uint8_t pack_tar(const MsBytes *entries, const MsStrBuild *names, size_t max, MsStrBuild *out) {
  for (size_t i = 0; i < entries->len; i++) {
    const MsArchiveEntry e = entry_at(entries, i);
    if (!tar_write_entry(out, ms_strbuild_span(&names[i]), ms_span_of(e.data.ptr, e.data.len),
                         e.directory != 0) ||
        ms_strbuild_length(out) > max) {
      return MS_STATUS_LIMIT_EXCEEDED;
    }
  }
  tar_finish(out);
  return MS_STATUS_OK;
}

uint8_t msstd_archive_pack(const MsBytes *entries, const MsString *format, uint8_t has_max, int64_t max,
                           MsBytes *out) {
  *out = (MsBytes){0};
  size_t limit = 0;
  if (!budget(has_max != 0, max, &limit)) {
    return MS_STATUS_INVALID_INPUT;
  }
  Names names = {0};
  uint8_t status = check_entries(entries, &names);
  names_free(&names);
  if (status != MS_STATUS_OK) {
    return status;
  }
  const MsSpan kind = ms_string_span(format);
  const bool zip = ms_span_is_text(kind, "zip");
  if (!zip && !ms_span_is_text(kind, "tar")) {
    return MS_STATUS_UNSUPPORTED;
  }
  MsStrBuild *archive = archive_names(entries);
  MsStrBuild bytes = ms_strbuild_new();
  status = zip ? pack_zip(entries, archive, &bytes) : pack_tar(entries, archive, limit, &bytes);
  if (status == MS_STATUS_OK && ms_strbuild_length(&bytes) > limit) {
    status = MS_STATUS_LIMIT_EXCEEDED;
  }
  if (status == MS_STATUS_OK) {
    *out = ms_bytes_from_span(ms_strbuild_span(&bytes));
  }
  for (size_t i = 0; i < entries->len; i++) {
    ms_strbuild_free(&archive[i]);
  }
  ms_free(archive);
  ms_strbuild_free(&bytes);
  return status;
}

/* ---- unpack ---- */

typedef struct Collector {
  MsBytes out;
  Names names;
  size_t count;
  size_t entry_max;
  size_t total;
} Collector;

static void collector_free(Collector *c) {
  for (size_t i = 0; i < c->out.len; i++) {
    MsArchiveEntry e = entry_at(&c->out, i);
    ms_string_release(&e.path);
    MsBytes data = e.data;
    ms_bytes_free(&data);
  }
  ms_list_free(&c->out);
  names_free(&c->names);
}

/* The checks Go makes before it reads a member's body. */
static uint8_t collector_begin(Collector *c, MsSpan name, bool directory, size_t size) {
  if (!path_valid(name, directory) || !names_add(&c->names, clean(name, directory), directory)) {
    return MS_STATUS_INVALID_DATA;
  }
  if (c->out.len >= c->count || size > c->entry_max || size > c->total) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  return MS_STATUS_OK;
}

static uint8_t collector_push(Collector *c, MsSpan name, bool directory, MsSpan body) {
  const size_t room = c->entry_max < c->total ? c->entry_max : c->total;
  if (body.len > room) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  if (directory && body.len != 0) {
    return MS_STATUS_INVALID_DATA;
  }
  c->total -= body.len;
  const MsArchiveEntry entry = {ms_string_from_span(clean(name, directory)), ms_bytes_from_span(body),
                                directory ? (uint8_t)1 : (uint8_t)0};
  ms_list_push(&c->out, sizeof entry, &entry);
  return MS_STATUS_OK;
}

static uint8_t unpack_tar(MsSpan data, Collector *c) {
  TarReader reader = {data, 0, 0};
  for (;;) {
    TarItem item;
    const int next = tar_next(&reader, &item);
    if (next < 0) {
      return MS_STATUS_INVALID_DATA;
    }
    if (next == 0) {
      return MS_STATUS_OK;
    }
    uint8_t status = MS_STATUS_OK;
    const uint8_t flag = item.typeflag;
    const bool directory = flag == TAR_TYPE_DIR;
    if (flag != TAR_TYPE_REG && flag != TAR_TYPE_REG_A && !directory) {
      status = MS_STATUS_UNSUPPORTED;
    } else {
      MsSpan name = ms_strbuild_span(&item.name);
      /* `tar -cf x.tar .` prefixes every member with `./` and adds a bare `./` entry. */
      while (ms_span_starts_with(name, ms_span_of_text("./"))) {
        name = ms_span_of(name.ptr + 2, name.len - 2);
      }
      const size_t size = (uint64_t)item.size > SIZE_MAX ? SIZE_MAX : (size_t)item.size;
      if (!(directory && (name.len == 0 || ms_span_is_text(name, ".")))) {
        status = collector_begin(c, name, directory, size);
        if (status == MS_STATUS_OK && item.truncated) {
          status = MS_STATUS_INVALID_DATA;
        }
        if (status == MS_STATUS_OK) {
          status = collector_push(c, name, directory, ms_span_of(data.ptr + item.start, item.length));
        }
      }
    }
    tar_item_free(&item);
    if (status != MS_STATUS_OK) {
      return status;
    }
  }
}

static uint8_t unpack_zip_file(MsSpan data, Collector *c, const ZipFile *file) {
  bool regular = false;
  bool directory = false;
  zip_kind(file, &regular, &directory);
  if (!ms_utf8_is_valid(file->name.ptr, file->name.len) || (!regular && !directory)) {
    return MS_STATUS_UNSUPPORTED;
  }
  const size_t size = file->size > (uint64_t)SIZE_MAX ? SIZE_MAX : (size_t)file->size;
  if (size > c->entry_max || size > c->total) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  /* Go opens the member (header and algorithm checks) before `add` validates. */
  if (!zip_check_open(file, data)) {
    return MS_STATUS_INVALID_DATA;
  }
  uint8_t status = collector_begin(c, file->name, directory, size);
  if (status != MS_STATUS_OK) {
    return status;
  }
  MsStrBuild body = ms_strbuild_new();
  status = zip_read(file, data, &body) ? collector_push(c, file->name, directory, ms_strbuild_span(&body))
                                       : MS_STATUS_INVALID_DATA;
  ms_strbuild_free(&body);
  return status;
}

static uint8_t unpack_zip(MsSpan data, Collector *c) {
  ZipFile *files = NULL;
  size_t count = 0;
  if (!zip_open(data, &files, &count)) {
    return MS_STATUS_INVALID_DATA;
  }
  uint8_t status = count > c->count ? MS_STATUS_LIMIT_EXCEEDED : MS_STATUS_OK;
  for (size_t i = 0; status == MS_STATUS_OK && i < count; i++) {
    status = unpack_zip_file(data, c, &files[i]);
  }
  ms_free(files);
  return status;
}

uint8_t msstd_archive_unpack(const MsBytes *data, const MsString *format, uint8_t has_limits,
                             uint8_t has_entries, int64_t max_entries, uint8_t has_entry_bytes,
                             int64_t max_entry_bytes, uint8_t has_total, int64_t max_total_bytes,
                             MsBytes *out) {
  *out = (MsBytes){0};
  Collector c = {0};
  const bool limited = has_limits != 0;
  if (!budget(limited && has_entries != 0, max_entries, &c.count) ||
      !budget(limited && has_entry_bytes != 0, max_entry_bytes, &c.entry_max) ||
      !budget(limited && has_total != 0, max_total_bytes, &c.total)) {
    return MS_STATUS_INVALID_INPUT;
  }
  const MsSpan kind = ms_string_span(format);
  const MsSpan bytes = ms_span_of(data->ptr, data->len);
  uint8_t status = MS_STATUS_UNSUPPORTED;
  if (ms_span_is_text(kind, "tar")) {
    status = unpack_tar(bytes, &c);
  } else if (ms_span_is_text(kind, "zip")) {
    status = unpack_zip(bytes, &c);
  }
  if (status == MS_STATUS_OK && names_conflict(&c.names)) {
    status = MS_STATUS_INVALID_DATA;
  }
  if (status == MS_STATUS_OK) {
    *out = c.out;
    c.out = (MsBytes){0};
  }
  collector_free(&c);
  return status;
}
