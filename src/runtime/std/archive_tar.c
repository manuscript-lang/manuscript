/* Tar reading and writing: USTAR, GNU long names and PAX records are read; writing emits USTAR headers when
 * the path fits and PAX path records otherwise, with deterministic metadata. */
#include "base/alloc.h"
#include "base/array.h"
#include "base/fatal.h"
#include "runtime/std/archive_internal.h"

enum {
  BLOCK = 512,
  TYPE_X_HEADER = 'x',
  TYPE_GNU_LONG_NAME = 'L',
  TYPE_GNU_LONG_LINK = 'K',
  TYPE_GNU_SPARSE = 'S',
  MAX_SPECIAL = 1 << 20,
  NAME_FIELD = 100,
  PREFIX_FIELD = 155
};

typedef enum Format { FORMAT_UNKNOWN, FORMAT_V7, FORMAT_USTAR_PAX, FORMAT_STAR, FORMAT_GNU } Format;

/* A PAX record: views into the special file's body. */
typedef struct PaxRecord {
  MsSpan key;
  MsSpan value;
} PaxRecord;

typedef struct PaxList {
  PaxRecord *items;
  size_t count;
  size_t capacity;
} PaxList;

static MsSpan sub(MsSpan s, size_t from, size_t to) {
  return ms_span_of(s.ptr + from, to - from);
}

static MsSpan parse_string(MsSpan b) {
  for (size_t i = 0; i < b.len; i++) {
    if (b.ptr[i] == 0) {
      return ms_span_of(b.ptr, i);
    }
  }
  return b;
}

static bool is_pad(uint8_t c) {
  return c == ' ' || c == 0;
}

static bool parse_octal(MsSpan b, int64_t *out) {
  size_t start = 0;
  size_t end = b.len;
  while (start < end && is_pad(b.ptr[start])) {
    start++;
  }
  while (end > start && is_pad(b.ptr[end - 1])) {
    end--;
  }
  *out = 0;
  if (start == end) {
    return true;
  }
  const MsSpan s = parse_string(sub(b, start, end));
  if (s.len == 0) {
    return false;
  }
  uint64_t x = 0;
  for (size_t i = 0; i < s.len; i++) {
    if (s.ptr[i] < '0' || s.ptr[i] > '7' || x > (UINT64_MAX - 7) / 8) {
      return false;
    }
    x = x * 8 + (uint64_t)(s.ptr[i] - '0');
  }
  *out = (int64_t)x;
  return true;
}

static bool parse_numeric(MsSpan b, int64_t *out) {
  if (b.len == 0 || (b.ptr[0] & 0x80) == 0) {
    return parse_octal(b, out);
  }
  const uint8_t inverse = (b.ptr[0] & 0x40) != 0 ? 0xff : 0;
  uint64_t x = 0;
  for (size_t i = 0; i < b.len; i++) {
    uint8_t c = (uint8_t)(b.ptr[i] ^ inverse);
    c = i == 0 ? (uint8_t)(c & 0x7f) : c;
    if ((x >> 56) > 0) {
      return false;
    }
    x = (x << 8) | c;
  }
  if ((x >> 63) > 0) {
    return false;
  }
  *out = inverse == 0xff ? (int64_t)~x : (int64_t)x;
  return true;
}

static void checksums(const uint8_t *b, int64_t *unsigned_sum, int64_t *signed_sum) {
  *unsigned_sum = 0;
  *signed_sum = 0;
  for (size_t i = 0; i < BLOCK; i++) {
    const uint8_t c = (i >= 148 && i < 156) ? ' ' : b[i];
    *unsigned_sum += c;
    *signed_sum += (int8_t)c;
  }
}

static bool field_is(const uint8_t *b, size_t at, const char *text, size_t length) {
  return ms_span_equal(ms_span_of(b + at, length), ms_span_of((const uint8_t *)text, length));
}

