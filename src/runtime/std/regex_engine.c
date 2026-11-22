/* runtime/std/regex_engine.c: @std/regex on PCRE2: compiling a pattern and searching a text; see
 * regex_engine.h for the dialect and the limits. */
#define PCRE2_CODE_UNIT_WIDTH 8
#include "runtime/std/regex_engine.h"

#include "base/alloc.h"
#include "base/chars.h"

#include <pcre2.h>
#include <string.h>

/* PCRE2 allocates through the runtime, so its memory is the program's memory. */
static void *engine_alloc(PCRE2_SIZE size, void *unused) {
  (void)unused;
  return ms_alloc(size);
}

static void engine_free(void *block, void *unused) {
  (void)unused;
  ms_free(block);
}

struct MsRegex {
  pcre2_code *code;
  pcre2_match_context
      *context; /* limits; read-only during matching, so a handle may be used from many threads */
  uint32_t slots;
};

static void refuse(MsStrBuild *error, const char *reason, size_t column) {
  ms_strbuild_append_text(error, reason);
  ms_strbuild_append_text(error, " at column ");
  ms_strbuild_append_u64(error, column);
}

/* The offset of the innermost `(` a pattern leaves unclosed. */
static size_t unclosed_group(MsSpan pattern) {
  size_t stack[64];
  size_t depth = 0;
  bool in_class = false;
  for (size_t at = 0; at < pattern.len; at++) {
    const uint8_t byte = pattern.ptr[at];
    if (byte == '\\') {
      at++;
    } else if (in_class) {
      in_class = byte != ']';
    } else if (byte == '[') {
      in_class = true;
      at += at + 1 < pattern.len && pattern.ptr[at + 1] == '^' ? 1 : 0;
      at += at + 1 < pattern.len && pattern.ptr[at + 1] == ']' ? 1 : 0;
    } else if (byte == '(' && depth < 64) {
      stack[depth++] = at;
    } else if (byte == ')' && depth > 0) {
      depth--;
    }
  }
  return depth > 0 ? stack[depth - 1] : 0;
}

/* The offset of the second `(?P<name>` or `(?<name>` that reuses a name. */
static size_t duplicate_name(MsSpan pattern) {
  size_t starts[64];
  size_t ends[64];
  size_t count = 0;
  for (size_t at = 0; at + 3 < pattern.len; at++) {
    if (pattern.ptr[at] == '\\') {
      at++;
      continue;
    }
    size_t name = 0;
    if (pattern.ptr[at] == '(' && pattern.ptr[at + 1] == '?' && pattern.ptr[at + 2] == 'P' && pattern.ptr[at + 3] == '<') {
      name = at + 4;
    } else if (pattern.ptr[at] == '(' && pattern.ptr[at + 1] == '?' && pattern.ptr[at + 2] == '<' &&
               pattern.ptr[at + 3] != '=' && pattern.ptr[at + 3] != '!') {
      name = at + 3;
    }
    if (name == 0) {
      continue;
    }
    size_t end = name;
    while (end < pattern.len && pattern.ptr[end] != '>') {
      end++;
    }
    for (size_t k = 0; k < count; k++) {
      if (ms_span_equal(ms_span_of(pattern.ptr + starts[k], ends[k] - starts[k]), ms_span_of(pattern.ptr + name, end - name))) {
        return name;
      }
    }
    if (count < 64) {
      starts[count] = name;
      ends[count++] = end;
    }
  }
  return 0;
}

/* The offset of the `[` that opens the character class a pattern leaves unclosed. */
static size_t unclosed_class(MsSpan pattern) {
  size_t open = 0;
  bool in_class = false;
  for (size_t at = 0; at < pattern.len; at++) {
    const uint8_t byte = pattern.ptr[at];
    if (byte == '\\') {
      at++;
    } else if (!in_class && byte == '[') {
      in_class = true;
      open = at;
    } else if (in_class && byte == ']' && at > open + 1 && !(at == open + 2 && pattern.ptr[open + 1] == '^')) {
      in_class = false;
    }
  }
  return open;
}

