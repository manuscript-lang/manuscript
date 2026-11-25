/* Lexical path rules, the one implementation for the toolchain and @std/fs (path.h): clean, join, base, dir and
 * absolute, by the host's rules. A Windows host parses volumes, UNC and drive roots and separates with `/`, except in
 * a verbatim `\\?\` path, where only the backslash separates. */
#include <string.h>

#include "base/path.h"

#ifdef _WIN32
#define HOST_RULES MS_PATH_RULES_WINDOWS
#else
#define HOST_RULES MS_PATH_RULES_UNIX
#endif

typedef enum PrefixKind { PREFIX_NONE, PREFIX_DISK, PREFIX_OTHER } PrefixKind;

/* A path split into volume prefix, root and the elements after them. */
typedef struct Parsed {
  MsPathRules rules;
  PrefixKind prefix_kind;
  size_t prefix_length;
  bool verbatim; /* \\?\ : only the backslash separates */
  bool physical_root;
  bool implicit_root; /* UNC, verbatim and device volumes are rooted by themselves */
  size_t body;        /* where the elements start */
} Parsed;

static bool ms_path_is_separator_with(MsPathRules rules, uint8_t byte) {
  return byte == '/' || (rules == MS_PATH_RULES_WINDOWS && byte == '\\');
}

static bool is_sep(const Parsed *parsed, uint8_t byte) {
  if (parsed->verbatim) {
    return byte == '\\';
  }
  return ms_path_is_separator_with(parsed->rules, byte);
}