static Format block_format(const uint8_t *b) {
  int64_t value = 0;
  int64_t unsigned_sum = 0;
  int64_t signed_sum = 0;
  if (!parse_octal(ms_span_of(b + 148, 8), &value)) {
    return FORMAT_UNKNOWN;
  }
  checksums(b, &unsigned_sum, &signed_sum);
  if (value != unsigned_sum && value != signed_sum) {
    return FORMAT_UNKNOWN;
  }
  const bool ustar = field_is(b, 257, "ustar\0", 6);
  if (ustar && field_is(b, 508, "tar\0", 4)) {
    return FORMAT_STAR;
  }
  if (ustar) {
    return FORMAT_USTAR_PAX;
  }
  return field_is(b, 257, "ustar ", 6) && field_is(b, 263, " \0", 2) ? FORMAT_GNU : FORMAT_V7;
}

static bool is_header_only(uint8_t flag) {
  return flag >= '1' && flag <= '6';
}

static size_t padding(int64_t n) {
  return (size_t)((-n) & (BLOCK - 1));
}

static bool is_ascii(MsSpan s) {
  for (size_t i = 0; i < s.len; i++) {
    if (s.ptr[i] >= 0x80 || s.ptr[i] == 0) {
      return false;
    }
  }
  return true;
}

static bool parse_dec(MsSpan s, int64_t *out) {
  size_t i = 0;
  bool negative = false;
  if (s.len > 0 && (s.ptr[0] == '+' || s.ptr[0] == '-')) {
    negative = s.ptr[0] == '-';
    i = 1;
  }
  if (i == s.len) {
    return false;
  }
  uint64_t x = 0;
  for (; i < s.len; i++) {
    if (s.ptr[i] < '0' || s.ptr[i] > '9' || x > (UINT64_MAX - 9) / 10) {
      return false;
    }
    x = x * 10 + (uint64_t)(s.ptr[i] - '0');
  }
  if (x > (negative ? (uint64_t)INT64_MAX + 1 : (uint64_t)INT64_MAX)) {
    return false;
  }
  *out = negative ? (int64_t)(0 - x) : (int64_t)x;
  return true;
}

static bool is_zero_block(MsSpan block) {
  for (size_t i = 0; i < block.len; i++) {
    if (block.ptr[i] != 0) {
      return false;
    }
  }
  return true;
}

/* Takes `n` bytes; false when fewer remain. */
static bool take(TarReader *r, size_t n, MsSpan *out) {
  if (n > r->data.len - r->pos) {
    return false;
  }
  *out = ms_span_of(r->data.ptr + r->pos, n);
  r->pos += n;
  return true;
}

/* Checks the numeric fields of a block (mode, ids, size, mtime and the device numbers); sets `size`. */
static bool validate_fields(const uint8_t *b, Format format, int64_t *size) {
  static const size_t OFFSETS[] = {100, 108, 116, 136};
  int64_t ignored = 0;
  if (!parse_numeric(ms_span_of(b + 124, 12), size)) {
    return false;
  }
  for (size_t i = 0; i < sizeof OFFSETS / sizeof OFFSETS[0]; i++) {
    if (!parse_numeric(ms_span_of(b + OFFSETS[i], i == 3 ? 12 : 8), &ignored)) {
      return false;
    }
  }
  if (format == FORMAT_V7) {
    return true;
  }
  return parse_numeric(ms_span_of(b + 329, 8), &ignored) && parse_numeric(ms_span_of(b + 337, 8), &ignored) &&
         (format != FORMAT_STAR || (parse_numeric(ms_span_of(b + 476, 12), &ignored) &&
                                    parse_numeric(ms_span_of(b + 488, 12), &ignored)));
}

static bool times_ok(MsSpan r) {
  int64_t ignored = 0;
  return r.ptr[0] == 0 || parse_numeric(r, &ignored);
}

/* The prefix field a format defines (empty for none). */
static MsSpan header_prefix(const uint8_t *b, Format format) {
  const MsSpan none = ms_span_of(NULL, 0);
  if (format == FORMAT_USTAR_PAX) {
    return parse_string(ms_span_of(b + 345, PREFIX_FIELD));
  }
  if (format == FORMAT_STAR) {
    return parse_string(ms_span_of(b + 345, 131));
  }
  if (format == FORMAT_GNU && !(times_ok(ms_span_of(b + 345, 12)) && times_ok(ms_span_of(b + 357, 12)))) {
    /* Pre-Go1.8 writers: the fields are really the USTAR prefix. */
    const MsSpan p = parse_string(ms_span_of(b + 345, PREFIX_FIELD));
    return is_ascii(p) ? p : none;
  }
  return none;
}

