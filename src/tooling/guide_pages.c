/* Owns the page and search half of guide.h: bounded standard-library pages and the fuzzy lookup behind `ms search_symbol`. */
#include "base/message.h"
#include "base/utf8.h"
#include "base/sort.h"
#include "base/strbuild.h"
#include "tooling/guide.h"

enum { PAGE_BUDGET = 3500, LINE_WIDTH = 150, MODULE_LINES = 45, INDEX_BUDGET = 3400, SEARCH_BUDGET = 3000 };

/* ---- text helpers ---- */

static bool is_blank(uint8_t c) {
  return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}

static MsSpan sub(MsSpan s, size_t from, size_t to) {
  return ms_span_of(s.ptr + from, to - from);
}

static MsSpan trim(MsSpan s) {
  size_t from = 0;
  size_t to = s.len;
  while (from < to && is_blank(s.ptr[from])) {
    from++;
  }
  while (to > from && is_blank(s.ptr[to - 1])) {
    to--;
  }
  return sub(s, from, to);
}

/* The words of `s` joined by one space. */
static MsSpan one_spaced(MsArena *arena, MsSpan s) {
  MsStrBuild out = ms_strbuild_new();
  size_t i = 0;
  bool first = true;
  while (i < s.len) {
    while (i < s.len && is_blank(s.ptr[i])) {
      i++;
    }
    size_t j = i;
    while (j < s.len && !is_blank(s.ptr[j])) {
      j++;
    }
    if (j > i) {
      ms_strbuild_append_text(&out, first ? "" : " ");
      ms_strbuild_append(&out, sub(s, i, j));
      first = false;
    }
    i = j;
  }
  const MsSpan text = ms_arena_copy(arena, ms_strbuild_span(&out));
  ms_strbuild_free(&out);
  return text;
}

static MsSpan copy_of(MsArena *arena, MsStrBuild *b) {
  const MsSpan text = ms_arena_copy(arena, ms_strbuild_span(b));
  ms_strbuild_free(b);
  return text;
}

static MsSpan short_name(MsSpan path) {
  if (ms_span_starts_with(path, ms_span_of_text("@std/"))) {
    path = sub(path, 5, path.len);
  }
  if (ms_span_ends_with(path, ms_span_of_text(".ms"))) {
    path = sub(path, 0, path.len - 3);
  }
  for (size_t i = path.len; i > 0; i--) {
    if (path.ptr[i - 1] == '/') {
      return sub(path, i, path.len);
    }
  }
  return path;
}

static MsSpan package_name(MsSpan path) {
  if (ms_span_starts_with(path, ms_span_of_text("@std/"))) {
    path = sub(path, 5, path.len);
  }
  return ms_span_ends_with(path, ms_span_of_text(".ms")) ? sub(path, 0, path.len - 3) : path;
}

/* Drops a generic parameter list: `group_by[K: Hashable]` becomes `group_by`. */
static MsSpan bare(MsSpan name) {
  for (size_t i = 0; i < name.len; i++) {
    if (name.ptr[i] == '[') {
      return sub(name, 0, i);
    }
  }
  return name;
}

static MsSpan std_path(MsArena *arena, MsSpan module, MsSpan name) {
  return ms_message_format(arena, "%S.%S", short_name(module), bare(name));
}

/* The first non-empty line of a doc, cut at a word boundary. */
static MsSpan first_line(MsArena *arena, MsSpan doc, size_t limit) {
  size_t at = 0;
  while (at <= doc.len) {
    size_t end = at;
    while (end < doc.len && doc.ptr[end] != '\n') {
      end++;
    }
    const MsSpan line = one_spaced(arena, sub(doc, at, end));
    at = end + 1;
    if (line.len == 0) {
      continue;
    }
    const size_t chars = ms_utf8_count(line.ptr, line.len);
    if (chars <= limit) {
      return line;
    }
    const MsSpan head = sub(line, 0, ms_utf8_offset_of(line.ptr, line.len, limit - 1));
    long cut = -1;
    for (size_t i = head.len; i > 0; i--) {
      if (head.ptr[i - 1] == ' ') {
        cut = (long)(i - 1);
        break;
      }
    }
    if (cut < (long)(limit / 2)) {
      cut = (long)limit - 1;
    }
    size_t take = (size_t)cut < chars ? (size_t)cut : chars;
    MsStrBuild out = ms_strbuild_new();
    ms_strbuild_append(&out, sub(line, 0, ms_utf8_offset_of(line.ptr, line.len, take)));
    ms_strbuild_append_text(&out, "\xE2\x80\xA6");
    return copy_of(arena, &out);
  }
  return ms_span_of_text("");
}

