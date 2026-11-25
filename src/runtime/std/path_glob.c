/* runtime/std/path_glob.c: the @std/os/path natives: a glob compiled once and matched against many values.
 *
 * Syntax: `*`, `?`, `[...]` classes, extended `@(a|b) +(..) ?(..) !(..) *(..)` groups, `{a,b}` and `{1..3}`
 * brace expansion, and `**` path segments. Patterns and values are slash separated; the Windows dialect reads
 * backslashes as slashes first. Matching keeps, per atom, the set of value positions reachable so far, so it
 * never backtracks. The compiled form is a handle that owns every allocation below it (`MsGlobCell`).
 *
 * Limits (a pattern past one is invalid): 4096 bytes, 1025 brace alternatives, 64 nested groups or brace
 * groups. A failed allocation reports MS_STATUS_FAILED and leaks nothing.
 */
#include "runtime/std/path_internal.h"

/* ---- matching: sets of reachable positions ---- */

/* The positions 0..=n a match can have reached. `words` points at `inline_words` for short values, so a set
 * is never copied; `capacity_words` 0 marks a set whose allocation failed, which holds nothing. */
typedef struct MsPositions {
  uint64_t *words; /* owned unless it is inline_words */
  size_t capacity_words;
  uint64_t inline_words[INLINE_WORDS];
} MsPositions;

/* Matching state: the value being matched, and whether any allocation failed. */
typedef struct MsMatch {
  const uint32_t *value;
  size_t length;
  bool failed;
} MsMatch;

static void positions_init(MsMatch *match, MsPositions *set, size_t n) {
  size_t words = n / 64 + 1;
  *set = (MsPositions){0};
  if (words <= INLINE_WORDS) {
    set->words = set->inline_words;
    set->capacity_words = words;
    return;
  }
  set->words = path_array_new(words, sizeof(uint64_t));
  if (set->words == NULL) {
    match->failed = true;
    return;
  }
  set->capacity_words = words;
}

static void positions_free(MsPositions *set) {
  if (set->words != set->inline_words) {
    ms_free(set->words);
  }
  set->words = NULL;
  set->capacity_words = 0;
}

static void positions_clear(MsPositions *set) {
  if (set->capacity_words != 0) {
    memset(set->words, 0, set->capacity_words * sizeof(uint64_t));
  }
}

static void positions_insert(MsPositions *set, size_t i) {
  if (i / 64 < set->capacity_words) {
    set->words[i / 64] |= (uint64_t)1 << (i % 64);
  }
}

static void positions_remove(MsPositions *set, size_t i) {
  if (i / 64 < set->capacity_words) {
    set->words[i / 64] &= ~((uint64_t)1 << (i % 64));
  }
}

static bool positions_has(const MsPositions *set, size_t i) {
  return i / 64 < set->capacity_words && ((set->words[i / 64] >> (i % 64)) & 1) == 1;
}

/* The lowest position in the set; false when it is empty. */
static bool positions_first(const MsPositions *set, size_t *first) {
  for (size_t w = 0; w < set->capacity_words; w++) {
    if (set->words[w] != 0) {
      *first = w * 64 + (size_t)__builtin_ctzll(set->words[w]);
      return true;
    }
  }
  return false;
}

static void positions_merge(MsPositions *into, const MsPositions *from) {
  for (size_t w = 0; w < into->capacity_words && w < from->capacity_words; w++) {
    into->words[w] |= from->words[w];
  }
}

/* Replaces the contents of `into` with those of `from`, which has the same capacity unless an allocation
 * failed. */
static void positions_assign(MsPositions *into, const MsPositions *from) {
  positions_clear(into);
  positions_merge(into, from);
}

static void seq_ends(MsMatch *match, const MsSeq *seq, size_t start, MsPositions *out);

static bool class_matches(const MsAtom *atom, uint32_t c) {
  bool inside = false;
  for (size_t i = 0; i < atom->range_count; i++) {
    inside = inside || (atom->ranges[i].low <= c && c <= atom->ranges[i].high);
  }
  return inside != atom->negated;
}