/* One header: 1 with name, typeflag and size, 0 at the end, -1 when malformed. */
static int read_header(TarReader *r, MsStrBuild *name, uint8_t *typeflag, int64_t *size, Format *format) {
  if (r->pos >= r->data.len) {
    return 0;
  }
  MsSpan block;
  if (!take(r, BLOCK, &block)) {
    return -1;
  }
  if (is_zero_block(block)) {
    MsSpan second;
    if (r->pos >= r->data.len) {
      return 0;
    }
    return take(r, BLOCK, &second) && is_zero_block(second) ? 0 : -1;
  }
  *format = block_format(block.ptr);
  if (*format == FORMAT_UNKNOWN || !validate_fields(block.ptr, *format, size)) {
    return -1;
  }
  const MsSpan prefix = header_prefix(block.ptr, *format);
  if (prefix.len != 0) {
    ms_strbuild_append(name, prefix);
    ms_strbuild_append_byte(name, '/');
  }
  ms_strbuild_append(name, parse_string(ms_span_of(block.ptr, NAME_FIELD)));
  *typeflag = block.ptr[156];
  return 1;
}

/* Reads a PAX or GNU special file of `size` bytes. */
static bool special(TarReader *r, int64_t size, MsSpan *body) {
  if (size < 0 || size > MAX_SPECIAL) {
    return false;
  }
  return take(r, (size_t)size, body);
}

static bool pax_valid_record(MsSpan key, MsSpan value) {
  if (key.len == 0 || ms_span_has_byte(key, '=')) {
    return false;
  }
  const bool value_key = ms_span_is_text(key, "path") || ms_span_is_text(key, "linkpath") ||
                         ms_span_is_text(key, "uname") || ms_span_is_text(key, "gname");
  return !(value_key ? ms_span_has_byte(value, 0) : ms_span_has_byte(key, 0));
}

static void pax_add(PaxList *list, MsSpan key, MsSpan value) {
  void *items = list->items;
  if (!ms_array_reserve(&items, &list->capacity, list->count + 1, sizeof *list->items)) {
    ms_fatal(MS_FATAL_OUT_OF_MEMORY, "tar: too many PAX records");
  }
  list->items = items;
  list->items[list->count++] = (PaxRecord){key, value};
}

static void pax_free(PaxList *list) {
  ms_free(list->items);
  *list = (PaxList){0};
}

/* Checks the sparse offset and numbytes records alternate; false when they do not. */
static bool sparse_record_ok(MsSpan key, MsSpan value, size_t *seen) {
  const bool want_offset = *seen % 2 == 0;
  if ((want_offset && !ms_span_is_text(key, "GNU.sparse.offset")) ||
      (!want_offset && !ms_span_is_text(key, "GNU.sparse.numbytes")) || ms_span_has_byte(value, ',')) {
    return false;
  }
  (*seen)++;
  return true;
}

/* One `<length> <key>=<value>\n` record at the start of `s`; advances `s`. */
static bool pax_next(MsSpan *s, MsSpan *key, MsSpan *value) {
  size_t space = 0;
  while (space < s->len && s->ptr[space] != ' ') {
    space++;
  }
  int64_t n = 0;
  if (space == s->len || !parse_dec(ms_span_of(s->ptr, space), &n) || n < 5 || n > (int64_t)s->len ||
      (size_t)n < space + 1) {
    return false;
  }
  const size_t body = (size_t)n - (space + 1);
  if (body == 0 || space + 1 + body > s->len || s->ptr[space + body] != '\n') {
    return false;
  }
  const MsSpan record = ms_span_of(s->ptr + space + 1, body - 1);
  size_t eq = 0;
  while (eq < record.len && record.ptr[eq] != '=') {
    eq++;
  }
  if (eq == record.len) {
    return false;
  }
  *key = ms_span_of(record.ptr, eq);
  *value = ms_span_of(record.ptr + eq + 1, record.len - eq - 1);
  *s = ms_span_of(s->ptr + space + 1 + body, s->len - space - 1 - body);
  return pax_valid_record(*key, *value);
}

