/* Owns the conversion of folded stacks (profile_folded.h). */
#include "driver/profile_folded.h"

#include "base/alloc.h"
#include "base/sort.h"

/* ---- reading ---- */

static bool parse_count(MsSpan text, uint64_t *out) {
  if (text.len == 0 || text.len > 19) {
    return false;
  }
  uint64_t value = 0;
  for (size_t i = 0; i < text.len; i++) {
    if (text.ptr[i] < '0' || text.ptr[i] > '9') {
      return false;
    }
    value = value * 10 + (uint64_t)(text.ptr[i] - '0');
  }
  *out = value;
  return value > 0;
}

static MsSpan trim_end(MsSpan text) {
  while (text.len > 0 && (text.ptr[text.len - 1] == ' ' || text.ptr[text.len - 1] == '\t' || text.ptr[text.len - 1] == '\r')) {
    text.len--;
  }
  return text;
}

static MsSpan trim(MsSpan text) {
  text = trim_end(text);
  while (text.len > 0 && (text.ptr[0] == ' ' || text.ptr[0] == '\t')) {
    text = ms_span_of(text.ptr + 1, text.len - 1);
  }
  return text;
}

static MsSpan line_error(MsArena *arena, size_t number, const char *what, MsSpan line) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "line ");
  ms_strbuild_append_u64(&text, number);
  ms_strbuild_append_text(&text, ": ");
  ms_strbuild_append_text(&text, what);
  ms_strbuild_append_text(&text, " \"");
  ms_strbuild_append(&text, line);
  ms_strbuild_append_text(&text, "\"");
  const MsSpan copy = ms_arena_copy(arena, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  return copy;
}

/* Handles a `# ...` line: only `# hz=<n>` means anything. False when the header is present but not a positive number. */
static bool read_comment(MsSpan line, uint64_t *hz) {
  const MsSpan body = trim(ms_span_of(line.ptr + 1, line.len - 1));
  const MsSpan key = ms_span_of_text("hz=");
  if (!ms_span_starts_with(body, key)) {
    return true;
  }
  return parse_count(trim(ms_span_of(body.ptr + key.len, body.len - key.len)), hz);
}

/* Adds `count` samples to the stack written `text` (frames joined by `;`), which is new or already seen. */
static bool add_stack(MsFoldedProfile *profile, MsNames *stacks, MsSpan text, uint64_t count) {
  MsU32List frames = {0};
  size_t start = 0;
  for (size_t i = 0; i <= text.len; i++) {
    if (i < text.len && text.ptr[i] != ';') {
      continue;
    }
    if (i == start) {
      ms_u32_list_free(&frames);
      return false; /* an empty frame name */
    }
    ms_u32_list_push(&frames, ms_names_intern(&profile->names, ms_span_of(text.ptr + start, i - start)));
    start = i + 1;
  }
  const size_t before = ms_names_count(stacks);
  const MsName id = ms_names_intern(stacks, text);
  if (ms_names_count(stacks) > before) {
    ms_u32_list_push(&profile->first, (uint32_t)profile->frames.len);
    ms_u32_list_push(&profile->length, (uint32_t)frames.len);
    for (size_t i = 0; i < frames.len; i++) {
      ms_u32_list_push(&profile->frames, frames.ptr[i]);
    }
    ms_u64_list_push(&profile->counts, 0);
  }
  /* Stack ids count from 1 because id 0 is the empty text. */
  profile->counts.ptr[id - 1] += count;
  profile->total += count;
  ms_u32_list_free(&frames);
  return true;
}

