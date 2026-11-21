/* Zip reading and writing: end-of-central-directory search (with prefix data and zip64), stored and deflated
 * members, data descriptors and CRC verification. Members are deflated and inflated through the compress
 * natives. */
#include <zlib.h>

#include "base/alloc.h"
#include "base/array.h"
#include "base/utf8.h"
#include "runtime/std/archive_internal.h"
#include "runtime/std/compress.h"

enum {
  FILE_HEADER_SIG = 0x04034b50,
  DIR_HEADER_SIG = 0x02014b50,
  DIR_END_SIG = 0x06054b50,
  DIR64_END_SIG = 0x06064b50,
  DIR64_LOC_SIG = 0x07064b50,
  DATA_DESC_SIG = 0x08074b50,
  FILE_HEADER_LEN = 30,
  DIR_HEADER_LEN = 46,
  DIR_END_LEN = 22,
  DIR64_END_LEN = 56,
  DIR64_LOC_LEN = 20,
  CREATOR_FAT = 0,
  CREATOR_UNIX = 3,
  CREATOR_NTFS = 11,
  CREATOR_VFAT = 14,
  CREATOR_MAC = 19,
  DEFLATE_LEVEL = 5,
  STORE_LIMIT = 64
};

static uint16_t u16le(const uint8_t *b, size_t at) {
  return (uint16_t)(b[at] | (b[at + 1] << 8));
}

static uint32_t u32le(const uint8_t *b, size_t at) {
  return (uint32_t)b[at] | ((uint32_t)b[at + 1] << 8) | ((uint32_t)b[at + 2] << 16) |
         ((uint32_t)b[at + 3] << 24);
}

static uint64_t u64le(const uint8_t *b, size_t at) {
  return (uint64_t)u32le(b, at) | ((uint64_t)u32le(b, at + 4) << 32);
}

static uint32_t crc_of(MsSpan data) {
  uint32_t crc = (uint32_t)crc32(0, Z_NULL, 0);
  for (size_t at = 0; at < data.len;) {
    const size_t step = data.len - at > UINT32_MAX ? UINT32_MAX : data.len - at;
    crc = (uint32_t)crc32(crc, data.ptr + at, (uInt)step);
    at += step;
  }
  return crc;
}

/* ---- the end of the central directory ---- */

/* Looks for the end record in the last `window` bytes: its absolute offset, or false to try a wider window.
 */
static bool find_end_in(MsSpan data, size_t window, size_t *at_out) {
  const size_t size = data.len;
  const size_t len = window > size ? size : window;
  const uint8_t *buf = data.ptr + (size - len);
  if (len < DIR_END_LEN) {
    return false;
  }
  for (size_t at = len - DIR_END_LEN + 1; at > 0; at--) {
    const size_t i = at - 1;
    if (buf[i] == 'P' && buf[i + 1] == 'K' && buf[i + 2] == 5 && buf[i + 3] == 6) {
      const size_t comment = u16le(buf, i + DIR_END_LEN - 2);
      if (comment + DIR_END_LEN + i > len) {
        return false; /* Go reports not found for this block rather than scanning on */
      }
      *at_out = size - len + i;
      return true;
    }
  }
  return false;
}

static bool find_end(MsSpan data, size_t *at) {
  if (find_end_in(data, 1024, at)) {
    return true;
  }
  return data.len > 1024 && find_end_in(data, 65 * 1024, at);
}

/* ---- central directory records ---- */

typedef enum DirResult { DIR_OK, DIR_EOF, DIR_SHORT, DIR_FORMAT } DirResult;

/* Applies the zip64 extra field to `file`; false for a malformed one or one missing a required value. */
static bool apply_zip64(MsSpan extra, ZipFile *file, bool need_size, bool need_csize, bool need_offset) {
  while (extra.len >= 4) {
    const uint16_t tag = u16le(extra.ptr, 0);
    const size_t length = u16le(extra.ptr, 2);
    extra = ms_span_of(extra.ptr + 4, extra.len - 4);
    if (extra.len < length) {
      break;
    }
    MsSpan field = ms_span_of(extra.ptr, length);
    extra = ms_span_of(extra.ptr + length, extra.len - length);
    bool *needs[3] = {&need_size, &need_csize, &need_offset};
    for (size_t slot = 0; tag == 0x0001 && slot < 3; slot++) {
      if (!*needs[slot]) {
        continue;
      }
      *needs[slot] = false;
      if (field.len < 8) {
        return false;
      }
      const uint64_t v = u64le(field.ptr, 0);
      field = ms_span_of(field.ptr + 8, field.len - 8);
      if (slot == 0) {
        file->size = v;
      } else if (slot == 1) {
        file->compressed_size = v;
      } else {
        file->offset = (int64_t)v;
      }
    }
  }
  return !need_csize && !need_offset;
}