static bool parse_pax(MsSpan s, PaxList *out) {
  size_t sparse_seen = 0;
  while (s.len != 0) {
    MsSpan key;
    MsSpan value;
    if (!pax_next(&s, &key, &value)) {
      return false;
    }
    const bool sparse =
        ms_span_is_text(key, "GNU.sparse.offset") || ms_span_is_text(key, "GNU.sparse.numbytes");
    if (!sparse) {
      pax_add(out, key, value);
    } else if (sparse_record_ok(key, value, &sparse_seen)) {
      pax_add(out, ms_span_of_text("GNU.sparse.map"), ms_span_of(NULL, 0));
    } else {
      return false;
    }
  }
  return true;
}

static bool parse_pax_time(MsSpan s) {
  size_t dot = s.len;
  for (size_t i = 0; i < s.len; i++) {
    if (s.ptr[i] == '.') {
      dot = i;
      break;
    }
  }
  int64_t seconds = 0;
  if (!parse_dec(ms_span_of(s.ptr, dot), &seconds)) {
    return false;
  }
  for (size_t i = dot + 1; i < s.len; i++) {
    if (s.ptr[i] < '0' || s.ptr[i] > '9') {
      return false;
    }
  }
  return true;
}

static bool merge_record(TarItem *item, const PaxRecord *record) {
  int64_t number = 0;
  const MsSpan key = record->key;
  if (record->value.len == 0) {
    return true;
  }
  if (ms_span_is_text(key, "path")) {
    ms_strbuild_clear(&item->name);
    ms_strbuild_append(&item->name, record->value);
    return true;
  }
  if (ms_span_is_text(key, "uid") || ms_span_is_text(key, "gid")) {
    return parse_dec(record->value, &number);
  }
  if (ms_span_is_text(key, "atime") || ms_span_is_text(key, "mtime") || ms_span_is_text(key, "ctime")) {
    return parse_pax_time(record->value);
  }
  if (ms_span_is_text(key, "size")) {
    return parse_dec(record->value, &item->size);
  }
  return true;
}

static bool merge_pax(TarItem *item, const PaxList *records) {
  bool sparse = false;
  for (size_t i = 0; i < records->count; i++) {
    if (!merge_record(item, &records->items[i])) {
      return false;
    }
    sparse = sparse || ms_span_starts_with_text(records->items[i].key, "GNU.sparse.");
  }
  if (sparse) {
    item->typeflag = TYPE_GNU_SPARSE; /* treated as an unsupported typeflag */
  }
  return true;
}

void tar_item_free(TarItem *item) {
  ms_strbuild_free(&item->name);
}

/* Handles a PAX header; true when `item` is complete (a global header) rather than a prefix of the next
 * entry. */
static int read_pax(TarReader *r, TarItem *item, int64_t size, PaxList *records, bool *done) {
  MsSpan body;
  *done = false;
  if (!special(r, size, &body) || !parse_pax(body, records)) {
    return -1;
  }
  if (item->typeflag == TAR_TYPE_X_GLOBAL) {
    if (!merge_pax(item, records)) {
      return -1;
    }
    item->typeflag = TAR_TYPE_X_GLOBAL;
    item->size = 0;
    item->start = r->pos;
    item->length = 0;
    *done = true;
  }
  return 1;
}

/* Fills the data section of a regular entry: the declared bytes, or what the archive still holds. */
static void place_data(TarReader *r, TarItem *item, int64_t declared) {
  const size_t available = r->data.len - (r->pos < r->data.len ? r->pos : r->data.len);
  item->start = r->pos;
  item->truncated = (uint64_t)declared > available;
  item->length = item->truncated ? available : (size_t)declared;
  r->pos += item->length;
}