static bool is_ascii_letter(uint8_t byte) {
  return (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z');
}

/* The end of the element starting at `at`, looking for either separator unless `verbatim`. */
static size_t element_end(MsSpan path, size_t at, bool verbatim) {
  while (at < path.len && !(path.ptr[at] == '\\' || (!verbatim && path.ptr[at] == '/'))) {
    at++;
  }
  return at;
}

/* \\?\UNC\server\share, \\?\C:, \\?\name, \\.\name and \\server\share, with the number of bytes they take. */
static void parse_windows_prefix(MsSpan path, Parsed *parsed) {
  const bool two_seps = path.len >= 2 && (path.ptr[0] == '/' || path.ptr[0] == '\\') &&
                        (path.ptr[1] == '/' || path.ptr[1] == '\\');
  if (two_seps && ms_span_starts_with_text(path, "\\\\?\\")) {
    parsed->verbatim = true;
    parsed->prefix_kind = PREFIX_OTHER;
    size_t at = 4;
    const size_t first_end = element_end(path, at, true);
    const bool unc = first_end - at == 3 && ms_span_is_text(ms_span_of(path.ptr + at, 3), "UNC");
    if (unc) {
      at = first_end < path.len ? first_end + 1 : first_end;
      const size_t server_end = element_end(path, at, true);
      at = server_end < path.len ? server_end + 1 : server_end;
      at = element_end(path, at, true);
    } else if (first_end - at == 2 && is_ascii_letter(path.ptr[at]) && path.ptr[at + 1] == ':') {
      parsed->prefix_kind = PREFIX_DISK;
      at = first_end;
    } else {
      at = first_end;
    }
    parsed->prefix_length = at;
    parsed->implicit_root = parsed->prefix_kind != PREFIX_DISK;
    return;
  }
  if (two_seps && path.len >= 4 && (path.ptr[3] == '/' || path.ptr[3] == '\\') && path.ptr[2] == '.') {
    parsed->prefix_kind = PREFIX_OTHER;
    parsed->prefix_length = element_end(path, 4, false);
    parsed->implicit_root = true;
    return;
  }
  if (two_seps) {
    size_t at = 2;
    const size_t server_end = element_end(path, at, false);
    at = server_end < path.len ? server_end + 1 : server_end;
    at = element_end(path, at, false);
    parsed->prefix_kind = PREFIX_OTHER;
    parsed->prefix_length = at;
    parsed->implicit_root = true;
    return;
  }
  if (path.len >= 2 && is_ascii_letter(path.ptr[0]) && path.ptr[1] == ':') {
    parsed->prefix_kind = PREFIX_DISK;
    parsed->prefix_length = 2;
  }
}

static Parsed parse(MsPathRules rules, MsSpan path) {
  Parsed parsed = {.rules = rules, .prefix_kind = PREFIX_NONE};
  if (rules == MS_PATH_RULES_WINDOWS) {
    parse_windows_prefix(path, &parsed);
  }
  size_t at = parsed.prefix_length;
  if (at < path.len && is_sep(&parsed, path.ptr[at])) {
    parsed.physical_root = true;
    at++;
  }
  parsed.body = at;
  return parsed;
}

static bool has_root(const Parsed *parsed) { return parsed->physical_root || parsed->implicit_root; }

static bool ms_path_is_absolute_with(MsPathRules rules, MsSpan path) {
  const Parsed parsed = parse(rules, path);
  if (rules == MS_PATH_RULES_UNIX) {
    return parsed.physical_root;
  }
  return parsed.prefix_kind != PREFIX_NONE && has_root(&parsed);
}

/* ---- elements ---- */

typedef struct Element {
  size_t start;
  size_t length;
  bool parent; /* ".." */
} Element;

/* The next element at or after *at, skipping empty ones and "."; false at the end. */
static bool next_element(const Parsed *parsed, MsSpan path, size_t *at, Element *element) {
  size_t i = *at;
  while (i < path.len) {
    while (i < path.len && is_sep(parsed, path.ptr[i])) {
      i++;
    }
    const size_t start = i;
    while (i < path.len && !is_sep(parsed, path.ptr[i])) {
      i++;
    }
    const size_t length = i - start;
    if (length == 0 || (length == 1 && path.ptr[start] == '.')) {
      continue;
    }
    *element = (Element){
        .start = start, .length = length, .parent = length == 2 && path.ptr[start] == '.' && path.ptr[start + 1] == '.'};
    *at = i;
    return true;
  }
  *at = i;
  return false;
}

/* Counts the elements, and reports the last. */
static size_t last_element(const Parsed *parsed, MsSpan path, Element *last) {
  size_t count = 0;
  size_t at = parsed->body;
  Element element = {0};
  while (next_element(parsed, path, &at, &element)) {
    *last = element;
    count++;
  }
  return count;
}

static uint8_t separator_of(const Parsed *parsed) { return parsed->verbatim ? '\\' : '/'; }

/* Appends the path without its last `drop` elements, lexically cleaned. */
static void clean_elements(MsPathRules rules, MsSpan path, size_t drop, MsStrBuild *out) {
  const Parsed parsed = parse(rules, path);
  const uint8_t sep = separator_of(&parsed);
  Element last = {0};
  const size_t total = last_element(&parsed, path, &last);
  const size_t keep = total > drop ? total - drop : 0;

  const size_t base = ms_strbuild_length(out);
  for (size_t at = 0; at < parsed.prefix_length; at++) {
    const uint8_t byte = path.ptr[at];
    ms_strbuild_append_byte(out, byte == '\\' && !parsed.verbatim ? '/' : byte);
  }
  if (parsed.physical_root) {
    ms_strbuild_append_byte(out, sep);
  }
  const size_t floor = ms_strbuild_length(out);
  size_t depth = 0;
  size_t at = parsed.body;
  Element element = {0};
  for (size_t index = 0; index < keep && next_element(&parsed, path, &at, &element); index++) {
    if (element.parent && depth > 0) {
      size_t cut = ms_strbuild_length(out);
      while (cut > floor && out->bytes.ptr[cut - 1] != sep) {
        cut--;
      }
      /* Back over the separator that precedes the element, but never into the root. */
      out->bytes.len = cut > floor ? cut - 1 : floor;
      depth--;
      continue;
    }
    if (element.parent && has_root(&parsed)) {
      continue;
    }
    const size_t length = ms_strbuild_length(out);
    const bool bare_disk = parsed.prefix_kind == PREFIX_DISK && length - base == parsed.prefix_length;
    if (length > base && out->bytes.ptr[length - 1] != sep && !bare_disk) {
      ms_strbuild_append_byte(out, sep);
    }
    ms_strbuild_append(out, ms_span_of(path.ptr + element.start, element.length));
    if (!element.parent) {
      depth++;
    }
  }
  if (ms_strbuild_length(out) == base) {
    ms_strbuild_append_byte(out, '.');
  }
}

/* The shortest equivalent path by lexical processing ("." for an empty result): repeated separators and "." go, ".."
 * undoes the element before it and vanishes above a root. Appended to `out`. */
static void ms_path_clean_with(MsPathRules rules, MsSpan path, MsStrBuild *out) { clean_elements(rules, path, 0, out); }

/* Everything but the last element, cleaned; a path without one (a root, a volume, empty) is cleaned itself. */
static void ms_path_dir_with(MsPathRules rules, MsSpan path, MsStrBuild *out) {
  const Parsed parsed = parse(rules, path);
  Element last = {0};
  const size_t total = last_element(&parsed, path, &last);
  clean_elements(rules, path, total > 0 ? 1 : 0, out);
}

/* The last element: "." for an empty path, the root or volume for a bare one. A view into `path`, or a constant. */
static MsSpan ms_path_base_with(MsPathRules rules, MsSpan path) {
  static const uint8_t separators[] = {'/', '\\'};
  static const uint8_t dot_text[] = {'.'};
  const Parsed parsed = parse(rules, path);
  Element last = {0};
  if (last_element(&parsed, path, &last) > 0) {
    return ms_span_of(path.ptr + last.start, last.length);
  }
  if (parsed.physical_root && parsed.prefix_length == 0) {
    return ms_span_of(&separators[parsed.verbatim ? 1 : 0], 1);
  }
  if (parsed.physical_root) {
    return ms_span_of(&separators[parsed.verbatim ? 1 : 0], 1);
  }
  if (parsed.prefix_length > 0) {
    return ms_span_of(path.ptr, parsed.prefix_length);
  }
  return ms_span_of(dot_text, 1);
}

/* Two elements joined and cleaned; an absolute second element replaces the first. */
static void ms_path_join_with(MsPathRules rules, MsSpan first, MsSpan second, MsStrBuild *out) {
  if (first.len == 0) {
    if (second.len != 0) {
      ms_path_clean_with(rules, second, out);
    }
    return;
  }
  if (second.len == 0) {
    ms_path_clean_with(rules, first, out);
    return;
  }
  const Parsed tail = parse(rules, second);
  const Parsed head = parse(rules, first);
  const bool same_disk = head.prefix_kind == PREFIX_DISK && tail.prefix_kind == PREFIX_DISK &&
                         head.prefix_length == 2 && (first.ptr[0] | 0x20) == (second.ptr[0] | 0x20);
  if (ms_path_is_absolute_with(rules, second) ||
      (tail.prefix_kind != PREFIX_NONE && !tail.physical_root && !same_disk)) {
    ms_path_clean_with(rules, second, out);
    return;
  }
  MsStrBuild joined = ms_strbuild_new();
  if (tail.physical_root && tail.prefix_kind == PREFIX_NONE) {
    /* "\x" keeps the volume of the first element and replaces the rest. */
    ms_strbuild_append(&joined, ms_span_of(first.ptr, head.prefix_length));
    ms_strbuild_append(&joined, second);
  } else {
    const uint8_t last = first.ptr[first.len - 1];
    const bool bare_disk = head.prefix_kind == PREFIX_DISK && first.len == head.prefix_length;
    ms_strbuild_append(&joined, first);
    if (!bare_disk && !is_sep(&head, last)) {
      ms_strbuild_append_byte(&joined, separator_of(&head));
    }
    ms_strbuild_append(&joined, ms_span_of(second.ptr + tail.prefix_length, second.len - tail.prefix_length));
  }
  ms_path_clean_with(rules, ms_strbuild_span(&joined), out);
  ms_strbuild_free(&joined);
}

/* ---- the host's rules ---- */

bool ms_path_is_separator(uint8_t byte) { return ms_path_is_separator_with(HOST_RULES, byte); }
bool ms_path_is_absolute(MsSpan path) { return ms_path_is_absolute_with(HOST_RULES, path); }
void ms_path_clean(MsStrBuild *out, MsSpan path) { ms_path_clean_with(HOST_RULES, path, out); }
void ms_path_join(MsSpan first, MsSpan second, MsStrBuild *out) {
  ms_path_join_with(HOST_RULES, first, second, out);
}
MsSpan ms_path_base(MsSpan path) { return ms_path_base_with(HOST_RULES, path); }
void ms_path_dir(MsSpan path, MsStrBuild *out) { ms_path_dir_with(HOST_RULES, path, out); }