/* Collapses a signature to one line of at most `limit` characters. */
static MsSpan one_line(MsArena *arena, MsSpan text, size_t limit) {
  MsSpan joined = one_spaced(arena, text);
  if (joined.len > 0 && joined.ptr[joined.len - 1] == ':') {
    joined = sub(joined, 0, joined.len - 1);
  }
  joined = trim(joined);
  if (ms_utf8_count(joined.ptr, joined.len) > limit) {
    MsStrBuild out = ms_strbuild_new();
    ms_strbuild_append(&out, sub(joined, 0, ms_utf8_offset_of(joined.ptr, joined.len, limit - 1)));
    ms_strbuild_append_text(&out, "\xE2\x80\xA6");
    return copy_of(arena, &out);
  }
  return joined;
}

/* Limits a full doc to `limit` bytes without cutting a character. */
static MsSpan cap_doc(MsArena *arena, MsSpan doc, size_t limit) {
  doc = trim(doc);
  if (doc.len <= limit) {
    return doc;
  }
  size_t chars = ms_utf8_count(doc.ptr, doc.len);
  size_t bytes = doc.len;
  while (bytes > limit) {
    chars = chars > 20 ? chars - 20 : 0;
    bytes = ms_utf8_offset_of(doc.ptr, doc.len, chars);
  }
  MsStrBuild out = ms_strbuild_new();
  ms_strbuild_append(&out, sub(doc, 0, bytes));
  ms_strbuild_append_text(&out, "\xE2\x80\xA6");
  return copy_of(arena, &out);
}

/* The text with lines beyond `limit` replaced by `...`. */
static MsSpan clip_lines(MsArena *arena, MsSpan text, size_t limit) {
  size_t lines = 1;
  for (size_t i = 0; i < text.len; i++) {
    lines += text.ptr[i] == '\n' ? 1 : 0;
  }
  if (lines <= limit) {
    return text;
  }
  size_t seen = 0;
  size_t cut = 0;
  for (size_t i = 0; i < text.len; i++) {
    if (text.ptr[i] == '\n' && ++seen == limit) {
      cut = i;
      break;
    }
  }
  return ms_message_format(arena, "%S\n...", sub(text, 0, cut), (MsSpan){0});
}

/* Appends `s` with every invalid UTF-8 sequence replaced by U+FFFD, as Rust's lossy conversion does. */
static void append_lossy(MsStrBuild *out, MsSpan s) {
  size_t i = 0;
  while (i < s.len) {
    const uint8_t c = s.ptr[i];
    size_t need = c < 0x80 ? 1 : (c >= 0xC2 && c <= 0xDF) ? 2 : (c >= 0xE0 && c <= 0xEF) ? 3 : (c >= 0xF0 && c <= 0xF4) ? 4 : 0;
    if (need == 0) {
      ms_strbuild_append_text(out, "\xEF\xBF\xBD");
      i++;
      continue;
    }
    size_t k = 1;
    while (k < need && i + k < s.len && (s.ptr[i + k] & 0xC0) == 0x80) {
      k++;
    }
    if (k < need) {
      ms_strbuild_append_text(out, "\xEF\xBF\xBD");
      i += k;
      continue;
    }
    ms_strbuild_append(out, sub(s, i, i + need));
    i += need;
  }
}

