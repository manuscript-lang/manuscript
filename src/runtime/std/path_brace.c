/* runtime/std/path_brace.c: the brace expansion of a glob pattern (`{a,b}`, `{1..3}`) and the zeroed-array
 * helpers the glob compiler shares. */
#include "runtime/std/path_internal.h"

/* ---- memory helpers ---- */

/* A zeroed array of `count` elements of `size` bytes; NULL on overflow or failure. Owned by the caller. */
void *path_array_new(size_t count, size_t size) {
  size_t bytes = 0;
  if (!ms_size_mul(count, size, &bytes) || bytes == 0) {
    return NULL;
  }
  return ms_alloc_zeroed(bytes);
}

/* Replaces *array (capacity *capacity) with one of at least `needed` elements, keeping `count` of them.
 * False on failure, leaving the old array in place. */
MS_NODISCARD bool path_array_reserve(void **array, size_t *capacity, size_t count, size_t needed,
                                     size_t size) {
  if (needed <= *capacity) {
    return true;
  }
  size_t grown = 0;
  if (!ms_size_mul(*capacity == 0 ? 4 : *capacity, 2, &grown)) {
    return false;
  }
  grown = grown < needed ? needed : grown;
  void *fresh = path_array_new(grown, size);
  if (fresh == NULL) {
    return false;
  }
  size_t bytes = 0;
  if (count != 0 && ms_size_mul(count, size, &bytes)) {
    memcpy(fresh, *array, bytes);
  }
  ms_free(*array);
  *array = fresh;
  *capacity = grown;
  return true;
}

/* ---- text: owned byte strings for the brace expansion ---- */
void path_text_list_free(MsTextList *list) {
  for (size_t i = 0; i < list->count; i++) {
    ms_free(list->items[i].ptr);
  }
  ms_free(list->items);
  *list = (MsTextList){0};
}

/* Appends prefix + middle + suffix to the list. */
static MS_NODISCARD bool text_list_push3(MsTextList *list, MsSpan prefix, MsSpan middle, MsSpan suffix) {
  size_t length = 0;
  if (!ms_size_add(prefix.len, middle.len, &length) || !ms_size_add(length, suffix.len, &length)) {
    return false;
  }
  size_t bytes = 0;
  if (!ms_size_add(length, 1, &bytes) || !path_array_reserve((void **)&list->items, &list->capacity,
                                                             list->count, list->count + 1, sizeof(MsText))) {
    return false;
  }
  char *text = ms_alloc(bytes);
  if (text == NULL) {
    return false;
  }
  if (prefix.len != 0) {
    memcpy(text, prefix.ptr, prefix.len);
  }
  if (middle.len != 0) {
    memcpy(text + prefix.len, middle.ptr, middle.len);
  }
  if (suffix.len != 0) {
    memcpy(text + prefix.len + middle.len, suffix.ptr, suffix.len);
  }
  text[length] = '\0';
  list->items[list->count++] = (MsText){.ptr = text, .len = length};
  return true;
}

/* ---- brace expansion ---- */

MsSpan path_span_range(MsSpan bytes, size_t start, size_t end) {
  MsSpan slice = {0};
  return ms_span_slice(bytes, start, end, &slice) ? slice : (MsSpan){0};
}

/* Byte index of the first `{` outside a `[...]` class and not escaped, from `from`; SIZE_MAX when there is
 * none. */
static size_t find_open_brace(MsSpan pattern, size_t from) {
  bool escaped = false;
  bool in_class = false;
  for (size_t i = from; i < pattern.len; i++) {
    uint8_t byte = pattern.ptr[i];
    if (escaped) {
      escaped = false;
    } else if (byte == '\\') {
      escaped = true;
    } else if (byte == '[') {
      in_class = true;
    } else if (byte == ']') {
      in_class = false;
    } else if (byte == '{' && !in_class) {
      return i;
    }
  }
  return SIZE_MAX;
}

/* Index of the `}` matching the `{` at `open`; false when unbalanced. */
static bool find_close_brace(MsSpan pattern, size_t open, size_t *close) {
  size_t depth = 1;
  for (size_t i = open + 1; i < pattern.len; i++) {
    if (pattern.ptr[i] == '{') {
      depth++;
    } else if (pattern.ptr[i] == '}' && --depth == 0) {
      *close = i;
      return true;
    }
  }
  return false;
}

/* Iterates the comma separated parts of a brace group's text: `cursor` starts at 0, and each call yields the
 * next part, skipping commas inside nested braces. False after the last part. */
static bool next_part(MsSpan text, size_t *cursor, MsSpan *part) {
  if (*cursor > text.len) {
    return false;
  }
  int64_t nested = 0;
  size_t start = *cursor;
  size_t i = start;
  for (; i < text.len; i++) {
    uint8_t byte = text.ptr[i];
    if (byte == '{') {
      nested++;
    } else if (byte == '}') {
      nested--;
    } else if (byte == ',' && nested == 0) {
      break;
    }
  }
  *part = path_span_range(text, start, i);
  *cursor = i + 1;
  return true;
}