bool ms_folded_parse(MsArena *arena, MsSpan text, MsFoldedProfile *out, MsSpan *error) {
  *out = (MsFoldedProfile){.hz = MS_PROFILE_DEFAULT_HZ};
  ms_names_init(&out->names);
  MsNames stacks;
  ms_names_init(&stacks);
  bool ok = true;
  size_t number = 0;
  for (size_t at = 0; at < text.len && ok;) {
    size_t end = at;
    while (end < text.len && text.ptr[end] != '\n') {
      end++;
    }
    const MsSpan line = trim_end(ms_span_of(text.ptr + at, end - at));
    at = end + 1;
    number++;
    if (trim(line).len == 0) {
      continue;
    }
    if (line.ptr[0] == '#') {
      ok = read_comment(line, &out->hz);
      if (!ok) {
        *error = line_error(arena, number, "invalid hz header", line);
      }
      continue;
    }
    size_t space = line.len;
    while (space > 0 && line.ptr[space - 1] != ' ') {
      space--;
    }
    uint64_t count = 0;
    ok = space > 0 && parse_count(ms_span_of(line.ptr + space, line.len - space), &count) &&
         add_stack(out, &stacks, ms_span_of(line.ptr, space - 1), count);
    if (!ok) {
      *error = line_error(arena, number, "expected '<frame>;<frame> <count>', got", line);
    }
  }
  ms_names_free(&stacks);
  if (!ok) {
    ms_folded_free(out);
  }
  return ok;
}

void ms_folded_free(MsFoldedProfile *profile) {
  ms_names_free(&profile->names);
  ms_u32_list_free(&profile->frames);
  ms_u32_list_free(&profile->first);
  ms_u32_list_free(&profile->length);
  ms_u64_list_free(&profile->counts);
  *profile = (MsFoldedProfile){0};
}

uint64_t ms_folded_period_nanos(const MsFoldedProfile *profile) { return UINT64_C(1000000000) / (profile->hz == 0 ? 1 : profile->hz); }

/* ---- ranking ---- */

typedef struct TopOrder {
  const MsNames *names;
} TopOrder;

static int64_t compare_top(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  MsTopEntry left;
  MsTopEntry right;
  __builtin_memcpy(&left, a, sizeof left);
  __builtin_memcpy(&right, b, sizeof right);
  if (left.flat != right.flat) {
    return left.flat > right.flat ? -1 : 1;
  }
  if (left.cum != right.cum) {
    return left.cum > right.cum ? -1 : 1;
  }
  const MsNames *const names = ((const TopOrder *)(void *)env)->names;
  const MsSpan x = ms_names_span(names, left.function);
  const MsSpan y = ms_names_span(names, right.function);
  const size_t common = x.len < y.len ? x.len : y.len;
  const int order = common == 0 ? 0 : __builtin_memcmp(x.ptr, y.ptr, common);
  if (order != 0) {
    return order;
  }
  return x.len < y.len ? -1 : (x.len > y.len ? 1 : 0);
}

void ms_folded_top(const MsFoldedProfile *profile, MsTopList *out) {
  const size_t functions = ms_names_count(&profile->names);
  for (size_t id = 1; id < functions; id++) {
    ms_top_list_push(out, (MsTopEntry){.function = (MsName)id});
  }
  /* The stack that last counted a function in its cumulative samples, so a recursive frame counts once. */
  uint32_t *const last_seen = ms_alloc_zeroed((functions + 1) * sizeof *last_seen);
  for (size_t s = 0; s < profile->first.len; s++) {
    const uint32_t first = profile->first.ptr[s];
    const uint32_t length = profile->length.ptr[s];
    const uint64_t count = profile->counts.ptr[s];
    if (length > 0) {
      out->ptr[profile->frames.ptr[first + length - 1] - 1].flat += count;
    }
    for (uint32_t i = 0; i < length; i++) {
      const uint32_t function = profile->frames.ptr[first + i];
      if (last_seen[function] != s + 1) {
        last_seen[function] = (uint32_t)(s + 1);
        out->ptr[function - 1].cum += count;
      }
    }
  }
  ms_free(last_seen);
  TopOrder order = {.names = &profile->names};
  if (out->len > 0) {
    ms_sort((uint8_t *)out->ptr, out->len, sizeof *out->ptr, compare_top, (uint8_t *)(void *)&order);
  }
}

/* ---- the text report ---- */

uint64_t ms_percent_hundredths(uint64_t part, uint64_t total) {
  if (total == 0) {
    return 0;
  }
  const unsigned __int128 scaled = (unsigned __int128)part * 10000 + total / 2;
  return (uint64_t)(scaled / total);
}