/* A GNU long name or long link special: the name is kept for the next entry. */
static bool read_long_name(TarReader *r, uint8_t typeflag, int64_t size, MsStrBuild *long_name) {
  MsSpan body;
  if (!special(r, size, &body)) {
    return false;
  }
  if (typeflag == TYPE_GNU_LONG_NAME) {
    ms_strbuild_clear(long_name);
    ms_strbuild_append(long_name, parse_string(body));
  }
  return true;
}

typedef struct TarState {
  PaxList pax;
  bool have_pax;
  MsStrBuild long_name;
} TarState;

static int next_item(TarReader *r, TarItem *item, TarState *state) {
  for (;;) {
    MsSpan skipped;
    if (!take(r, r->pad, &skipped)) {
      return 0; /* a short tail is a clean end */
    }
    r->pad = 0;
    Format format = FORMAT_UNKNOWN;
    ms_strbuild_clear(&item->name);
    const int header = read_header(r, &item->name, &item->typeflag, &item->size, &format);
    if (header <= 0) {
      return header;
    }
    const int64_t declared = is_header_only(item->typeflag) ? 0 : item->size;
    if (declared < 0) {
      return -1;
    }
    r->pad = padding(declared);
    if (item->typeflag == TYPE_X_HEADER || item->typeflag == TAR_TYPE_X_GLOBAL) {
      bool done = false;
      pax_free(&state->pax);
      state->have_pax = item->typeflag == TYPE_X_HEADER;
      if (read_pax(r, item, declared, &state->pax, &done) < 0) {
        return -1;
      }
      if (done) {
        return 1;
      }
      continue;
    }
    if (item->typeflag == TYPE_GNU_LONG_NAME || item->typeflag == TYPE_GNU_LONG_LINK) {
      if (!read_long_name(r, item->typeflag, declared, &state->long_name)) {
        return -1;
      }
      continue;
    }
    const bool old_sparse = item->typeflag == TYPE_GNU_SPARSE;
    if (state->have_pax && !merge_pax(item, &state->pax)) {
      return -1;
    }
    if (state->long_name.bytes.len != 0) {
      ms_strbuild_clear(&item->name);
      ms_strbuild_append(&item->name, ms_strbuild_span(&state->long_name));
      ms_strbuild_clear(&state->long_name);
    }
    if (item->typeflag == TAR_TYPE_REG_A) {
      const MsSpan name = ms_strbuild_span(&item->name);
      item->typeflag = name.len != 0 && name.ptr[name.len - 1] == '/' ? TAR_TYPE_DIR : TAR_TYPE_REG;
    }
    const int64_t body = is_header_only(item->typeflag) ? 0 : item->size;
    if (body < 0 || (old_sparse && format != FORMAT_GNU)) {
      return -1;
    }
    r->pad = padding(body);
    place_data(r, item, body);
    return 1;
  }
}

int tar_next(TarReader *r, TarItem *item) {
  *item = (TarItem){0};
  TarState state = {0};
  const int status = next_item(r, item, &state);
  pax_free(&state.pax);
  ms_strbuild_free(&state.long_name);
  if (status <= 0) {
    tar_item_free(item);
  }
  return status;
}

/* ---- writing ---- */

static void put_string(uint8_t *field, size_t field_length, MsSpan s) {
  const size_t n = s.len < field_length ? s.len : field_length;
  for (size_t i = 0; i < n; i++) {
    field[i] = s.ptr[i];
  }
  if (s.len < field_length) {
    field[s.len] = 0;
  }
  if (s.len > field_length && field[field_length - 1] == '/') {
    size_t end = field_length - 1;
    while (end > 0 && s.ptr[end - 1] == '/') {
      end--;
    }
    field[end] = 0;
  }
}

static void octal(uint8_t *field, size_t field_length, uint64_t x) {
  uint8_t digits[24];
  size_t count = 0;
  do {
    digits[count++] = (uint8_t)('0' + (x & 7));
    x >>= 3;
  } while (x != 0);
  uint8_t text[24];
  const size_t width = field_length - 1;
  size_t length = 0;
  for (size_t i = count; i < width; i++) {
    text[length++] = '0';
  }
  while (count > 0) {
    text[length++] = digits[--count];
  }
  put_string(field, field_length, ms_span_of(text, length));
}

