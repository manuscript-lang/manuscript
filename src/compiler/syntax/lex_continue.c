/* Owns the recovery pass of the lexer: which physical lines lie inside a token that began earlier. */
#include "compiler/syntax/lex_internal.h"

/* Whether byte `b` can end the word before a quote, so the quote is not a text prefix. */
static bool ends_word(uint8_t b) {
  return ms_ascii_is_ident(b);
}

/* Whether `prefix` (`f` or `r`) starts text at the cursor: the letter is not the tail of a word. */
static bool prefixes_text(const Scanner *s, const char *prefix) {
  return lex_starts_with(s, s->offset, prefix) && !(s->offset > 0 && ends_word(s->src[s->offset - 1]));
}

static void skip_line_comment(Scanner *s) {
  while (s->offset < s->n && s->src[s->offset] != '\n') {
    lex_advance(s);
  }
}

/* Comments do not nest. Even a malformed comment stays opaque up to its first closer (or the end of the
 * source); strict lexing reports the error. */
static void skip_block_comment(Scanner *s) {
  lex_advance(s);
  lex_advance(s);
  while (s->offset < s->n) {
    if (lex_starts_with(s, s->offset, "*/")) {
      lex_advance(s);
      lex_advance(s);
      return;
    }
    lex_advance(s);
  }
}

/* One-line raw text ends at its first quote; there are no escapes. */
static void skip_raw_line(Scanner *s) {
  lex_advance(s);
  lex_advance(s);
  while (s->offset < s->n) {
    uint8_t byte = lex_advance(s);
    if (byte == '"' || byte == '\n') {
      return;
    }
  }
}

typedef struct Continuations {
  size_t depth;
  bool invalid_text_header; /* the last multi-line text opened without a body line */
  uint32_t leading_line;    /* the line `first_token` was computed for */
  size_t first_token;       /* offset of the first token on that line */
} Continuations;

/* Skips a multi-line text opener and its body. A malformed header's standalone closer must not become a
 * fresh opener; a literal in a new expression supersedes that malformed header. */
static void skip_multiline(Scanner *s, Continuations *c) {
  bool raw = s->src[s->offset] == 'r';
  if (c->leading_line != s->line) {
    c->leading_line = s->line;
    size_t line_start = s->offset - (s->column - 1);
    size_t at = line_start;
    while (at < s->n && (s->src[at] == ' ' || s->src[at] == '\t')) {
      at++;
    }
    c->first_token = at;
  }
  bool standalone = s->offset == c->first_token;
  for (int i = 0; i < (raw ? 4 : 3); i++) {
    lex_advance(s);
  }
  bool body = lex_peek(s, s->offset) == '\n';
  bool closing_invalid = c->invalid_text_header && standalone && !raw && c->depth == 0;
  c->invalid_text_header = !body;
  if (!body || closing_invalid) {
    return;
  }
  while (s->offset < s->n) {
    if (lex_starts_with(s, s->offset, "\"\"\"")) {
      for (int i = 0; i < 3; i++) {
        lex_advance(s);
      }
      return;
    }
    uint8_t byte = lex_advance(s);
    if (!raw && byte == '\\' && s->offset < s->n) {
      lex_advance(s);
    }
  }
}

static void skip_quoted(Scanner *s) {
  bool formatted = s->offset > 0 && s->src[s->offset - 1] == 'f' && !(s->offset > 1 && ends_word(s->src[s->offset - 2]));
  (void)lex_scan_string(s, formatted); /* an invalid text is reported by the strict lex */
}

/* Advances over one token, comment or character. */
static void skip_one(Scanner *s, Continuations *c) {
  if (lex_at_line_comment(s)) {
    skip_line_comment(s);
  } else if (lex_at_block_comment(s)) {
    skip_block_comment(s);
  } else if (prefixes_text(s, "f\"")) {
    lex_advance(s); /* the prefix of interpolating text; the quote is handled next */
  } else if (prefixes_text(s, "r\"") && !lex_starts_with(s, s->offset + 2, "\"\"")) {
    skip_raw_line(s);
  } else if (lex_starts_with(s, s->offset, "r\"\"\"") || lex_starts_with(s, s->offset, "\"\"\"")) {
    skip_multiline(s, c);
  } else if (s->src[s->offset] == '"') {
    skip_quoted(s);
  } else {
    uint8_t byte = lex_advance(s);
    if (byte == '(' || byte == '[' || byte == '{') {
      c->depth++;
    } else if ((byte == ')' || byte == ']' || byte == '}') && c->depth > 0) {
      c->depth--;
    }
  }
}

bool *ms_lex_continuations(MsArena *arena, MsSpan source, const bool *roots, size_t nroots, size_t *nlines) {
  const uint32_t *offsets = NULL;
  MsSpan text = lex_normalize(arena, source, &offsets);
  MsDiag scratch = {0};
  Scanner s;
  lex_scanner_init(&s, arena, text, offsets, &scratch);
  size_t count = 1;
  for (size_t i = 0; i < source.len; i++) {
    count += source.ptr[i] == '\n';
  }
  bool *lines = MS_ARENA_NEW_ARRAY(arena, bool, count);
  Continuations c = {0};
  while (s.offset < s.n) {
    size_t first = s.line - 1;
    if (s.column == 1 && first < nroots && roots[first]) {
      c.depth = 0;
    }
    skip_one(&s, &c);
    /* An invalid single-line string may consume its newline before failing; the following line still
     * starts independently. */
    size_t last = s.line - 1 - (s.column == 1 ? 1 : 0);
    for (size_t line = first + 1; line <= last && line < count; line++) {
      lines[line] = true;
    }
  }
  lex_scanner_free(&s);
  *nlines = count;
  return lines;
}

/* An offset of the normalised text as an offset of the source it came from. */
static size_t source_offset(const Scanner *s, size_t offset, uint32_t line) {
  return s->line_offsets == NULL ? offset : offset + s->line_offsets[line - 1];
}

size_t ms_lex_skim(MsArena *arena, MsSpan source, MsSkimSpan **out) {
  const uint32_t *offsets = NULL;
  MsSpan text = lex_normalize(arena, source, &offsets);
  MsDiag scratch = {0};
  Scanner s;
  lex_scanner_init(&s, arena, text, offsets, &scratch);
  Continuations c = {0};
  MsSkimSpan *spans = MS_ARENA_NEW_ARRAY(arena, MsSkimSpan, source.len + 1);
  size_t count = 0;
  while (s.offset < s.n) {
    const size_t start = s.offset;
    const uint32_t line = s.line;
    const bool prefix = prefixes_text(&s, "f\"");
    const bool comment = lex_at_line_comment(&s) || lex_at_block_comment(&s);
    const bool text_start = prefix || s.src[s.offset] == '"' || lex_starts_with(&s, s.offset, "r\"");
    skip_one(&s, &c);
    if (prefix) skip_one(&s, &c); /* the quote after the `f` */
    if (!comment && !text_start) continue;
    spans[count++] = (MsSkimSpan){comment ? MS_SKIM_COMMENT : MS_SKIM_TEXT, source_offset(&s, start, line),
                                  source_offset(&s, s.offset, s.line)};
  }
  lex_scanner_free(&s);
  *out = spans;
  return count;
}