static DirResult read_dir_header(MsSpan *rd, ZipFile *file) {
  if (rd->len == 0) {
    return DIR_EOF;
  }
  if (rd->len < DIR_HEADER_LEN) {
    *rd = ms_span_of(NULL, 0);
    return DIR_SHORT;
  }
  const uint8_t *b = rd->ptr;
  if (u32le(b, 0) != DIR_HEADER_SIG) {
    *rd = ms_span_of(rd->ptr + 4, rd->len - 4);
    return DIR_FORMAT;
  }
  const size_t name_length = u16le(b, 28);
  const size_t extra_length = u16le(b, 30);
  const size_t total = name_length + extra_length + u16le(b, 32);
  *file = (ZipFile){.creator = u16le(b, 4),
                    .flags = u16le(b, 8),
                    .method = u16le(b, 10),
                    .crc32 = u32le(b, 16),
                    .compressed_size = u32le(b, 20),
                    .size = u32le(b, 24),
                    .attrs = u32le(b, 38),
                    .offset = u32le(b, 42)};
  const MsSpan rest = ms_span_of(b + DIR_HEADER_LEN, rd->len - DIR_HEADER_LEN);
  if (rest.len < total) {
    const bool eof = rest.len == 0 && total > 0;
    *rd = ms_span_of(NULL, 0);
    return eof ? DIR_EOF : DIR_SHORT;
  }
  file->name = ms_span_of(rest.ptr, name_length);
  const MsSpan extra = ms_span_of(rest.ptr + name_length, extra_length);
  *rd = ms_span_of(rest.ptr + total, rest.len - total);
  const bool ok = apply_zip64(extra, file, u32le(b, 24) == UINT32_MAX, u32le(b, 20) == UINT32_MAX,
                              u32le(b, 42) == UINT32_MAX);
  return ok ? DIR_OK : DIR_FORMAT;
}

typedef struct EndRecord {
  uint64_t records;
  uint64_t size;
  uint64_t offset;
} EndRecord;

/* Replaces `end` with the zip64 end record when the plain one holds placeholders; false when malformed. */
static bool read_zip64_end(MsSpan data, int64_t *end_offset, EndRecord *end) {
  if (end->records != 0xffff && end->size != 0xffffffff && end->offset != 0xffffffff) {
    return true;
  }
  const int64_t loc = *end_offset - DIR64_LOC_LEN;
  if (loc < 0) {
    return true;
  }
  const uint8_t *l = data.ptr + loc;
  if ((size_t)loc + DIR64_LOC_LEN > data.len) {
    return false;
  }
  if (u32le(l, 0) != DIR64_LOC_SIG || u32le(l, 4) != 0 || u32le(l, 16) != 1) {
    return true;
  }
  const int64_t p = (int64_t)u64le(l, 8);
  *end_offset = p;
  if (p < 0 || (uint64_t)p > data.len || data.len - (size_t)p < DIR64_END_LEN) {
    return false;
  }
  const uint8_t *e = data.ptr + p;
  if (u32le(e, 0) != DIR64_END_SIG) {
    return false;
  }
  end->records = u64le(e, 32);
  end->size = u64le(e, 40);
  end->offset = u64le(e, 48);
  return true;
}

/* The offset the central directory's stored offsets are relative to (prefix data shifts them). */
static bool directory_base(MsSpan data, int64_t end_offset, const EndRecord *end, int64_t *base_out) {
  const uint64_t max = (uint64_t)INT64_MAX;
  if (end->size > max || end->offset > max) {
    return false;
  }
  int64_t base = (int64_t)((uint64_t)end_offset - end->size - end->offset);
  const int64_t at = (int64_t)((uint64_t)base + end->offset);
  if (at < 0 || at >= (int64_t)data.len) {
    return false;
  }
  if (base > 0 && (int64_t)end->offset <= (int64_t)data.len) {
    MsSpan probe = ms_span_of(data.ptr + end->offset, data.len - (size_t)end->offset);
    ZipFile ignored;
    if (read_dir_header(&probe, &ignored) == DIR_OK) {
      base = 0;
    }
  }
  *base_out = base;
  return true;
}