static void pad_to(MsStrBuild *out, size_t used, size_t width) {
  for (; used < width; used++) {
    ms_strbuild_append_byte(out, ' ');
  }
}

static size_t digits_of(uint64_t value) {
  size_t digits = 1;
  for (; value >= 10; value /= 10) {
    digits++;
  }
  return digits;
}

static void put_number(MsStrBuild *out, uint64_t value, size_t width) {
  pad_to(out, digits_of(value), width);
  ms_strbuild_append_u64(out, value);
}

/* `45.45` for 4545 hundredths, right-aligned to `width`. */
static void put_percent(MsStrBuild *out, uint64_t hundredths, size_t width) {
  pad_to(out, digits_of(hundredths / 100) + 3, width);
  ms_strbuild_append_u64(out, hundredths / 100);
  ms_strbuild_append_byte(out, '.');
  ms_strbuild_append_byte(out, (uint8_t)('0' + hundredths % 100 / 10));
  ms_strbuild_append_byte(out, (uint8_t)('0' + hundredths % 10));
}

static void put_right(MsStrBuild *out, const char *text, size_t width) {
  pad_to(out, __builtin_strlen(text), width);
  ms_strbuild_append_text(out, text);
}

void ms_folded_render_top(const MsFoldedProfile *profile, const MsTopList *entries, size_t top, MsStrBuild *out) {
  const uint64_t total = profile->total;
  const size_t shown = entries->len < top ? entries->len : top;
  const uint64_t centiseconds = (uint64_t)(((unsigned __int128)total * ms_folded_period_nanos(profile) + 5000000) / 10000000);
  ms_strbuild_append_text(out, "Showing top ");
  ms_strbuild_append_u64(out, shown);
  ms_strbuild_append_text(out, " of ");
  ms_strbuild_append_u64(out, entries->len);
  ms_strbuild_append_text(out, " functions (");
  ms_strbuild_append_u64(out, total);
  ms_strbuild_append_text(out, " samples, ");
  ms_strbuild_append_u64(out, profile->hz);
  ms_strbuild_append_text(out, " Hz, ");
  ms_strbuild_append_u64(out, centiseconds / 100);
  ms_strbuild_append_byte(out, '.');
  ms_strbuild_append_byte(out, (uint8_t)('0' + centiseconds % 100 / 10));
  ms_strbuild_append_byte(out, (uint8_t)('0' + centiseconds % 10));
  ms_strbuild_append_text(out, "s)\n");
  put_right(out, "flat", 8);
  put_right(out, " flat%", 8);
  put_right(out, " cum", 9);
  put_right(out, " cum%", 8);
  ms_strbuild_append_text(out, "  function\n");
  for (size_t i = 0; i < shown; i++) {
    const MsTopEntry *const entry = &entries->ptr[i];
    put_number(out, entry->flat, 8);
    ms_strbuild_append_byte(out, ' ');
    put_percent(out, ms_percent_hundredths(entry->flat, total), 6);
    ms_strbuild_append_text(out, "% ");
    put_number(out, entry->cum, 8);
    ms_strbuild_append_byte(out, ' ');
    put_percent(out, ms_percent_hundredths(entry->cum, total), 6);
    ms_strbuild_append_text(out, "%  ");
    ms_strbuild_append(out, ms_names_span(&profile->names, entry->function));
    ms_strbuild_append_byte(out, '\n');
  }
  if (total < MS_PROFILE_LOW_SAMPLES) {
    ms_strbuild_append_text(out, "note: ");
    ms_strbuild_append_u64(out, total);
    ms_strbuild_append_text(out, " samples is too few to rank functions; run the program for several seconds (about 100 "
                                 "samples or more) or give it more work\n");
  }
}

/* ---- pprof ---- */

static void varint(MsStrBuild *out, uint64_t value) {
  while (value >= 0x80) {
    ms_strbuild_append_byte(out, (uint8_t)((value & 0x7f) | 0x80));
    value >>= 7;
  }
  ms_strbuild_append_byte(out, (uint8_t)value);
}