/* Keeps the head and tail of long text, where errors and summaries usually sit. */
static MsSpan clip_text(MsArena *arena, MsSpan s, size_t limit) {
  if (s.len <= limit) {
    return s;
  }
  const size_t room = limit > 48 ? limit - 48 : 0;
  const size_t head = room * 2 / 3;
  const size_t tail = room / 3;
  MsStrBuild out = ms_strbuild_new();
  append_lossy(&out, sub(s, 0, head));
  ms_strbuild_append(&out, ms_message_format(arena, "\n[... %z bytes omitted ...]\n", s.len - head - tail));
  append_lossy(&out, sub(s, s.len - tail, s.len));
  return copy_of(arena, &out);
}

/* ---- the index and pages ---- */

static void pad_to(MsStrBuild *out, MsSpan text, size_t width) {
  ms_strbuild_append(out, text);
  for (size_t n = ms_utf8_count(text.ptr, text.len); n < width; n++) {
    ms_strbuild_append_byte(out, ' ');
  }
}

static MsSpan index_lines(MsArena *arena, const MsGuide *guide, size_t width) {
  MsStrBuild b = ms_strbuild_new();
  for (size_t m = 0; m < guide->count; m++) {
    const MsApiModule *module = &guide->modules[m];
    MsStrBuild line = ms_strbuild_new();
    pad_to(&line, short_name(module->path), 12);
    size_t shown = 0;
    for (size_t d = 0; d < module->decls.len; d++) {
      const MsSpan name = module->decls.ptr[d].name;
      if (ms_strbuild_length(&line) + 2 + name.len > width && shown > 0) {
        break;
      }
      ms_strbuild_append_byte(&line, ' ');
      ms_strbuild_append(&line, name);
      ms_strbuild_append_byte(&line, ',');
      shown++;
    }
    if (line.bytes.len > 0 && line.bytes.ptr[line.bytes.len - 1] == ',') {
      line.bytes.len--;
    }
    const size_t rest = module->decls.len - shown;
    if (rest > 0) {
      ms_strbuild_append(&line, ms_message_format(arena, " +%z", rest));
    }
    ms_strbuild_append(&b, ms_strbuild_span(&line));
    ms_strbuild_append_byte(&b, '\n');
    ms_strbuild_free(&line);
  }
  return copy_of(arena, &b);
}

MsSpan ms_guide_index(MsArena *arena, const MsGuide *guide) {
  const MsSpan header = ms_span_of_text(
      "Standard modules (prelude needs no import).\n`ms search_symbol <module>` lists one, `ms search_symbol "
      "<module>.<Name>` shows a declaration, `ms search_symbol <words>` searches.\n\n");
  size_t width = 84;
  for (;;) {
    const MsSpan body = index_lines(arena, guide, width);
    if (header.len + body.len <= INDEX_BUDGET || width <= 24) {
      return ms_message_format(arena, "%S%S", header, body);
    }
    width -= 4;
  }
}

static MsSpan import_line(MsArena *arena, const MsApiModule *m) {
  if (ms_span_is_text(m->path, "prelude")) {
    return ms_span_of_text("available in every module; no import");
  }
  return ms_message_format(arena, "import Name from \"%S\"", m->path, (MsSpan){0});
}

static MsSpan module_page(MsArena *arena, const MsApiModule *m) {
  MsStrBuild b = ms_strbuild_new();
  ms_strbuild_append(&b, ms_message_format(arena, "%S: %S\n", m->path, import_line(arena, m)));
  for (size_t i = 0; i < m->decls.len; i++) {
    const MsApiDecl *d = &m->decls.ptr[i];
    if (i == MODULE_LINES) {
      ms_strbuild_append(&b, ms_message_format(arena, "... %z more; narrow with `ms search_symbol <words>`\n", m->decls.len - MODULE_LINES));
      break;
    }
    if (ms_span_is_text(d->kind, "fn") && d->declaration.len > 0) {
      ms_strbuild_append(&b, one_line(arena, d->declaration, LINE_WIDTH));
      ms_strbuild_append_byte(&b, '\n');
      continue;
    }
    ms_strbuild_append_text(&b, d->opaque ? "opaque " : "");
    ms_strbuild_append(&b, d->kind);
    ms_strbuild_append_byte(&b, ' ');
    ms_strbuild_append(&b, bare(d->name));
    const MsSpan doc = first_line(arena, d->doc, 90);
    if (doc.len > 0) {
      ms_strbuild_append(&b, ms_message_format(arena, " // %S", doc, (MsSpan){0}));
    }
    ms_strbuild_append_byte(&b, '\n');
  }
  ms_strbuild_append(&b, ms_message_format(arena, "Details: ms search_symbol %S.<Name>\n", short_name(m->path), (MsSpan){0}));
  return clip_text(arena, copy_of(arena, &b), PAGE_BUDGET);
}