/* The positions after one single-character atom, from each position of `from`. */
static void step_character(const MsMatch *match, const MsAtom *atom, const MsPositions *from,
                           MsPositions *next) {
  for (size_t at = 0; at < match->length; at++) {
    if (!positions_has(from, at)) {
      continue;
    }
    uint32_t c = match->value[at];
    bool accepted = atom->kind == ATOM_ANY || (atom->kind == ATOM_LITERAL && c == atom->literal) ||
                    (atom->kind == ATOM_CLASS && class_matches(atom, c));
    if (accepted) {
      positions_insert(next, at + 1);
    }
  }
}

/* One or more repetitions of a group after `accepted`, closed under another pass of any alternative. */
static void repeat_group(MsMatch *match, const MsAtom *atom, const MsPositions *accepted, size_t at,
                         MsPositions *next) {
  size_t n = match->length;
  MsPositions seen;
  MsPositions pending;
  MsPositions reached;
  positions_init(match, &seen, n);
  positions_init(match, &pending, n);
  positions_init(match, &reached, n);
  positions_insert(&seen, at);
  for (size_t e = 0; e <= n; e++) {
    if (positions_has(accepted, e) && !positions_has(&seen, e)) {
      positions_insert(&seen, e);
      positions_insert(&pending, e);
    }
  }
  size_t position = 0;
  while (positions_first(&pending, &position)) {
    positions_remove(&pending, position);
    for (size_t a = 0; a < atom->alternative_count; a++) {
      positions_clear(&reached);
      seq_ends(match, &atom->alternatives[a], position, &reached);
      for (size_t e = 0; e <= n; e++) {
        if (!positions_has(&reached, e)) {
          continue;
        }
        positions_insert(next, e);
        if (!positions_has(&seen, e)) {
          positions_insert(&seen, e);
          positions_insert(&pending, e);
        }
      }
    }
  }
  positions_free(&seen);
  positions_free(&pending);
  positions_free(&reached);
}

/* The positions after a group atom, from each position of `from`. */
static void step_group(MsMatch *match, const MsAtom *atom, const MsPositions *from, MsPositions *next) {
  size_t n = match->length;
  MsPositions accepted;
  MsPositions reached;
  positions_init(match, &accepted, n);
  positions_init(match, &reached, n);
  for (size_t at = 0; at <= n; at++) {
    if (!positions_has(from, at)) {
      continue;
    }
    positions_clear(&accepted);
    for (size_t a = 0; a < atom->alternative_count; a++) {
      positions_clear(&reached);
      seq_ends(match, &atom->alternatives[a], at, &reached);
      positions_merge(&accepted, &reached);
    }
    if (atom->group_kind == '!') {
      for (size_t e = at; e <= n; e++) {
        if (!positions_has(&accepted, e)) {
          positions_insert(next, e);
        }
      }
      continue;
    }
    positions_merge(next, &accepted);
    if (atom->group_kind == '?' || atom->group_kind == '*') {
      positions_insert(next, at);
    }
    if (atom->group_kind == '+' || atom->group_kind == '*') {
      repeat_group(match, atom, &accepted, at, next);
    }
  }
  positions_free(&accepted);
  positions_free(&reached);
}

static void step_atom(MsMatch *match, const MsAtom *atom, const MsPositions *from, MsPositions *next) {
  size_t first = 0;
  switch (atom->kind) {
  case ATOM_STAR:
    if (positions_first(from, &first)) {
      for (size_t at = first; at <= match->length; at++) {
        positions_insert(next, at);
      }
    }
    return;
  case ATOM_GROUP:
    step_group(match, atom, from, next);
    return;
  case ATOM_ANY:
  case ATOM_CLASS:
  case ATOM_LITERAL:
    step_character(match, atom, from, next);
    return;
  }
}

/* out = the positions reachable after matching `seq` from `start`. `out` is initialised for this value. */
static void seq_ends(MsMatch *match, const MsSeq *seq, size_t start, MsPositions *out) {
  MsPositions first;
  MsPositions second;
  positions_init(match, &first, match->length);
  positions_init(match, &second, match->length);
  MsPositions *current = &first;
  MsPositions *next = &second;
  positions_insert(current, start);
  size_t any = 0;
  for (size_t i = 0; i < seq->count && positions_first(current, &any); i++) {
    positions_clear(next);
    step_atom(match, &seq->atoms[i], current, next);
    MsPositions *swap = current;
    current = next;
    next = swap;
  }
  positions_assign(out, current);
  positions_free(&first);
  positions_free(&second);
}