bool zip_open(MsSpan data, ZipFile **files_out, size_t *count_out) {
  size_t end_at = 0;
  if (!find_end(data, &end_at)) {
    return false;
  }
  const uint8_t *b = data.ptr + end_at + 4;
  EndRecord end = {u16le(b, 6), u32le(b, 8), u32le(b, 12)};
  int64_t end_offset = (int64_t)end_at;
  int64_t base = 0;
  if (!read_zip64_end(data, &end_offset, &end) || !directory_base(data, end_offset, &end, &base)) {
    return false;
  }
  const uint64_t start = (uint64_t)base + end.offset;
  MsSpan rd = ms_span_of(data.ptr + start, data.len - (size_t)start);
  ZipFile *files = NULL;
  size_t count = 0;
  size_t capacity = 0;
  for (;;) {
    ZipFile file;
    const DirResult result = read_dir_header(&rd, &file);
    if (result == DIR_EOF) {
      ms_free(files);
      return false;
    }
    if (result != DIR_OK) {
      break;
    }
    file.offset = (int64_t)((uint64_t)file.offset + (uint64_t)base);
    void *items = files;
    if (!ms_array_reserve(&items, &capacity, count + 1, sizeof *files)) {
      ms_free(files);
      return false;
    }
    files = items;
    files[count++] = file;
  }
  if ((uint16_t)count != (uint16_t)end.records) {
    ms_free(files);
    return false;
  }
  *files_out = files;
  *count_out = count;
  return true;
}

/* ---- members ---- */

void zip_kind(const ZipFile *file, bool *regular, bool *directory) {
  bool is_dir = false;
  bool irregular = false;
  const unsigned creator = file->creator >> 8;
  if (creator == CREATOR_UNIX || creator == CREATOR_MAC) {
    switch ((file->attrs >> 16) & 0xf000) {
    case 0x6000:
    case 0x2000:
    case 0x1000:
    case 0xa000:
    case 0xc000:
      irregular = true;
      break;
    case 0x4000:
      is_dir = true;
      break;
    default:
      break;
    }
  } else if (creator == CREATOR_NTFS || creator == CREATOR_VFAT || creator == CREATOR_FAT) {
    is_dir = (file->attrs & 0x10) != 0;
  }
  if (file->name.len != 0 && file->name.ptr[file->name.len - 1] == '/') {
    is_dir = true;
  }
  *regular = !is_dir && !irregular;
  *directory = is_dir;
}

static bool body_offset(const ZipFile *file, MsSpan data, size_t *out) {
  if (file->offset < 0 || (uint64_t)file->offset > data.len ||
      data.len - (size_t)file->offset < FILE_HEADER_LEN) {
    return false;
  }
  const uint8_t *hdr = data.ptr + file->offset;
  if (u32le(hdr, 0) != FILE_HEADER_SIG) {
    return false;
  }
  *out = (size_t)file->offset + FILE_HEADER_LEN + u16le(hdr, 26) + u16le(hdr, 28);
  return true;
}

static bool is_dir_name(const ZipFile *file) {
  return file->name.len != 0 && file->name.ptr[file->name.len - 1] == '/';
}

bool zip_check_open(const ZipFile *file, MsSpan data) {
  size_t body = 0;
  if (!body_offset(file, data, &body)) {
    return false;
  }
  return is_dir_name(file) || file->method == 0 || file->method == 8;
}

/* The member's bytes, inflated or stored, checked against the declared sizes. */
static bool member_bytes(const ZipFile *file, MsSpan stored, MsBytes *out) {
  *out = (MsBytes){0};
  if (file->method == 0) {
    if (stored.len != file->compressed_size || file->compressed_size > file->size) {
      return false;
    }
    *out = ms_bytes_from_span(stored);
    return true;
  }
  const MsBytes input = ms_bytes_from_span(stored);
  const MsString format = ms_string_static(ms_span_of_text("deflate"));
  const int64_t room = file->size > (uint64_t)INT64_MAX ? INT64_MAX : (int64_t)file->size;
  const uint8_t status = msstd_compress_decompress(&input, &format, 1, room, out);
  MsBytes released = input;
  ms_bytes_free(&released);
  return status == MS_STATUS_OK;
}