static MsSpan trim_newlines_end(MsSpan s) {
  while (s.len > 0 && s.ptr[s.len - 1] == '\n') {
    s.len--;
  }
  return s;
}

static MsSpan declaration_page(MsArena *arena, const MsApiModule *m, const MsApiDecl *d) {
  MsStrBuild b = ms_strbuild_new();
  ms_strbuild_append_text(&b, d->opaque ? "opaque " : "");
  ms_strbuild_append(&b, ms_message_format(arena, "%S %S (%S)\n", d->kind, d->name, m->path));
  if (!ms_span_is_text(m->path, "prelude")) {
    ms_strbuild_append(&b, ms_message_format(arena, "import %S from \"%S\"\n", bare(d->name), m->path));
  }
  const MsSpan doc = cap_doc(arena, d->doc, 500);
  if (doc.len > 0) {
    ms_strbuild_append(&b, doc);
    ms_strbuild_append_byte(&b, '\n');
  }
  if (d->members.len == 0) {
    if (d->declaration.len > 0) {
      ms_strbuild_append(&b, clip_lines(arena, trim_newlines_end(d->declaration), 12));
      ms_strbuild_append_byte(&b, '\n');
    }
    return clip_text(arena, copy_of(arena, &b), PAGE_BUDGET);
  }
  ms_strbuild_append(&b, ms_message_format(arena, "members (%z):\n", d->members.len));
  for (size_t i = 0; i < d->members.len; i++) {
    const MsSpan line = ms_message_format(arena, "  %S\n", one_line(arena, d->members.ptr[i].signature, LINE_WIDTH));
    if (ms_strbuild_length(&b) + line.len > PAGE_BUDGET - 160) {
      ms_strbuild_append(&b, ms_message_format(arena, "  ... %z more; use `ms search_symbol %S.%S.<member>`\n",
                                               d->members.len - i, short_name(m->path), bare(d->name)));
      break;
    }
    ms_strbuild_append(&b, line);
  }
  ms_strbuild_append(&b, ms_message_format(arena, "Details: ms search_symbol %S.%S.<member>\n", short_name(m->path), bare(d->name)));
  return copy_of(arena, &b);
}

static bool member_page(MsArena *arena, const MsApiModule *m, const MsApiDecl *d, MsSpan name, MsSpan *page, MsSpan *error) {
  MsStrBuild b = ms_strbuild_new();
  size_t count = 0;
  for (size_t i = 0; i < d->members.len; i++) {
    const MsApiMember *member = &d->members.ptr[i];
    if (!ms_span_equal(bare(member->name), name)) {
      continue;
    }
    if (++count > 3) {
      break;
    }
    ms_strbuild_append(&b, ms_message_format(arena, "%S.%S (%S)\n%S\n", d->name, member->name, m->path,
                                             clip_lines(arena, trim_newlines_end(member->signature), 6)));
    const MsSpan doc = cap_doc(arena, member->doc, 800);
    if (doc.len > 0) {
      ms_strbuild_append(&b, doc);
      ms_strbuild_append_byte(&b, '\n');
    }
  }
  if (count == 0) {
    ms_strbuild_free(&b);
    *error = ms_message_format(arena, "%S has no member \"%S\"; see `ms search_symbol %S.%S`", d->name, name, short_name(m->path),
                               bare(d->name));
    return false;
  }
  *page = clip_text(arena, copy_of(arena, &b), PAGE_BUDGET);
  return true;
}