/* The fields of a range, `lo..hi` or `lo..hi..step`: at most MAX_FIELDS are kept and `count` says how many
 * exist. */
enum { MAX_FIELDS = 4 };
typedef struct MsFields {
  MsSpan items[MAX_FIELDS];
  size_t count;
} MsFields;

static void split_dots(MsSpan text, MsFields *fields) {
  size_t start = 0;
  fields->count = 0;
  for (size_t i = 0; i <= text.len; i++) {
    bool at_dots = i + 1 < text.len && text.ptr[i] == '.' && text.ptr[i + 1] == '.';
    if (i != text.len && !at_dots) {
      continue;
    }
    if (fields->count < MAX_FIELDS) {
      fields->items[fields->count] = path_span_range(text, start, i);
    }
    fields->count++;
    start = i + 2;
    i++;
  }
}

/* Go's strconv.Atoi on bytes: an optional sign, then decimal digits only, no overflow. */
static bool parse_integer(MsSpan text, int64_t *value) {
  size_t i = 0;
  bool negative = false;
  if (text.len != 0 && (text.ptr[0] == '+' || text.ptr[0] == '-')) {
    negative = text.ptr[0] == '-';
    i = 1;
  }
  if (i == text.len) {
    return false;
  }
  uint64_t magnitude = 0;
  for (; i < text.len; i++) {
    uint8_t digit = (uint8_t)(text.ptr[i] - '0');
    if (digit > 9 || magnitude > (UINT64_MAX - digit) / 10) {
      return false;
    }
    magnitude = magnitude * 10 + digit;
  }
  if (magnitude > (negative ? (uint64_t)INT64_MAX + 1 : (uint64_t)INT64_MAX)) {
    return false;
  }
  *value = negative ? (int64_t)(0 - magnitude) : (int64_t)magnitude;
  return true;
}

/* The bounds of a `{lo..hi..step}` range once parsed. */
typedef struct MsRangeSpec {
  int64_t low;
  int64_t high;
  uint64_t step; /* absolute, never 0 */
  bool alphabetic;
  size_t width; /* zero padding, 0 for none */
} MsRangeSpec;

/* Reads the endpoints of a range from its `..` separated fields (two or three). */
static bool parse_range(const MsFields *fields, MsRangeSpec *spec) {
  MsSpan first = fields->items[0];
  MsSpan second = fields->items[1];
  spec->step = 1;
  if (fields->count == 3) {
    int64_t step = 0;
    if (!parse_integer(fields->items[2], &step) || step == 0) {
      return false;
    }
    spec->step = step < 0 ? 0 - (uint64_t)step : (uint64_t)step;
  }
  if (!parse_integer(first, &spec->low) || !parse_integer(second, &spec->high)) {
    if (first.len != 1 || second.len != 1 || !ms_ascii_is_alpha(first.ptr[0]) ||
        !ms_ascii_is_alpha(second.ptr[0])) {
      return false;
    }
    spec->low = first.ptr[0];
    spec->high = second.ptr[0];
    spec->alphabetic = true;
  }
  const int64_t limit = 100000;
  if (spec->low < -limit || spec->low > limit || spec->high < -limit || spec->high > limit) {
    return false;
  }
  uint64_t span =
      spec->low > spec->high ? (uint64_t)(spec->low - spec->high) : (uint64_t)(spec->high - spec->low);
  if (span / spec->step > MAX_BRACE_RANGE) {
    return false;
  }
  for (size_t i = 0; i < 2; i++) {
    MsSpan endpoint = i == 0 ? first : second;
    size_t skip = endpoint.len != 0 && endpoint.ptr[0] == '-' ? 1 : 0;
    if (endpoint.len - skip > 1 && endpoint.ptr[skip] == '0' && endpoint.len - skip > spec->width) {
      spec->width = endpoint.len - skip;
    }
  }
  return true;
}

/* Writes element `n` of a range into `buffer` (at least 32 bytes) and returns its length. */
static size_t format_range_element(const MsRangeSpec *spec, int64_t n, char *buffer) {
  if (spec->alphabetic) {
    buffer[0] = (char)n;
    return 1;
  }
  char digits[24] = {0};
  size_t count = 0;
  uint64_t magnitude = n < 0 ? 0 - (uint64_t)n : (uint64_t)n;
  do {
    digits[count++] = (char)('0' + magnitude % 10);
    magnitude /= 10;
  } while (magnitude != 0);
  size_t length = 0;
  if (n < 0) {
    buffer[length++] = '-';
  }
  for (size_t pad = count; pad < spec->width; pad++) {
    buffer[length++] = '0';
  }
  while (count != 0) {
    buffer[length++] = digits[--count];
  }
  return length;
}