/* Checks the CRC against the local data descriptor when the member has one. */
static bool crc_ok(const ZipFile *file, MsSpan data, size_t body, uint32_t sum) {
  if ((file->flags & 0x8) == 0) {
    return sum == file->crc32;
  }
  if (file->compressed_size > data.len || body > data.len - (size_t)file->compressed_size) {
    return false;
  }
  const size_t at = body + (size_t)file->compressed_size;
  const size_t available = data.len - at < 16 ? data.len - at : 16;
  const uint8_t *d = data.ptr + at;
  const bool signed_descriptor = available >= 4 && u32le(d, 0) == DATA_DESC_SIG;
  const size_t crc_at = signed_descriptor ? 4 : 0;
  const size_t need = signed_descriptor ? 16 : 12;
  return available >= need && u32le(d, crc_at) == file->crc32 && sum == file->crc32;
}

bool zip_read(const ZipFile *file, MsSpan data, MsStrBuild *out) {
  size_t body = 0;
  if (!body_offset(file, data, &body)) {
    return false;
  }
  if (is_dir_name(file)) {
    return file->size == 0;
  }
  const MsSpan avail = body <= data.len ? ms_span_of(data.ptr + body, data.len - body) : ms_span_of(NULL, 0);
  const size_t stored_length = file->compressed_size < avail.len ? (size_t)file->compressed_size : avail.len;
  MsBytes bytes;
  if (!member_bytes(file, ms_span_of(avail.ptr, stored_length), &bytes)) {
    return false;
  }
  const MsSpan content = ms_span_of(bytes.ptr, bytes.len);
  const bool ok = content.len == file->size && crc_ok(file, data, body, crc_of(content));
  if (ok) {
    ms_strbuild_append(out, content);
  }
  ms_free(bytes.ptr);
  return ok;
}

/* ---- writing ---- */

enum { DOS_DATE = (1 << 5) | 1, UNIX_1980 = 315532800, EXTRA_LENGTH = 9 };

static void put16(MsStrBuild *out, uint64_t v) {
  ms_strbuild_append_byte(out, (uint8_t)v);
  ms_strbuild_append_byte(out, (uint8_t)(v >> 8));
}

static void put32(MsStrBuild *out, uint64_t v) {
  put16(out, v & 0xffff);
  put16(out, (v >> 16) & 0xffff);
}

static void put64(MsStrBuild *out, uint64_t v) {
  put32(out, v & 0xffffffff);
  put32(out, v >> 32);
}

static void put_zeros(MsStrBuild *out, size_t count) {
  for (size_t i = 0; i < count; i++) {
    ms_strbuild_append_byte(out, 0);
  }
}

/* The extended timestamp field every header carries: 1980-01-01 00:00:00 UTC. */
static void put_extra(MsStrBuild *out) {
  put16(out, 0x5455);
  put16(out, 5);
  ms_strbuild_append_byte(out, 1);
  put32(out, UNIX_1980);
}

static bool needs_utf8_flag(MsSpan name) {
  for (size_t at = 0; at < name.len;) {
    const MsRune scalar = ms_utf8_decode(name.ptr + at, name.len - at);
    if (scalar.rune == MS_RUNE_ERROR && scalar.width == 1) {
      return false;
    }
    if (scalar.rune < 0x20 || scalar.rune > 0x7d || scalar.rune == '\\') {
      return true;
    }
    at += scalar.width;
  }
  return false;
}

typedef struct Record {
  uint16_t flags;
  uint16_t method;
  uint32_t crc;
  uint64_t compressed_size;
  uint64_t size;
  uint64_t offset;
  uint32_t attrs;
  bool zip64;
} Record;

/* The member's stored bytes: deflated from 64 bytes up (appended to `body`). */
static uint16_t member_body(const ZipMember *m, MsStrBuild *body) {
  if (m->directory) {
    return 0;
  }
  if (m->data.len < STORE_LIMIT) {
    ms_strbuild_append(body, m->data);
    return 0;
  }
  const MsBytes input = ms_bytes_from_span(m->data);
  const MsString format = ms_string_static(ms_span_of_text("deflate"));
  MsBytes packed = {0};
  const uint8_t status = msstd_compress_compress(&input, &format, DEFLATE_LEVEL, 0, 0, &packed);
  MsBytes released = input;
  ms_bytes_free(&released);
  if (status == MS_STATUS_OK) {
    ms_strbuild_append(body, ms_span_of(packed.ptr, packed.len));
  }
  ms_bytes_free(&packed);
  return 8;
}