/* The dot-separated parts of a path, at most three; a leading `@std/` and `.ms` are accepted. */
static size_t split_path(MsArena *arena, MsSpan path, MsSpan parts[3]) {
  path = trim(path);
  if (ms_span_starts_with(path, ms_span_of_text("@std/"))) {
    path = sub(path, 5, path.len);
    size_t at = 0;
    if (ms_span_find(path, ms_span_of_text(".ms"), &at)) {
      /* `data/json.ms.parse` reads as `data/json.parse` */
      path = ms_message_format(arena, "%S%S", sub(path, 0, at), sub(path, at + 3, path.len));
    }
  }
  size_t count = 0;
  size_t from = 0;
  for (size_t i = 0; i <= path.len; i++) {
    if (i == path.len || (path.ptr[i] == '.' && count < 2)) {
      parts[count++] = sub(path, from, i);
      from = i + 1;
    }
  }
  return count;
}

static const MsApiModule *find_module(const MsGuide *guide, MsSpan name) {
  for (size_t i = 0; i < guide->count; i++) {
    if (ms_span_equal(short_name(guide->modules[i].path), name) || ms_span_equal(package_name(guide->modules[i].path), name)) {
      return &guide->modules[i];
    }
  }
  return NULL;
}

bool ms_guide_page(MsArena *arena, const MsGuide *guide, MsSpan path, MsSpan *page, MsSpan *error) {
  MsSpan parts[3] = {0};
  const size_t count = split_path(arena, path, parts);
  const MsApiModule *module = find_module(guide, parts[0]);
  if (module == NULL) {
    MsStrBuild names = ms_strbuild_new();
    for (size_t i = 0; i < guide->count; i++) {
      ms_strbuild_append_text(&names, i > 0 ? ", " : "");
      ms_strbuild_append(&names, short_name(guide->modules[i].path));
    }
    *error = ms_message_format(arena, "no standard module \"%S\"; modules: %S", parts[0], copy_of(arena, &names));
    return false;
  }
  if (count == 1) {
    *page = module_page(arena, module);
    return true;
  }
  const MsApiDecl *found = NULL;
  for (size_t i = 0; i < module->decls.len && found == NULL; i++) {
    found = ms_span_equal(bare(module->decls.ptr[i].name), parts[1]) ? &module->decls.ptr[i] : NULL;
  }
  if (found == NULL) {
    *error = ms_message_format(arena, "%S has no declaration \"%S\"; see `ms search_symbol %S` (or `ms search_symbol %S`)",
                               short_name(module->path), parts[1], short_name(module->path), parts[1]);
    return false;
  }
  if (count == 2) {
    *page = declaration_page(arena, module, found);
    return true;
  }
  return member_page(arena, module, found, parts[2], page, error);
}

/* ---- search ---- */

typedef struct Entry {
  MsSpan module, name, kind, signature, doc;
  const MsSpans *effects;
  MsSpans words, doc_words, module_words;
} Entry;
MS_AVEC(Entries, entries, Entry)

static bool is_word_scalar(uint32_t c) {
  if (c < 0x80) {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
  }
  return !((c >= 0x2000 && c <= 0x2BFF) || (c >= 0x3000 && c <= 0x303F));
}

/* Lowercases text and splits on punctuation, underscores and camelCase. */
static MsSpans split_words(MsArena *arena, MsSpan s) {
  MsSpans words = {0};
  MsStrBuild current = ms_strbuild_new();
  uint8_t previous = 0;
  for (size_t i = 0; i < s.len; i++) {
    const uint8_t c = s.ptr[i];
    const bool word = c >= 0x80 ? is_word_scalar(0x80) : is_word_scalar(c);
    if (word) {
      const bool upper = c >= 'A' && c <= 'Z';
      const bool prev_lower = previous >= 'a' && previous <= 'z';
      if (upper && i > 0 && prev_lower && current.bytes.len > 0) {
        ms_spans_push(arena, &words, copy_of(arena, &current));
        current = ms_strbuild_new();
      }
      ms_strbuild_append_byte(&current, upper ? (uint8_t)(c + 32) : c);
    } else if (current.bytes.len > 0) {
      ms_spans_push(arena, &words, copy_of(arena, &current));
      current = ms_strbuild_new();
    }
    previous = c;
  }
  if (current.bytes.len > 0) {
    ms_spans_push(arena, &words, copy_of(arena, &current));
  }
  ms_strbuild_free(&current);
  return words;
}