/* Expands each alternative text in turn into `out`, with `prefix` and `suffix` around it. */
static MsPathResult expand_alternative(MsSpan prefix, MsSpan middle, MsSpan suffix, size_t depth,
                                       MsTextList *out) {
  MsTextList whole = {0};
  MsTextList expanded = {0};
  MsPathResult result = PATH_NO_MEMORY;
  if (!text_list_push3(&whole, prefix, middle, suffix)) {
    goto done;
  }
  MsSpan joined = ms_span_of((const uint8_t *)whole.items[0].ptr, whole.items[0].len);
  result = path_expand_braces(joined, depth + 1, &expanded);
  if (result != PATH_OK) {
    goto done;
  }
  if (out->count + expanded.count > MAX_BRACE_RESULTS) {
    result = PATH_INVALID;
    goto done;
  }
  for (size_t i = 0; i < expanded.count; i++) {
    MsSpan item = ms_span_of((const uint8_t *)expanded.items[i].ptr, expanded.items[i].len);
    if (!text_list_push3(out, item, (MsSpan){0}, (MsSpan){0})) {
      result = PATH_NO_MEMORY;
      goto done;
    }
  }
done:
  path_text_list_free(&whole);
  path_text_list_free(&expanded);
  return result;
}

/* Expands the elements of a range group. */
static MsPathResult expand_range(MsSpan pattern, size_t open, size_t close, size_t depth, MsTextList *out) {
  MsSpan inside = path_span_range(pattern, open + 1, close);
  MsFields fields = {0};
  MsRangeSpec spec = {0};
  split_dots(inside, &fields);
  if (fields.count < 2 || fields.count > 3 || !parse_range(&fields, &spec)) {
    return PATH_INVALID;
  }
  MsSpan prefix = path_span_range(pattern, 0, open);
  MsSpan suffix = path_span_range(pattern, close + 1, pattern.len);
  int64_t n = spec.low;
  int64_t direction = spec.low > spec.high ? -1 : 1;
  for (;;) {
    char buffer[32] = {0};
    size_t length = format_range_element(&spec, n, buffer);
    MsPathResult result =
        expand_alternative(prefix, ms_span_of((const uint8_t *)buffer, length), suffix, depth, out);
    if (result != PATH_OK) {
      return result;
    }
    uint64_t remaining = direction > 0 ? (uint64_t)(spec.high - n) : (uint64_t)(n - spec.high);
    if (remaining < spec.step) {
      return PATH_OK;
    }
    n += direction * (int64_t)spec.step; /* step <= remaining <= 200000 */
  }
}

/* Expands a group with commas: one alternative per part. */
static MsPathResult expand_parts(MsSpan pattern, size_t open, size_t close, size_t depth, MsTextList *out) {
  MsSpan inside = path_span_range(pattern, open + 1, close);
  MsSpan prefix = path_span_range(pattern, 0, open);
  MsSpan suffix = path_span_range(pattern, close + 1, pattern.len);
  size_t cursor = 0;
  MsSpan part = {0};
  while (next_part(inside, &cursor, &part)) {
    MsPathResult result = expand_alternative(prefix, part, suffix, depth, out);
    if (result != PATH_OK) {
      return result;
    }
  }
  return PATH_OK;
}

static bool has_top_level_comma(MsSpan inside) {
  size_t cursor = 0;
  MsSpan part = {0};
  return next_part(inside, &cursor, &part) && cursor <= inside.len;
}

static bool contains_dots(MsSpan inside) {
  for (size_t i = 0; i + 1 < inside.len; i++) {
    if (inside.ptr[i] == '.' && inside.ptr[i + 1] == '.') {
      return true;
    }
  }
  return false;
}

/* Expands the first brace group of `pattern` that has a comma or a range, and every later one, into `out`. A
 * group with neither stays literal, and the search continues after it. */
MsPathResult path_expand_braces(MsSpan pattern, size_t depth, MsTextList *out) {
  if (depth > MAX_NESTING) {
    return PATH_INVALID;
  }
  size_t from = 0;
  for (;;) {
    size_t open = find_open_brace(pattern, from);
    if (open == SIZE_MAX) {
      return text_list_push3(out, pattern, (MsSpan){0}, (MsSpan){0}) ? PATH_OK : PATH_NO_MEMORY;
    }
    size_t close = 0;
    if (!find_close_brace(pattern, open, &close)) {
      return PATH_INVALID;
    }
    MsSpan inside = path_span_range(pattern, open + 1, close);
    if (has_top_level_comma(inside)) {
      return expand_parts(pattern, open, close, depth, out);
    }
    if (contains_dots(inside)) {
      return expand_range(pattern, open, close, depth, out);
    }
    from = close + 1;
  }
}