static Record write_member(MsStrBuild *out, const ZipMember *m) {
  MsStrBuild body = ms_strbuild_new();
  Record r = {.flags = needs_utf8_flag(m->name) ? 0x800 : 0, .offset = ms_strbuild_length(out)};
  r.method = member_body(m, &body);
  if (!m->directory) {
    r.flags |= 0x8;
    r.crc = crc_of(m->data);
    r.size = m->data.len;
  }
  r.compressed_size = ms_strbuild_length(&body);
  r.zip64 = r.compressed_size >= UINT32_MAX || r.size >= UINT32_MAX;
  put32(out, FILE_HEADER_SIG);
  put16(out, r.zip64 ? 45 : 20);
  put16(out, r.flags);
  put16(out, r.method);
  put16(out, 0);
  put16(out, DOS_DATE);
  put_zeros(out, 12);
  put16(out, m->name.len);
  put16(out, EXTRA_LENGTH);
  ms_strbuild_append(out, m->name);
  put_extra(out);
  ms_strbuild_append(out, ms_strbuild_span(&body));
  if (!m->directory) {
    put32(out, DATA_DESC_SIG);
    put32(out, r.crc);
    if (r.zip64) {
      put64(out, r.compressed_size);
      put64(out, r.size);
    } else {
      put32(out, r.compressed_size);
      put32(out, r.size);
    }
  }
  r.attrs = m->directory ? ((0x41c0u << 16) | 0x10u) : (0x8180u << 16);
  ms_strbuild_free(&body);
  return r;
}

static void write_dir_record(MsStrBuild *out, const ZipMember *m, const Record *r) {
  const bool big = r->zip64 || r->offset >= UINT32_MAX;
  put32(out, DIR_HEADER_SIG);
  put16(out, 0x0314);
  put16(out, r->zip64 ? 45 : 20);
  put16(out, r->flags);
  put16(out, r->method);
  put16(out, 0);
  put16(out, DOS_DATE);
  put32(out, r->crc);
  put32(out, big ? UINT32_MAX : (uint32_t)r->compressed_size);
  put32(out, big ? UINT32_MAX : (uint32_t)r->size);
  put16(out, m->name.len);
  put16(out, EXTRA_LENGTH + (big ? 28 : 0));
  put16(out, 0);
  put_zeros(out, 4);
  put32(out, r->attrs);
  put32(out, r->offset > UINT32_MAX ? UINT32_MAX : (uint32_t)r->offset);
  ms_strbuild_append(out, m->name);
  put_extra(out);
  if (big) {
    put16(out, 1);
    put16(out, 24);
    put64(out, r->size);
    put64(out, r->compressed_size);
    put64(out, r->offset);
  }
}

static void write_end(MsStrBuild *out, size_t count, uint64_t start, uint64_t end) {
  uint64_t records = count;
  uint64_t size = end - start;
  uint64_t offset = start;
  if (records >= 0xffff || size >= UINT32_MAX || offset >= UINT32_MAX) {
    put32(out, DIR64_END_SIG);
    put64(out, DIR64_END_LEN - 12);
    put16(out, 45);
    put16(out, 45);
    put32(out, 0);
    put32(out, 0);
    put64(out, records);
    put64(out, records);
    put64(out, size);
    put64(out, offset);
    put32(out, DIR64_LOC_SIG);
    put32(out, 0);
    put64(out, end);
    put32(out, 1);
    records = 0xffff;
    size = UINT32_MAX;
    offset = UINT32_MAX;
  }
  put32(out, DIR_END_SIG);
  put_zeros(out, 4);
  put16(out, records);
  put16(out, records);
  put32(out, size);
  put32(out, offset);
  put16(out, 0);
}

void zip_pack(MsStrBuild *out, const ZipMember *members, size_t count) {
  Record *records = ms_alloc((count + 1) * sizeof *records);
  for (size_t i = 0; i < count; i++) {
    records[i] = write_member(out, &members[i]);
  }
  const uint64_t start = ms_strbuild_length(out);
  for (size_t i = 0; i < count; i++) {
    write_dir_record(out, &members[i], &records[i]);
  }
  write_end(out, count, start, ms_strbuild_length(out));
  ms_free(records);
}
