/* runtime/std/regex_replace.c: the @std/regex replacements: `replace_all` inserts a literal,
 * `replace_template` expands `$1`, `${name}` and `$$` from each match. The output is built in one growing
 * buffer under the caller's byte budget, which every append checks before it copies, so an oversized capture
 * or literal fails without being copied. */
#include "runtime/std/regex_internal.h"

/* ---- the output buffer ---- */

typedef struct ReplaceBuffer {
  MsStrBuild text;
  uint64_t max; /* bytes the result may hold */
} ReplaceBuffer;

/* Appends `bytes`; false when the result would pass the budget or the string limit. */
MS_NODISCARD static bool buffer_append(ReplaceBuffer *buffer, MsSpan bytes) {
  size_t needed = 0;
  if (!ms_size_add(ms_strbuild_length(&buffer->text), bytes.len, &needed) || needed > buffer->max ||
      needed > MS_STRING_MAX_LENGTH) {
    return false;
  }
  ms_strbuild_append(&buffer->text, bytes);
  return true;
}

/* text[start..end]; the offsets come from the engine, so a bad range is a bug in it. */
static MsSpan slice_of(MsSpan text, int64_t start, int64_t end) {
  if (start < 0 || end < start || (uint64_t)end > text.len) {
    return ms_span_of(NULL, 0);
  }
  return ms_span_of(text.ptr + start, (size_t)(end - start));
}

static MsSpan dollar(void) {
  return ms_span_of((const uint8_t *)"$", 1);
}

/* ---- the template ---- */

/* Where a `$` reference ends and what it names. `found` is false for a `$` that is literal. */
typedef struct Reference {
  MsSpan name;
  size_t end; /* template offset after the reference */
  bool found;
} Reference;