/* Whether `seq` matches all of the `length` characters at `value`. */
static bool matches_whole(bool *failed, const MsSeq *seq, const uint32_t *value, size_t length) {
  MsMatch match = {.value = value, .length = length, .failed = false};
  MsPositions ends;
  positions_init(&match, &ends, length);
  seq_ends(&match, seq, 0, &ends);
  bool whole = positions_has(&ends, length);
  positions_free(&ends);
  *failed = *failed || match.failed;
  return whole;
}

/* ---- compiled glob ---- */

typedef struct MsSegment {
  bool double_star; /* the segment is `**` */
  bool leading_dot; /* the segment's text starts with `.` */
  MsSeq seq;        /* owned; empty for `**` */
} MsSegment;

typedef struct MsAlternative {
  MsSegment *segments; /* owned */
  size_t count;
} MsAlternative;

typedef struct MsGlobCell {
  MsObj header; /* must be first: the runtime drops the handle through it */
  bool windows;
  MsAlternative *alternatives; /* owned */
  size_t alternative_count;
} MsGlobCell;

_Static_assert(offsetof(MsGlobCell, header) == 0,
               "the runtime reads the object header at the start of a handle");

static void alternative_free(MsAlternative *alternative) {
  for (size_t i = 0; i < alternative->count; i++) {
    path_seq_free(&alternative->segments[i].seq);
  }
  ms_free(alternative->segments);
  *alternative = (MsAlternative){0};
}

static void glob_drop(MsObj *object) {
  MsGlobCell *cell = (MsGlobCell *)object;
  for (size_t i = 0; i < cell->alternative_count; i++) {
    alternative_free(&cell->alternatives[i]);
  }
  ms_free(cell->alternatives);
  ms_free(cell);
}

/* The width of the UTF-8 sequence a lead byte starts; 1 for an ASCII or invalid lead. */
static size_t utf8_width(uint8_t lead) {
  if (lead >= 0xF0) {
    return 4;
  }
  if (lead >= 0xE0) {
    return 3;
  }
  return lead >= 0xC0 ? 2 : 1;
}

/* Decodes UTF-8 into code points (an invalid byte becomes U+FFFD). `*chars` is owned by the caller and is
 * NULL for empty text. */
static bool decode_text(MsSpan text, uint32_t **chars, size_t *count) {
  *chars = NULL;
  *count = 0;
  if (text.len == 0) {
    return true;
  }
  uint32_t *decoded = path_array_new(text.len, sizeof(uint32_t));
  if (decoded == NULL) {
    return false;
  }
  size_t n = 0;
  for (size_t i = 0; i < text.len;) {
    uint8_t lead = text.ptr[i];
    size_t width = utf8_width(lead);
    uint32_t c = width == 1 ? lead : (uint32_t)(lead & (0xFFu >> (width + 1)));
    bool valid = i + width <= text.len;
    for (size_t k = 1; valid && k < width; k++) {
      valid = ms_utf8_is_continuation(text.ptr[i + k]);
      c = (c << 6) | (uint32_t)(text.ptr[i + k] & 0x3F);
    }
    decoded[n++] = valid ? c : 0xFFFDu;
    i += valid ? width : 1;
  }
  *chars = decoded;
  *count = n;
  return true;
}

/* Parses one slash separated segment of an expanded pattern into `segment`. */
static MsPathResult parse_segment(MsSpan text, MsSegment *segment) {
  segment->double_star = text.len == 2 && text.ptr[0] == '*' && text.ptr[1] == '*';
  segment->leading_dot = text.len != 0 && text.ptr[0] == '.';
  if (segment->double_star) {
    return PATH_OK;
  }
  uint32_t *chars = NULL;
  size_t count = 0;
  if (!decode_text(text, &chars, &count)) {
    return PATH_NO_MEMORY;
  }
  MsPathResult result = path_parse_sequence((MsChars){.ptr = chars, .len = count}, 0, &segment->seq);
  ms_free(chars);
  return result;
}