static void finish_block(uint8_t *b) {
  int64_t unsigned_sum = 0;
  int64_t signed_sum = 0;
  for (size_t i = 148; i < 156; i++) {
    b[i] = ' ';
  }
  checksums(b, &unsigned_sum, &signed_sum);
  octal(b + 148, 7, (uint64_t)unsigned_sum);
  b[155] = ' ';
}

/* Go's splitUSTARPath: false when the name cannot be split into prefix and name fields. */
static bool split_ustar(MsSpan name, MsSpan *prefix, MsSpan *suffix) {
  size_t length = name.len;
  if (length <= NAME_FIELD || !is_ascii(name)) {
    return false;
  }
  if (length > 156) {
    length = 156;
  } else if (name.ptr[length - 1] == '/') {
    length--;
  }
  size_t i = length;
  while (i > 0 && name.ptr[i - 1] != '/') {
    i--;
  }
  if (i == 0) {
    return false;
  }
  i--;
  const size_t suffix_length = name.len - i - 1;
  if (i == 0 || suffix_length > NAME_FIELD || suffix_length == 0 || i > PREFIX_FIELD) {
    return false;
  }
  *prefix = ms_span_of(name.ptr, i);
  *suffix = ms_span_of(name.ptr + i + 1, suffix_length);
  return true;
}

static void append_pax_record(MsStrBuild *out, const char *key, MsSpan value) {
  const size_t base = ms_span_of_text(key).len + value.len + 3;
  size_t size = base;
  MsStrBuild digits = ms_strbuild_new();
  ms_strbuild_append_u64(&digits, base);
  size += ms_strbuild_length(&digits);
  ms_strbuild_free(&digits);
  MsStrBuild rec = ms_strbuild_new();
  for (int pass = 0; pass < 2; pass++) {
    ms_strbuild_clear(&rec);
    ms_strbuild_append_u64(&rec, size);
    ms_strbuild_append_byte(&rec, ' ');
    ms_strbuild_append_text(&rec, key);
    ms_strbuild_append_byte(&rec, '=');
    ms_strbuild_append(&rec, value);
    ms_strbuild_append_byte(&rec, '\n');
    if (ms_strbuild_length(&rec) == size) {
      break;
    }
    size = ms_strbuild_length(&rec);
  }
  ms_strbuild_append(out, ms_strbuild_span(&rec));
  ms_strbuild_free(&rec);
}

/* path.Join(dir, "PaxHeaders.0", file) for already clean parts, as the pax header's own name. */
static void pax_header_name(MsSpan name, MsStrBuild *out) {
  size_t slash = name.len;
  for (size_t i = name.len; i > 0; i--) {
    if (name.ptr[i - 1] == '/') {
      slash = i - 1;
      break;
    }
  }
  const MsSpan dir = slash < name.len ? ms_span_of(name.ptr, slash + 1) : ms_span_of(NULL, 0);
  const MsSpan file = slash < name.len ? ms_span_of(name.ptr + slash + 1, name.len - slash - 1) : name;
  const MsSpan parts[3] = {dir, ms_span_of_text("PaxHeaders.0"), file};
  /* The segments of the three parts, with "." and empty ones dropped and ".." removing the previous one. */
  MsSpan stack[256];
  size_t depth = 0;
  for (size_t p = 0; p < 3; p++) {
    size_t start = 0;
    for (size_t i = 0; i <= parts[p].len; i++) {
      if (i < parts[p].len && parts[p].ptr[i] != '/') {
        continue;
      }
      const MsSpan seg = ms_span_of(parts[p].ptr + start, i - start);
      start = i + 1;
      if (seg.len == 0 || ms_span_is_text(seg, ".")) {
        continue;
      }
      if (ms_span_is_text(seg, "..") && depth > 0 && !ms_span_is_text(stack[depth - 1], "..")) {
        depth--;
      } else if (depth < sizeof stack / sizeof stack[0]) {
        stack[depth++] = seg;
      }
    }
  }
  for (size_t i = 0; i < depth; i++) {
    if (i > 0) {
      ms_strbuild_append_byte(out, '/');
    }
    ms_strbuild_append(out, stack[i]);
  }
}