static bool is_name_byte(uint8_t byte) {
  return (byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') ||
         byte == '_';
}

/* The reference after the `$` that ended at template[at]: `${...}` up to the first `}`, else the run of name
 * bytes. */
static Reference reference_at(MsSpan tmpl, size_t at) {
  Reference reference = {0};
  if (at < tmpl.len && tmpl.ptr[at] == '{') {
    const uint8_t *close = __builtin_memchr(tmpl.ptr + at + 1, '}', tmpl.len - at - 1);
    if (close != NULL) {
      const size_t close_at = (size_t)(close - tmpl.ptr);
      reference.name = ms_span_of(tmpl.ptr + at + 1, close_at - at - 1);
      reference.end = close_at + 1;
      reference.found = true;
    }
    return reference;
  }
  size_t end = at;
  while (end < tmpl.len && is_name_byte(tmpl.ptr[end])) {
    end++;
  }
  reference.name = ms_span_of(tmpl.ptr + at, end - at);
  reference.end = end;
  reference.found = end > at;
  return reference;
}

/* A group number as Rust's usize parser reads it: digits with an optional leading `+`; false for anything
 * else, overflow included, which makes the reference a name. */
static bool parse_group_number(MsSpan name, size_t *out) {
  size_t at = (name.len > 0 && name.ptr[0] == '+') ? 1 : 0;
  if (at == name.len) {
    return false;
  }
  size_t value = 0;
  for (; at < name.len; at++) {
    const uint8_t digit = name.ptr[at];
    if (digit < '0' || digit > '9' || !ms_size_mul(value, 10, &value) ||
        !ms_size_add(value, (size_t)(digit - '0'), &value)) {
      return false;
    }
  }
  *out = value;
  return true;
}

/* The group a reference names: its number, or the group with that name. SIZE_MAX when no group does. */
static size_t group_of(const MsRegex *re, size_t group_count, MsSpan name) {
  size_t number = 0;
  if (parse_group_number(name, &number)) {
    return number < group_count ? number : SIZE_MAX;
  }
  for (size_t group = 1; group < group_count; group++) {
    const MsSpan group_name = ms_re_group_name(re, group);
    if (group_name.len == name.len && group_name.len != 0 &&
        __builtin_memcmp(group_name.ptr, name.ptr, name.len) == 0) {
      return group;
    }
  }
  return SIZE_MAX;
}

/* What an expansion reads: the pattern, the text and the match. */
typedef struct Expansion {
  const MsRegex *re;
  MsSpan text;
  MsSpan tmpl;
  const MsRegexMatch *match;
} Expansion;

/* Appends the text of a referenced group; an absent group or a name no group has adds nothing. */
static bool append_reference(ReplaceBuffer *out, const Expansion *x, MsSpan name) {
  const size_t group = group_of(x->re, x->match->pair_count, name);
  if (group == SIZE_MAX || x->match->slots[group * 2] < 0) {
    return true;
  }
  return buffer_append(out, slice_of(x->text, x->match->slots[group * 2], x->match->slots[group * 2 + 1]));
}

/* One match's expansion of the template; false when it passes the budget. */
static bool expand_template(ReplaceBuffer *out, const Expansion *x) {
  const MsSpan tmpl = x->tmpl;
  size_t at = 0;
  while (at < tmpl.len) {
    const uint8_t *found = __builtin_memchr(tmpl.ptr + at, '$', tmpl.len - at);
    const size_t stop = found != NULL ? (size_t)(found - tmpl.ptr) : tmpl.len;
    if (!buffer_append(out, ms_span_of(tmpl.ptr + at, stop - at))) {
      return false;
    }
    if (found == NULL) {
      return true;
    }
    at = stop + 1;
    if (at < tmpl.len && tmpl.ptr[at] == '$') {
      at++;
      if (!buffer_append(out, dollar())) {
        return false;
      }
      continue;
    }
    const Reference reference = reference_at(tmpl, at);
    if (!reference
             .found) { /* a lone or unfinished `$` is literal; later dollars may still start references */
      if (!buffer_append(out, dollar())) {
        return false;
      }
      continue;
    }
    if (!append_reference(out, x, reference.name)) {
      return false;
    }
    at = reference.end;
  }
  return true;
}

/* ---- the scans ---- */

typedef struct Replacement {
  const MsRegex *re;
  MsSpan text;
  MsSpan with;   /* the literal or the template */
  bool expand;   /* the template holds a `$` */
  size_t copied; /* text before this offset is in the buffer */
  ReplaceBuffer buffer;
} Replacement;

static uint8_t replace_match(void *state, const MsRegexMatch *match) {
  Replacement *replacement = state;
  const MsSpan between = slice_of(replacement->text, (int64_t)replacement->copied, match->slots[0]);
  if (!buffer_append(&replacement->buffer, between)) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  const Expansion expansion = {
      .re = replacement->re, .text = replacement->text, .tmpl = replacement->with, .match = match};
  const bool fits = replacement->expand ? expand_template(&replacement->buffer, &expansion)
                                        : buffer_append(&replacement->buffer, replacement->with);
  replacement->copied = (size_t)match->slots[1];
  return fits ? MS_STATUS_OK : MS_STATUS_LIMIT_EXCEEDED;
}

static uint8_t replace(const void *handle, const MsString *text, const MsString *with, bool expand,
                       uint8_t has_max, int64_t max, MsString *out) {
  Replacement replacement = {
      .re = ms_regex_of(handle),
      .text = ms_string_span(text),
      .with = ms_string_span(with),
      .buffer = {.text = ms_strbuild_new()},
  };
  replacement.expand = expand && replacement.with.len != 0 &&
                       __builtin_memchr(replacement.with.ptr, '$', replacement.with.len) != NULL;
  if (!ms_regex_budget(has_max, max, &replacement.buffer.max)) {
    return MS_STATUS_INVALID_INPUT;
  }
  uint8_t status = ms_regex_each_match(replacement.re, replacement.text, replace_match, &replacement);
  const MsSpan tail = slice_of(replacement.text, (int64_t)replacement.copied, (int64_t)replacement.text.len);
  if (status == MS_STATUS_OK && !buffer_append(&replacement.buffer, tail)) {
    status = MS_STATUS_LIMIT_EXCEEDED;
  }
  if (status == MS_STATUS_OK) {
    *out = ms_strbuild_finish(&replacement.buffer.text);
  }
  ms_strbuild_free(&replacement.buffer.text);
  return status;
}

uint8_t msstd_regex_replace_all(const void *re, const MsString *text, const MsString *replacement,
                                uint8_t has_max, int64_t max, MsString *out) {
  return replace(re, text, replacement, false, has_max, max, out);
}

uint8_t msstd_regex_replace_template(const void *re, const MsString *text, const MsString *template_text,
                                     uint8_t has_max, int64_t max, MsString *out) {
  return replace(re, text, template_text, true, has_max, max, out);
}