/* Compiles with the dialect's options; NULL with the reason in `error`. */
static pcre2_code *compile_code(pcre2_general_context *general, MsSpan pattern, MsStrBuild *error) {
  pcre2_compile_context *options = pcre2_compile_context_create(general);
  if (options == NULL) {
    refuse(error, "out of memory", 1);
    return NULL;
  }
  pcre2_set_newline(options, PCRE2_NEWLINE_LF);
  int code_error = 0;
  PCRE2_SIZE offset = 0;
  const uint32_t flags = PCRE2_UTF | PCRE2_UCP | PCRE2_DOLLAR_ENDONLY | PCRE2_NEVER_BACKSLASH_C;
  pcre2_code *code =
      pcre2_compile((PCRE2_SPTR)pattern.ptr, pattern.len, flags, &code_error, &offset, options);
  pcre2_compile_context_free(options);
  if (code == NULL && code_error == PCRE2_ERROR_MISSING_CLOSING_PARENTHESIS) {
    refuse(error, "unclosed group", ms_re_column(pattern, unclosed_group(pattern)));
  } else if (code == NULL && code_error == PCRE2_ERROR_DUPLICATE_SUBPATTERN_NAME) {
    refuse(error, "duplicate capture group name", ms_re_column(pattern, duplicate_name(pattern)));
  } else if (code == NULL && code_error == PCRE2_ERROR_MISSING_SQUARE_BRACKET) {
    refuse(error, "unclosed character class", ms_re_column(pattern, unclosed_class(pattern)));
  } else if (code == NULL) {
    PCRE2_UCHAR text[160];
    const bool known = pcre2_get_error_message(code_error, text, sizeof text) >= 0;
    refuse(error, known ? (const char *)text : "invalid pattern", ms_re_column(pattern, offset));
  }
  return code;
}

/* The regex around compiled code, with the match limits; NULL when the pattern uses a back-reference. */
static MsRegex *wrap_code(pcre2_general_context *general, pcre2_code *code, MsStrBuild *error) {
  uint32_t backref = 0;
  uint32_t captures = 0;
  pcre2_pattern_info(code, PCRE2_INFO_BACKREFMAX, &backref);
  pcre2_pattern_info(code, PCRE2_INFO_CAPTURECOUNT, &captures);
  if (backref != 0) {
    refuse(error, "back-references and subroutine calls are not supported", 1);
    pcre2_code_free(code);
    return NULL;
  }
  pcre2_match_context *context = pcre2_match_context_create(general);
  if (context == NULL) {
    refuse(error, "out of memory", 1);
    pcre2_code_free(code);
    return NULL;
  }
  pcre2_set_match_limit(context, MS_RE_MATCH_LIMIT);
  pcre2_set_depth_limit(context, MS_RE_DEPTH_LIMIT);
  pcre2_set_heap_limit(context, MS_RE_HEAP_KIB);
  MsRegex *re = ms_alloc(sizeof *re);
  *re = (MsRegex){.code = code, .context = context, .slots = captures + 1};
  return re;
}

MsRegex *ms_re_compile(MsSpan pattern, MsStrBuild *error) {
  size_t at = 0;
  if (pattern.len > MS_RE_PATTERN_MAX) {
    refuse(error, "pattern is too long", 1);
    return NULL;
  }
  const char *why = ms_re_screen(pattern, &at);
  if (why != NULL) {
    refuse(error, why, ms_re_column(pattern, at));
    return NULL;
  }
  pcre2_general_context *general = pcre2_general_context_create(engine_alloc, engine_free, NULL);
  if (general == NULL) {
    refuse(error, "out of memory", 1);
    return NULL;
  }
  pcre2_code *code = compile_code(general, pattern, error);
  MsRegex *re = code != NULL ? wrap_code(general, code, error) : NULL;
  pcre2_general_context_free(general);
  return re;
}

void ms_re_free(MsRegex *re) {
  if (re == NULL) {
    return;
  }
  pcre2_match_context_free(re->context);
  pcre2_code_free(re->code);
  ms_free(re);
}

size_t ms_re_slots(const MsRegex *re) {
  return re->slots;
}

MsSpan ms_re_group_name(const MsRegex *re, size_t i) {
  uint32_t count = 0;
  uint32_t size = 0;
  PCRE2_SPTR table = NULL;
  pcre2_pattern_info(re->code, PCRE2_INFO_NAMECOUNT, &count);
  pcre2_pattern_info(re->code, PCRE2_INFO_NAMEENTRYSIZE, &size);
  pcre2_pattern_info(re->code, PCRE2_INFO_NAMETABLE, &table);
  for (uint32_t k = 0; k < count; k++) {
    const uint8_t *entry = table + (size_t)k * size;
    if ((size_t)(entry[0] << 8 | entry[1]) == i) {
      const uint8_t *name = entry + 2;
      size_t length = 0;
      while (name[length] != 0) {
        length++;
      }
      return ms_span_of(name, length);
    }
  }
  return ms_span_of(NULL, 0);
}