static void varint_field(MsStrBuild *out, uint32_t field, uint64_t value) {
  varint(out, (uint64_t)field << 3);
  varint(out, value);
}

static void message(MsStrBuild *out, uint32_t field, MsSpan body) {
  varint(out, ((uint64_t)field << 3) | 2);
  varint(out, body.len);
  ms_strbuild_append(out, body);
}

static void packed(MsStrBuild *out, uint32_t field, const uint64_t *values, size_t count) {
  MsStrBuild body = ms_strbuild_new();
  for (size_t i = 0; i < count; i++) {
    varint(&body, values[i]);
  }
  message(out, field, ms_strbuild_span(&body));
  ms_strbuild_free(&body);
}

static void value_type(MsStrBuild *out, uint32_t field, uint64_t kind, uint64_t unit) {
  MsStrBuild body = ms_strbuild_new();
  varint_field(&body, 1, kind);
  varint_field(&body, 2, unit);
  message(out, field, ms_strbuild_span(&body));
  ms_strbuild_free(&body);
}

void ms_folded_encode_pprof(const MsFoldedProfile *profile, uint64_t time_nanos, MsStrBuild *out) {
  /* The string table: "" first, then the four fixed texts, then one per function name. */
  enum { STR_SAMPLES = 1, STR_COUNT = 2, STR_CPU = 3, STR_NANOS = 4, FIXED_STRINGS = 5 };
  const uint64_t period = ms_folded_period_nanos(profile);
  const size_t functions = ms_names_count(&profile->names) - 1;
  /* Function ids are the interned ids (1 and up); the string index of a function name is FIXED_STRINGS - 1 + id. */
  value_type(out, 1, STR_SAMPLES, STR_COUNT);
  value_type(out, 1, STR_CPU, STR_NANOS);
  for (size_t s = 0; s < profile->first.len; s++) {
    const uint32_t first = profile->first.ptr[s];
    const uint32_t length = profile->length.ptr[s];
    uint64_t *const leaf_first = ms_alloc_zeroed((length == 0 ? 1 : length) * sizeof *leaf_first);
    for (uint32_t i = 0; i < length; i++) {
      leaf_first[i] = profile->frames.ptr[first + length - 1 - i];
    }
    const uint64_t values[2] = {profile->counts.ptr[s], profile->counts.ptr[s] * period};
    MsStrBuild sample = ms_strbuild_new();
    packed(&sample, 1, leaf_first, length);
    packed(&sample, 2, values, 2);
    message(out, 2, ms_strbuild_span(&sample));
    ms_strbuild_free(&sample);
    ms_free(leaf_first);
  }
  for (size_t id = 1; id <= functions; id++) {
    MsStrBuild line = ms_strbuild_new();
    varint_field(&line, 1, id);
    MsStrBuild location = ms_strbuild_new();
    varint_field(&location, 1, id);
    message(&location, 4, ms_strbuild_span(&line));
    message(out, 4, ms_strbuild_span(&location));
    ms_strbuild_free(&location);
    ms_strbuild_free(&line);
  }
  for (size_t id = 1; id <= functions; id++) {
    MsStrBuild function = ms_strbuild_new();
    varint_field(&function, 1, id);
    varint_field(&function, 2, FIXED_STRINGS - 1 + id);
    varint_field(&function, 3, FIXED_STRINGS - 1 + id);
    message(out, 5, ms_strbuild_span(&function));
    ms_strbuild_free(&function);
  }
  message(out, 6, ms_span_of_text(""));
  message(out, 6, ms_span_of_text("samples"));
  message(out, 6, ms_span_of_text("count"));
  message(out, 6, ms_span_of_text("cpu"));
  message(out, 6, ms_span_of_text("nanoseconds"));
  for (size_t id = 1; id <= functions; id++) {
    message(out, 6, ms_names_span(&profile->names, (MsName)id));
  }
  varint_field(out, 9, time_nanos);
  varint_field(out, 10, profile->total * period);
  value_type(out, 11, STR_CPU, STR_NANOS);
  varint_field(out, 12, period);
}