static void append_ascii(MsStrBuild *out, MsSpan s, size_t limit) {
  size_t kept = 0;
  for (size_t i = 0; i < s.len && kept < limit; i++) {
    if (s.ptr[i] < 0x80 && s.ptr[i] != 0) {
      ms_strbuild_append_byte(out, s.ptr[i]);
      kept++;
    }
  }
}

static void pad_block(MsStrBuild *out) {
  for (size_t n = padding((int64_t)ms_strbuild_length(out)); n > 0; n--) {
    ms_strbuild_append_byte(out, 0);
  }
}

static void common_fields(uint8_t *b, uint64_t mode, uint64_t size, uint8_t flag, bool devices) {
  octal(b + 100, 8, mode);
  octal(b + 108, 8, 0);
  octal(b + 116, 8, 0);
  octal(b + 124, 12, size);
  octal(b + 136, 12, 0);
  b[156] = flag;
  if (devices) {
    octal(b + 329, 8, 0);
    octal(b + 337, 8, 0);
  }
  b[257] = 'u';
  b[258] = 's';
  b[259] = 't';
  b[260] = 'a';
  b[261] = 'r';
  b[262] = 0;
  b[263] = '0';
  b[264] = '0';
  finish_block(b);
}

static void raw_pax(MsStrBuild *out, MsSpan name, MsSpan data) {
  uint8_t b[BLOCK] = {0};
  put_string(b, NAME_FIELD, name);
  common_fields(b, 0, data.len, TYPE_X_HEADER, false);
  ms_strbuild_append(out, ms_span_of(b, BLOCK));
  ms_strbuild_append(out, data);
  pad_block(out);
}

bool tar_write_entry(MsStrBuild *out, MsSpan name, MsSpan data, bool directory) {
  const uint64_t size = directory ? 0 : data.len;
  if (size >= (UINT64_C(1) << 33)) {
    return false;
  }
  uint8_t b[BLOCK] = {0};
  MsSpan prefix = ms_span_of(NULL, 0);
  MsSpan suffix = name;
  const bool split = split_ustar(name, &prefix, &suffix);
  if ((name.len <= NAME_FIELD && is_ascii(name)) || split) {
    put_string(b, NAME_FIELD, suffix);
    put_string(b + 345, PREFIX_FIELD, prefix);
  } else {
    MsStrBuild record = ms_strbuild_new();
    MsStrBuild pax_name = ms_strbuild_new();
    MsStrBuild ascii = ms_strbuild_new();
    MsStrBuild joined = ms_strbuild_new();
    append_pax_record(&record, "path", name);
    pax_header_name(name, &joined);
    append_ascii(&pax_name, ms_strbuild_span(&joined), NAME_FIELD);
    while (ms_strbuild_length(&pax_name) != 0 &&
           ms_strbuild_span(&pax_name).ptr[ms_strbuild_length(&pax_name) - 1] == '/') {
      pax_name.bytes.len--;
    }
    raw_pax(out, ms_strbuild_span(&pax_name), ms_strbuild_span(&record));
    append_ascii(&ascii, name, name.len);
    put_string(b, NAME_FIELD, ms_strbuild_span(&ascii));
    ms_strbuild_free(&record);
    ms_strbuild_free(&pax_name);
    ms_strbuild_free(&ascii);
    ms_strbuild_free(&joined);
  }
  common_fields(b, directory ? 0700 : 0600, size, directory ? TAR_TYPE_DIR : TAR_TYPE_REG, true);
  ms_strbuild_append(out, ms_span_of(b, BLOCK));
  if (!directory) {
    ms_strbuild_append(out, data);
  }
  pad_block(out);
  return true;
}

void tar_finish(MsStrBuild *out) {
  for (size_t i = 0; i < 2 * BLOCK; i++) {
    ms_strbuild_append_byte(out, 0);
  }
}