/* Keeps the leading paragraph and at most 3 lines, so a native type with dozens of members cannot flood a result. */
static MsSpan first_block(MsArena *arena, MsSpan s) {
  size_t at = 0;
  if (ms_span_find(s, ms_span_of_text("\n\n"), &at)) {
    s = sub(s, 0, at);
  }
  s = trim_newlines_end(s);
  size_t lines = 1;
  for (size_t i = 0; i < s.len; i++) {
    lines += s.ptr[i] == '\n' ? 1 : 0;
  }
  if (lines <= 3) {
    return s;
  }
  size_t seen = 0;
  size_t cut = 0;
  for (size_t i = 0; i < s.len; i++) {
    if (s.ptr[i] == '\n' && ++seen == 3) {
      cut = i;
      break;
    }
  }
  return ms_message_format(arena, "%S\n    ...", sub(s, 0, cut), (MsSpan){0});
}

static Entry new_entry(MsArena *arena, MsSpan path, MsSpan short_module, MsSpan name, MsSpan kind, MsSpan signature, MsSpan doc) {
  return (Entry){.module = path, .name = name, .kind = kind, .signature = signature, .doc = doc,
                 .words = split_words(arena, name), .doc_words = split_words(arena, doc),
                 .module_words = split_words(arena, short_module)};
}

static Entries standard_index(MsArena *arena, const MsGuide *guide) {
  Entries index = {0};
  for (size_t m = 0; m < guide->count; m++) {
    const MsApiModule *module = &guide->modules[m];
    const MsSpan short_module = short_name(module->path);
    for (size_t i = 0; i < module->decls.len; i++) {
      const MsApiDecl *d = &module->decls.ptr[i];
      Entry entry = new_entry(arena, module->path, short_module, d->name, d->kind, first_block(arena, trim(d->declaration)), d->doc);
      entry.effects = &d->effects;
      entries_push(arena, &index, entry);
      for (size_t k = 0; k < d->members.len; k++) {
        const MsApiMember *member = &d->members.ptr[k];
        entries_push(arena, &index,
                     new_entry(arena, module->path, short_module, ms_message_format(arena, "%S.%S", d->name, member->name),
                               member->kind, member->signature, member->doc));
      }
    }
  }
  return index;
}

static bool stop_word(MsSpan w) {
  static const char *const STOP[] = {"a", "an", "the", "of", "to", "in", "for", "with", "by", "from", "and", "or", "how", "do"};
  for (size_t i = 0; i < sizeof STOP / sizeof STOP[0]; i++) {
    if (ms_span_is_text(w, STOP[i])) {
      return true;
    }
  }
  return false;
}

/* Drops filler so "sort by key" matches on "sort" and "key". */
static MsSpans significant_words(MsArena *arena, MsSpan query) {
  const MsSpans all = split_words(arena, query);
  MsSpans kept = {0};
  for (size_t i = 0; i < all.len; i++) {
    if (!stop_word(all.ptr[i]) && !ms_span_is_text(all.ptr[i], "i")) {
      ms_spans_push(arena, &kept, all.ptr[i]);
    }
  }
  return kept.len == 0 ? all : kept;
}

static bool is_subsequence(MsSpan small, MsSpan large) {
  size_t i = 0;
  for (size_t k = 0; k < large.len; k++) {
    if (i < small.len && small.ptr[i] == large.ptr[k]) {
      i++;
    }
  }
  return i == small.len;
}