/* Parses an expanded pattern (no braces left) into its segments. */
static MsPathResult parse_alternative(MsSpan text, MsAlternative *alternative) {
  size_t segments = 1;
  for (size_t i = 0; i < text.len; i++) {
    segments += text.ptr[i] == '/' ? 1 : 0;
  }
  alternative->segments = path_array_new(segments, sizeof(MsSegment));
  if (alternative->segments == NULL) {
    return PATH_NO_MEMORY;
  }
  alternative->count = segments;
  size_t start = 0;
  size_t index = 0;
  for (size_t i = 0; i <= text.len; i++) {
    if (i != text.len && text.ptr[i] != '/') {
      continue;
    }
    MsPathResult result = parse_segment(path_span_range(text, start, i), &alternative->segments[index++]);
    if (result != PATH_OK) {
      return result;
    }
    start = i + 1;
  }
  return PATH_OK;
}

/* Fills the cell from `pattern`, with backslashes already read as slashes where the dialect says so. */
static MsPathResult glob_fill(MsGlobCell *cell, MsSpan pattern) {
  MsTextList expanded = {0};
  MsPathResult result = path_expand_braces(pattern, 0, &expanded);
  if (result == PATH_OK) {
    cell->alternatives = path_array_new(expanded.count, sizeof(MsAlternative));
    result = cell->alternatives == NULL ? PATH_NO_MEMORY : PATH_OK;
  }
  for (size_t i = 0; result == PATH_OK && i < expanded.count; i++) {
    cell->alternative_count = i + 1;
    MsSpan text = ms_span_of((const uint8_t *)expanded.items[i].ptr, expanded.items[i].len);
    result = parse_alternative(text, &cell->alternatives[i]);
  }
  path_text_list_free(&expanded);
  return result;
}

/* A copy of `text` with each backslash a slash when `windows`, plus a NUL; NULL when out of memory. */
static char *slash_copy(MsSpan text, bool windows) {
  size_t bytes = 0;
  if (!ms_size_add(text.len, 1, &bytes)) {
    return NULL;
  }
  char *copy = ms_alloc(bytes);
  if (copy == NULL) {
    return NULL;
  }
  for (size_t i = 0; i < text.len; i++) {
    char c = (char)text.ptr[i];
    if (windows && c == '\\') {
      c = (char)'/';
    }
    copy[i] = c;
  }
  copy[text.len] = '\0';
  return copy;
}

static uint8_t status_of(MsPathResult result) {
  return result == PATH_INVALID ? MS_STATUS_INVALID_INPUT : MS_STATUS_FAILED;
}

uint8_t msstd_path_host_windows(void) {
#ifdef _WIN32
  return 1;
#else
  return 0;
#endif
}

uint8_t msstd_path_compile_glob(uint8_t windows, const MsString *pattern, MsObj **out) {
  MsSpan text = ms_string_span(pattern);
  if (text.len > MAX_PATTERN_BYTES || ms_span_has_byte(text, 0)) {
    return MS_STATUS_INVALID_INPUT;
  }
  char *slashed = slash_copy(text, windows != 0);
  MsGlobCell *cell = ms_alloc_zeroed(sizeof *cell);
  MsPathResult result = PATH_NO_MEMORY;
  if (slashed != NULL && cell != NULL) {
    cell->header.drop = glob_drop;
    cell->windows = windows != 0;
    result = glob_fill(cell, ms_span_of((const uint8_t *)slashed, text.len));
  }
  ms_free(slashed);
  if (result != PATH_OK) {
    if (cell != NULL) {
      glob_drop(&cell->header);
    }
    return status_of(result);
  }
  *out = &cell->header;
  return MS_STATUS_OK;
}

/* ---- matching a value ---- */

/* The characters of a value and where each slash separated part starts and ends. */
typedef struct MsParts {
  uint32_t *chars; /* owned */
  size_t *starts;  /* owned, `count` entries */
  size_t *ends;    /* owned, `count` entries */
  size_t count;
} MsParts;