/* ---- matching ---- */

static pcre2_match_data *scratch_for(const MsRegex *re, void **cache) {
  if (cache != NULL && *cache != NULL) {
    return *cache;
  }
  pcre2_general_context *general = pcre2_general_context_create(engine_alloc, engine_free, NULL);
  pcre2_match_data *data = general != NULL ? pcre2_match_data_create(re->slots, general) : NULL;
  pcre2_general_context_free(general); /* the match data keeps its own allocator */
  if (cache != NULL) {
    *cache = data;
  }
  return data;
}

static int run(const MsRegex *re, pcre2_match_data *data, MsSpan text, size_t start) {
  const int rc =
      pcre2_match(re->code, (PCRE2_SPTR)text.ptr, text.len, start, PCRE2_NO_UTF_CHECK, data, re->context);
  if (rc >= 0) {
    return MS_RE_MATCHED;
  }
  if (rc == PCRE2_ERROR_NOMATCH) {
    return MS_RE_NOMATCH;
  }
  if (rc == PCRE2_ERROR_MATCHLIMIT || rc == PCRE2_ERROR_DEPTHLIMIT || rc == PCRE2_ERROR_HEAPLIMIT ||
      rc == PCRE2_ERROR_NOMEMORY) {
    return MS_RE_LIMIT;
  }
  return MS_RE_FAULT;
}

static void read_slots(const MsRegex *re, pcre2_match_data *data, int64_t *slots) {
  const PCRE2_SIZE *ovector = pcre2_get_ovector_pointer(data);
  for (uint32_t i = 0; i < re->slots; i++) {
    const size_t first = (size_t)i * 2;
    const bool taken = ovector[first] != PCRE2_UNSET;
    slots[first] = taken ? (int64_t)ovector[first] : -1;
    slots[first + 1] = taken ? (int64_t)ovector[first + 1] : -1;
  }
}

int ms_re_match(const MsRegex *re, MsSpan text, size_t start, int64_t *slots) {
  pcre2_match_data *data = scratch_for(re, NULL);
  if (data == NULL) {
    return MS_RE_LIMIT;
  }
  const int rc = run(re, data, text, start);
  if (rc == MS_RE_MATCHED && slots != NULL) {
    read_slots(re, data, slots);
  }
  pcre2_match_data_free(data);
  return rc;
}

void ms_re_iter_init(MsRegexIter *it) {
  *it = (MsRegexIter){.pos = 0, .prev_end = SIZE_MAX, .scratch = NULL};
}

void ms_re_iter_done(MsRegexIter *it) {
  if (it->scratch != NULL) {
    pcre2_match_data_free(it->scratch);
  }
  it->scratch = NULL;
}

/* The width of the character at `pos` (1 at the end of the text). */
static size_t character_width(MsSpan text, size_t pos) {
  size_t step = 1;
  while (pos < text.len && pos + step < text.len && ms_utf8_is_continuation(text.ptr[pos + step])) {
    step++;
  }
  return step;
}

int ms_re_next(const MsRegex *re, MsSpan text, MsRegexIter *it, int64_t *slots) {
  pcre2_match_data *data = scratch_for(re, &it->scratch);
  if (data == NULL) {
    return MS_RE_LIMIT;
  }
  while (it->pos <= text.len) {
    const int rc = run(re, data, text, it->pos);
    if (rc != MS_RE_MATCHED) {
      return rc;
    }
    const PCRE2_SIZE *ovector = pcre2_get_ovector_pointer(data);
    const size_t start = ovector[0];
    const size_t end = ovector[1];
    bool accept = true;
    if (end == it->pos) {
      accept = start != it->prev_end;
      it->pos += character_width(text, it->pos);
    } else {
      it->pos = end;
    }
    it->prev_end = end;
    if (accept) {
      if (slots != NULL) {
        read_slots(re, data, slots);
      }
      return MS_RE_MATCHED;
    }
  }
  return MS_RE_NOMATCH;
}