/* The Damerau-Levenshtein distance with adjacent transpositions. */
static size_t edit_distance(MsArena *arena, MsSpan a, MsSpan b) {
  const size_t diff = a.len > b.len ? a.len - b.len : b.len - a.len;
  if (diff > 2) {
    return 3;
  }
  const size_t cols = b.len + 1;
  size_t *d = MS_ARENA_NEW_ARRAY(arena, size_t, (a.len + 1) * cols);
  for (size_t i = 0; i <= a.len; i++) {
    d[i * cols] = i;
  }
  for (size_t j = 0; j <= b.len; j++) {
    d[j] = j;
  }
  for (size_t i = 1; i <= a.len; i++) {
    for (size_t j = 1; j <= b.len; j++) {
      const size_t cost = a.ptr[i - 1] != b.ptr[j - 1] ? 1 : 0;
      size_t best = d[(i - 1) * cols + j] + 1;
      const size_t insert = d[i * cols + j - 1] + 1;
      const size_t replace = d[(i - 1) * cols + j - 1] + cost;
      best = insert < best ? insert : best;
      best = replace < best ? replace : best;
      if (i > 1 && j > 1 && a.ptr[i - 1] == b.ptr[j - 2] && a.ptr[i - 2] == b.ptr[j - 1]) {
        const size_t swap = d[(i - 2) * cols + j - 2] + 1;
        best = swap < best ? swap : best;
      }
      d[i * cols + j] = best;
    }
  }
  return d[a.len * cols + b.len];
}

/* Scores one query word against a candidate word; `weight` scales the field. */
static int64_t score_word(MsArena *arena, MsSpan token, MsSpan word, int64_t weight) {
  if (ms_span_equal(token, word)) {
    return weight;
  }
  if (ms_span_starts_with(word, token) && token.len >= 2) {
    return weight * 7 / 10;
  }
  size_t at = 0;
  if (token.len >= 3 && ms_span_find(word, token, &at)) {
    return weight / 2;
  }
  if (weight < 50) {
    return 0; /* prose matches must be exact words or prefixes */
  }
  if (token.len >= 3 && word.len > 0 && token.ptr[0] == word.ptr[0] && is_subsequence(token, word)) {
    return weight * 3 / 10;
  }
  if (token.len >= 5 && edit_distance(arena, token, word) <= (token.len >= 7 ? 2u : 1u)) {
    return weight * 4 / 10;
  }
  return 0;
}

static int64_t score_words(MsArena *arena, MsSpan token, const Entry *e) {
  int64_t best = 0;
  for (size_t i = 0; i < e->words.len; i++) {
    const int64_t s = score_word(arena, token, e->words.ptr[i], 100);
    best = s > best ? s : best;
  }
  for (size_t i = 0; i < e->module_words.len; i++) {
    const int64_t s = score_word(arena, token, e->module_words.ptr[i], 60);
    best = s > best ? s : best;
  }
  if (token.len >= 4) {
    for (size_t i = 0; i < e->doc_words.len; i++) {
      const int64_t s = score_word(arena, token, e->doc_words.ptr[i], 12);
      best = s > best ? s : best;
    }
  }
  return best;
}

static int64_t score_token(MsArena *arena, MsSpan token, const Entry *e) {
  static const struct {
    const char *word;
    const char *alias[2];
  } SYNONYMS[] = {{"sort", {"sorted", NULL}},   {"order", {"sorted", NULL}},   {"uppercase", {"upper", NULL}},
                  {"lowercase", {"lower", NULL}}, {"size", {"length", "count"}}, {"len", {"length", NULL}},
                  {"delete", {"remove", NULL}},   {"push", {"append", NULL}},    {"print", {"write", "stdout"}},
                  {"stdin", {"read_line", NULL}}, {"concat", {"join", "concat"}}, {"split", {"split", "lines"}},
                  {"env", {"environment", NULL}}, {"random", {"random", NULL}}};
  int64_t best = score_words(arena, token, e);
  for (size_t i = 0; i < sizeof SYNONYMS / sizeof SYNONYMS[0]; i++) {
    if (!ms_span_is_text(token, SYNONYMS[i].word)) {
      continue;
    }
    for (size_t a = 0; a < 2 && SYNONYMS[i].alias[a] != NULL; a++) {
      const int64_t s = score_words(arena, ms_span_of_text(SYNONYMS[i].alias[a]), e) * 9 / 10;
      best = s > best ? s : best;
    }
  }
  return best;
}