static void parts_free(MsParts *parts) {
  ms_free(parts->chars);
  ms_free(parts->starts);
  ms_free(parts->ends);
  *parts = (MsParts){0};
}

/* Splits `text` (already slashed) into parts of characters. */
static bool parts_split(MsSpan text, MsParts *parts) {
  size_t count = 1;
  for (size_t i = 0; i < text.len; i++) {
    count += text.ptr[i] == '/' ? 1 : 0;
  }
  size_t chars = 0;
  if (!decode_text(text, &parts->chars, &chars)) {
    return false;
  }
  parts->starts = path_array_new(count, sizeof(size_t));
  parts->ends = path_array_new(count, sizeof(size_t));
  if (parts->starts == NULL || parts->ends == NULL) {
    return false;
  }
  parts->count = count;
  size_t part = 0;
  size_t start = 0;
  for (size_t i = 0; i < chars; i++) {
    if (parts->chars[i] == '/') {
      parts->starts[part] = start;
      parts->ends[part++] = i;
      start = i + 1;
    }
  }
  parts->starts[part] = start;
  parts->ends[part] = chars;
  return true;
}

/* Whether part j (1-based) is non-empty and starts with a dot, which `*` and `**` do not match. */
static bool part_is_dotted(const MsParts *parts, size_t j) {
  size_t start = parts->starts[j - 1];
  return start < parts->ends[j - 1] && parts->chars[start] == '.';
}

/* Positions 0..=n of `next` after one segment, given those of `previous`. */
static void step_segment(bool *failed, const MsParts *parts, const MsSegment *segment,
                         const MsPositions *previous, MsPositions *next) {
  size_t n = parts->count;
  if (segment->double_star) {
    if (positions_has(previous, 0)) {
      positions_insert(next, 0);
    }
    for (size_t j = 1; j <= n; j++) {
      if (positions_has(previous, j) || (positions_has(next, j - 1) && !part_is_dotted(parts, j))) {
        positions_insert(next, j);
      }
    }
    return;
  }
  for (size_t j = 1; j <= n; j++) {
    bool open = positions_has(previous, j - 1) && (!part_is_dotted(parts, j) || segment->leading_dot);
    size_t from = parts->starts[j - 1];
    if (open && matches_whole(failed, &segment->seq, parts->chars + from, parts->ends[j - 1] - from)) {
      positions_insert(next, j);
    }
  }
}

/* Whether the parts match one expanded alternative of the pattern. */
static bool match_alternative(bool *failed, const MsParts *parts, const MsAlternative *alternative) {
  MsMatch scratch = {.value = NULL, .length = 0, .failed = false};
  MsPositions first;
  MsPositions second;
  positions_init(&scratch, &first, parts->count);
  positions_init(&scratch, &second, parts->count);
  MsPositions *previous = &first;
  MsPositions *next = &second;
  positions_insert(previous, 0);
  for (size_t i = 0; i < alternative->count; i++) {
    positions_clear(next);
    step_segment(failed, parts, &alternative->segments[i], previous, next);
    MsPositions *swap = previous;
    previous = next;
    next = swap;
  }
  bool whole = positions_has(previous, parts->count);
  positions_free(&first);
  positions_free(&second);
  *failed = *failed || scratch.failed;
  return whole;
}

uint8_t msstd_path_glob_matches(const MsObj *glob, const MsString *value, uint8_t *out) {
  const MsGlobCell *cell = (const MsGlobCell *)glob;
  MsSpan text = ms_string_span(value);
  if (ms_span_has_byte(text, 0)) {
    return MS_STATUS_INVALID_INPUT;
  }
  char *slashed = slash_copy(text, cell->windows);
  MsParts parts = {0};
  bool failed = slashed == NULL || !parts_split(ms_span_of((const uint8_t *)slashed, text.len), &parts);
  bool matched = false;
  for (size_t i = 0; !failed && !matched && i < cell->alternative_count; i++) {
    matched = match_alternative(&failed, &parts, &cell->alternatives[i]);
  }
  parts_free(&parts);
  ms_free(slashed);
  if (failed) {
    return MS_STATUS_FAILED;
  }
  *out = matched ? 1 : 0;
  return MS_STATUS_OK;
}