static bool contains_span(const MsSpans *list, MsSpan item) {
  for (size_t i = 0; i < list->len; i++) {
    if (ms_span_equal(list->ptr[i], item)) {
      return true;
    }
  }
  return false;
}

/* Rewards names whose own words the query spells out and penalizes names with extra words it never mentioned. */
static int64_t name_coverage(const MsSpans *tokens, const Entry *e) {
  int64_t covered = 0;
  for (size_t i = 0; i < e->words.len; i++) {
    covered += contains_span(tokens, e->words.ptr[i]) ? 1 : 0;
  }
  return 15 * covered - 10 * ((int64_t)e->words.len - covered);
}

static int64_t compare_matches(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  MsArena *arena = (MsArena *)(void *)env;
  const MsGuideMatch *x = (const MsGuideMatch *)(const void *)a;
  const MsGuideMatch *y = (const MsGuideMatch *)(const void *)b;
  if (x->score != y->score) {
    return y->score < x->score ? -1 : 1;
  }
  const bool xp = !ms_span_is_text(x->module, "prelude");
  const bool yp = !ms_span_is_text(y->module, "prelude");
  if (xp != yp) {
    return xp ? 1 : -1;
  }
  const MsSpan xs = ms_message_format(arena, "%S.%S", x->module, x->name);
  const MsSpan ys = ms_message_format(arena, "%S.%S", y->module, y->name);
  const size_t n = xs.len < ys.len ? xs.len : ys.len;
  for (size_t i = 0; i < n; i++) {
    if (xs.ptr[i] != ys.ptr[i]) {
      return (int64_t)xs.ptr[i] - (int64_t)ys.ptr[i];
    }
  }
  return (int64_t)xs.len - (int64_t)ys.len;
}

MsGuideMatches ms_guide_search(MsArena *arena, const MsGuide *guide, MsSpan query, size_t limit) {
  MsGuideMatches matches = {0};
  const MsSpans tokens = significant_words(arena, query);
  if (tokens.len == 0) {
    return matches;
  }
  limit = limit == 0 ? 5 : limit;
  const Entries index = standard_index(arena, guide);
  size_t best = 0;
  for (size_t k = 0; k < index.len; k++) {
    const Entry *e = &index.ptr[k];
    int64_t total = 0;
    size_t matched = 0;
    size_t strong = 0;
    for (size_t t = 0; t < tokens.len; t++) {
      const int64_t score = score_token(arena, tokens.ptr[t], e);
      if (score > 0) {
        total += score;
        matched++;
        strong += score >= 25 ? 1 : 0;
      }
    }
    /* A partial match must hinge on a name or module word, never on prose alone. */
    if (matched == 0 || matched < best || (matched < tokens.len && strong == 0)) {
      continue;
    }
    if (matched > best) {
      best = matched;
      matches.len = 0;
    }
    total = total * 10 + name_coverage(&tokens, e) - (int64_t)(e->name.len < 9 ? e->name.len : 9);
    MsGuideMatch m = {.module = e->module, .name = e->name, .kind = e->kind, .signature = e->signature,
                      .doc = first_line(arena, e->doc, 120), .path = std_path(arena, e->module, e->name), .score = total};
    if (e->effects != NULL) {
      m.effects = *e->effects;
    }
    ms_guide_matches_push(arena, &matches, m);
  }
  if (matches.len > 1) {
    ms_sort((uint8_t *)matches.ptr, matches.len, sizeof(MsGuideMatch), compare_matches, (uint8_t *)(void *)arena);
  }
  /* Removes repeats of one declaration that several modules expose. */
  MsGuideMatches kept = {0};
  for (size_t i = 0; i < matches.len && kept.len < limit; i++) {
    bool seen = false;
    for (size_t j = 0; j < kept.len && !seen; j++) {
      seen = ms_span_equal(kept.ptr[j].name, matches.ptr[i].name) && ms_span_equal(kept.ptr[j].signature, matches.ptr[i].signature);
    }
    if (!seen) {
      ms_guide_matches_push(arena, &kept, matches.ptr[i]);
    }
  }
  return kept;
}
