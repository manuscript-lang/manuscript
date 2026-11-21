/* Owns the scanner primitives: errors, cursor, token emission, comments and numbers. */
#include "base/chars.h"
#include "base/utf8.h"
#include "compiler/syntax/lex_internal.h"

static const char COMMENT_CR[] =
    "lone carriage returns are not allowed in comments; use line endings of LF or CRLF";
static const char COMMENT_BIDI[] =
    "bidirectional text controls (U+202A..U+202E, U+2066..U+2069) are not allowed in comments because they "
    "can make source display differently from how it is read; remove the character";

bool lex_is_binary_digit(uint8_t byte) {
  return byte == '0' || byte == '1';
}

bool lex_is_graphic(uint8_t byte) {
  return byte > 0x20 && byte < 0x7f;
}

bool lex_is_word_byte(uint8_t byte) {
  return ms_ascii_is_ident_start(byte) || ms_ascii_is_digit(byte);
}

/* ---- errors ---- */

MsPos lex_pos(const Scanner *s) {
  uint32_t offset = (uint32_t)s->offset + s->base_offset;
  if (s->line_offsets != NULL) {
    offset += s->line_offsets[s->line - s->base_line - 1];
  }
  return (MsPos){.offset = offset, .line = s->line, .column = s->column};
}

/* Starts the diagnostic for the scan in progress; the caller fills the optional range and fix. */
MsDiag *lex_new_diag(Scanner *s, MsPos pos, MsSpan message) {
  *s->diag = (MsDiag){.pos = pos, .message = message};
  return s->diag;
}

/* The lex_fail functions record a diagnostic and return false, so a scanner function reports its failure
 * with `return lex_fail...(...)` and every caller passes that false on. */
bool lex_fail_at(Scanner *s, MsPos pos, MsSpan message) {
  (void)lex_new_diag(s, pos, message);
  return false;
}

bool lex_fail(Scanner *s, MsSpan message) {
  return lex_fail_at(s, lex_pos(s), message);
}

bool lex_fail_text(Scanner *s, const char *message) {
  return lex_fail(s, ms_span_of_text(message));
}

bool lex_fail_at_text(Scanner *s, MsPos pos, const char *message) {
  return lex_fail_at(s, pos, ms_span_of_text(message));
}

bool lex_fail_format(Scanner *s, const char *format, ...) {
  va_list arguments;
  va_start(arguments, format);
  MsSpan message = ms_message_vformat(s->arena, format, arguments);
  va_end(arguments);
  return lex_fail(s, message);
}

bool lex_fail_at_format(Scanner *s, MsPos pos, const char *format, ...) {
  va_list arguments;
  va_start(arguments, format);
  MsSpan message = ms_message_vformat(s->arena, format, arguments);
  va_end(arguments);
  return lex_fail_at(s, pos, message);
}

/* Reports a character whose first byte was just consumed: the cursor may be inside its UTF-8 encoding, so
 * it is not itself a diagnostic boundary. */
bool lex_fail_previous_byte(Scanner *s, MsSpan message) {
  MsPos pos = lex_pos(s);
  pos.offset -= 1;
  pos.column -= 1;
  return lex_fail_at(s, pos, message);
}

/* Fails on the single ASCII character at the cursor, with its range and the fix when one exists. */
bool lex_fail_char(Scanner *s, MsSpan message, const char *replacement) {
  MsPos pos = lex_pos(s);
  MsPos end = {pos.offset + 1, pos.line, pos.column + 1};
  MsDiag *diag = lex_new_diag(s, pos, message);
  diag->has_end = true;
  diag->end = end;
  if (replacement != NULL) {
    diag->has_fix = true;
    diag->fix_pos = pos;
    diag->fix_end = end;
    diag->replacement = ms_span_of_text(replacement);
  }
  return false;
}

/* Fails on the source range [start, cursor). */
bool lex_fail_range(Scanner *s, MsPos start, MsSpan message) {
  MsDiag *diag = lex_new_diag(s, start, message);
  diag->has_end = true;
  diag->end = lex_pos(s);
  return false;
}

/* ---- Rust's `{:?}` for a char ---- */

static void append_escape(MsStrBuild *out, uint32_t scalar) {
  switch (scalar) {
  case 0:
    ms_strbuild_append_text(out, "\\0");
    return;
  case '\t':
    ms_strbuild_append_text(out, "\\t");
    return;
  case '\r':
    ms_strbuild_append_text(out, "\\r");
    return;
  case '\n':
    ms_strbuild_append_text(out, "\\n");
    return;
  case '\\':
    ms_strbuild_append_text(out, "\\\\");
    return;
  case '\'':
    ms_strbuild_append_text(out, "\\'");
    return;
  default:
    break;
  }
  if (!lex_is_debug_escaped(scalar)) {
    ms_strbuild_append_utf8(out, scalar);
    return;
  }
  ms_strbuild_append_text(out, "\\u{");
  ms_strbuild_append_u64_radix(out, scalar, 16);
  ms_strbuild_append_byte(out, '}');
}

void ms_quote_rune(MsStrBuild *out, uint32_t scalar) {
  ms_strbuild_append_byte(out, '\'');
  append_escape(out, scalar);
  ms_strbuild_append_byte(out, '\'');
}

MsSpan lex_quote_rune(Scanner *s, uint32_t scalar) {
  MsStrBuild builder = ms_strbuild_new();
  ms_quote_rune(&builder, scalar);
  MsSpan quoted = ms_message_from_builder(s->arena, &builder);
  ms_strbuild_free(&builder);
  return quoted;
}

/* ---- cursor ---- */

uint8_t lex_advance(Scanner *s) {
  uint8_t b = s->src[s->offset++];
  if (b == '\n') {
    s->line++;
    s->column = 1;
  } else {
    s->column++;
  }
  return b;
}

int lex_peek(const Scanner *s, size_t i) {
  return i < s->n ? s->src[i] : -1;
}

bool lex_starts_with(const Scanner *s, size_t i, const char *lit) {
  return i <= s->n && ms_span_starts_with(ms_span_of(s->src + i, s->n - i), ms_span_of_text(lit));
}

bool lex_at_line_comment(const Scanner *s) {
  return s->src[s->offset] == '/' && lex_peek(s, s->offset + 1) == '/';
}
bool lex_at_block_comment(const Scanner *s) {
  return s->src[s->offset] == '/' && lex_peek(s, s->offset + 1) == '*';
}

/* Whether the UTF-8 sequence at `i` is a bidirectional text control (U+202A..U+202E,
 * U+2066..U+2069). */
bool lex_bidi_control_at(const Scanner *s, size_t i) {
  if (i + 3 > s->n) {
    return false;
  }
  const uint8_t *p = s->src + i;
  return (p[0] == 0xE2 && p[1] == 0x80 && p[2] >= 0xAA && p[2] <= 0xAE) ||
         (p[0] == 0xE2 && p[1] == 0x81 && p[2] >= 0xA6 && p[2] <= 0xA9);
}

void lex_emit(Scanner *s, MsTok kind, size_t lo, size_t hi, MsPos pos) {
  MsToken t = {pos, lex_pos(s), (uint32_t)lo, (uint32_t)hi, (uint8_t)kind};
  token_list_push(&s->tokens, t);
}

void lex_emit_layout(Scanner *s, MsTok kind) {
  MsPos p = lex_pos(s);
  MsToken t = {p, p, (uint32_t)s->offset, (uint32_t)s->offset, (uint8_t)kind};
  token_list_push(&s->tokens, t);
}

size_t lex_token_count(const Scanner *s) {
  return s->tokens.len;
}
MsToken *lex_token_at(const Scanner *s, size_t i) {
  return &s->tokens.ptr[i];
}
int lex_last_kind(const Scanner *s) {
  size_t n = lex_token_count(s);
  return n == 0 ? -1 : lex_token_at(s, n - 1)->kind;
}

/* Whether the word ending at `hi` is a member or field name, where a contextual keyword is an
 * ordinary name: after `.`, or a `name:` label that opens a line or follows `(` or `,`. */
bool lex_names_a_member(const Scanner *s, size_t hi) {
  int prev = lex_last_kind(s);
  if (prev == MS_T_Dot) {
    return true;
  }
  bool label_start = prev == MS_T_LParen || prev == MS_T_Comma || prev == MS_T_Newline ||
                     prev == MS_T_Indent || prev == MS_T_Dedent || prev == -1;
  size_t j = hi;
  while (lex_peek(s, j) == ' ') {
    j++;
  }
  return label_start && lex_peek(s, j) == ':' && lex_peek(s, j + 1) != '=';
}

/* Whether only whitespace or a `//` comment follows the cursor on its line. */
bool lex_trailing_semicolon(const Scanner *s) {
  size_t i = s->offset + 1;
  while (i < s->n && (s->src[i] == ' ' || s->src[i] == '\t')) {
    i++;
  }
  if (i >= s->n || s->src[i] == '\n') {
    return true;
  }
  if (s->src[i] == '/' && lex_peek(s, i + 1) == '/') {
    return true;
  }
  /* line == "\r" */
  return s->src[i] == '\r' && (i + 1 >= s->n || s->src[i + 1] == '\n');
}

/* ---- comments ---- */

MS_NODISCARD bool lex_skip_comment(Scanner *s) {
  while (s->offset < s->n && s->src[s->offset] != '\n') {
    if (s->src[s->offset] == '\r') {
      return lex_fail_text(s, COMMENT_CR);
    }
    if (lex_bidi_control_at(s, s->offset)) {
      return lex_fail_text(s, COMMENT_BIDI);
    }
    lex_advance(s);
  }
  return true;
}

/* Consumes a block comment, which does not nest, and the blanks and optional `//` comment after
 * its `*​/`; the cursor ends at the line's newline. */
MS_NODISCARD bool lex_skip_block_comment(Scanner *s) {
  MsPos open = lex_pos(s);
  size_t start = s->offset;
  lex_advance(s);
  lex_advance(s);
  for (;;) {
    if (s->offset >= s->n) {
      return lex_fail_at_text(s, open, "unterminated block comment; close it with '*/'");
    }
    uint8_t b = s->src[s->offset];
    if (b == '*' && lex_peek(s, s->offset + 1) == '/') {
      lex_advance(s);
      lex_advance(s);
      MsByteRange r = {start, s->offset};
      range_list_push(&s->blocks, r);
      break;
    }
    if (b == '/' && lex_peek(s, s->offset + 1) == '*') {
      return lex_fail_text(s, "block comments do not nest; remove the inner '/*'");
    }
    if (b == '\r') {
      return lex_fail_text(s, COMMENT_CR);
    }
    if (lex_bidi_control_at(s, s->offset)) {
      return lex_fail_text(s, COMMENT_BIDI);
    }
    lex_advance(s);
  }
  while (s->offset < s->n && s->src[s->offset] == ' ') {
    lex_advance(s);
  }
  if (s->offset < s->n && lex_at_line_comment(s)) {
    if (!lex_skip_comment(s)) {
      return false;
    }
    return true;
  }
  if (s->offset < s->n && s->src[s->offset] != '\n') {
    return lex_fail_text(s, "code cannot follow a block comment on the same line; start a new line");
  }
  return true;
}

/* ---- numbers ---- */

/* Consumes digits accepted by `ok`, allowing `_` only between two digits. */
MS_NODISCARD static bool scan_digits(Scanner *s, bool (*ok)(uint8_t), bool after_digit) {
  while (s->offset < s->n) {
    uint8_t b = s->src[s->offset];
    if (ok(b)) {
      after_digit = true;
    } else if (b == '_') {
      bool next_ok = s->offset + 1 < s->n && ok(s->src[s->offset + 1]);
      if (!after_digit || !next_ok) {
        return lex_fail_text(s, "a digit separator goes between two digits; write e.g. 1_000_000 or 0xFF_FF");
      }
      after_digit = false;
    } else {
      break;
    }
    lex_advance(s);
  }
  return true;
}

/* A `0x` or `0b` literal: the prefix is at the cursor's `start`, `ok` accepts its digits. */
MS_NODISCARD static bool scan_radix_number(Scanner *s, MsPos p, size_t start, bool (*ok)(uint8_t)) {
  lex_advance(s);
  if (s->offset == s->n || !ok(s->src[s->offset])) {
    return lex_fail_text(
        s, "a hexadecimal or binary literal requires digits after the prefix; write e.g. 0xFF or 0b1010");
  }
  if (!scan_digits(s, ok, false)) {
    return false;
  }
  if (s->offset < s->n && lex_is_word_byte(s->src[s->offset])) {
    return lex_fail_text(
        s, "invalid digit in a hexadecimal or binary literal; 0x takes 0-9 and a-f, 0b takes 0 and 1");
  }
  lex_emit(s, MS_T_Number, start, s->offset, p);
  return true;
}

/* The digits after the `e` of a floating-point exponent, with an optional sign. */
MS_NODISCARD static bool scan_exponent(Scanner *s) {
  lex_advance(s);
  if (s->offset < s->n && (s->src[s->offset] == '+' || s->src[s->offset] == '-')) {
    lex_advance(s);
  }
  if (s->offset == s->n || !ms_ascii_is_digit(s->src[s->offset])) {
    return lex_fail_text(s, "an exponent requires digits; write e.g. 1e3 or 2.5e-4");
  }
  while (s->offset < s->n && ms_ascii_is_digit(s->src[s->offset])) {
    lex_advance(s);
  }
  return true;
}

static bool word_has_prefix(MsSpan word, const char *a, const char *b) {
  return word.len > 1 &&
         (ms_span_starts_with(word, ms_span_of_text(a)) || ms_span_starts_with(word, ms_span_of_text(b)));
}

static const char *suffix_reason(MsSpan word) {
  if (word_has_prefix(word, "0o", "0O")) {
    return "octal literals do not exist, so write the value in decimal, hexadecimal (0x) or binary (0b)";
  }
  for (size_t index = 0; index < word.len; index++) {
    if (word.ptr[index] == '_') {
      return "a digit separator goes between two digits of the integer or fraction part, e.g. 1_000_000";
    }
  }
  return "the only numeric suffix is d for Decimal (1.5d), so put a space or operator after the number";
}

/* A number followed by letters: names what went wrong from the whole word. */
static bool fail_number_suffix(Scanner *s, MsPos p, size_t start) {
  while (s->offset < s->n && lex_is_word_byte(s->src[s->offset])) {
    lex_advance(s);
  }
  MsSpan word = ms_span_of(s->src + start, s->offset - start);
  if (word_has_prefix(word, "0X", "0B")) {
    MsSpan message =
        ms_message_format(s->arena, "invalid number %S; the prefix is lowercase, so write 0%c%S", word,
                          ms_ascii_to_lower(word.ptr[1]), ms_span_of(word.ptr + 2, word.len - 2));
    return lex_fail_range(s, p, message);
  }
  MsSpan message = ms_message_format(s->arena, "invalid number %S; %s", word, suffix_reason(word));
  return lex_fail_range(s, p, message);
}

MS_NODISCARD bool lex_scan_number(Scanner *s, MsPos p) {
  size_t start = s->offset;
  lex_advance(s);
  bool zero = s->src[start] == '0' && s->offset < s->n;
  if (zero && s->src[s->offset] == 'x') {
    return scan_radix_number(s, p, start, ms_ascii_is_hex);
  }
  if (zero && s->src[s->offset] == 'b') {
    return scan_radix_number(s, p, start, lex_is_binary_digit);
  }
  if (zero && (ms_ascii_is_digit(s->src[s->offset]) || s->src[s->offset] == '_')) {
    return lex_fail_text(s, "leading zeros are not allowed in numeric literals; write the number without "
                            "them, e.g. 42 instead of 042");
  }
  if (!scan_digits(s, ms_ascii_is_digit, true)) {
    return false;
  }
  if (s->offset + 1 < s->n && s->src[s->offset] == '.' && ms_ascii_is_digit(s->src[s->offset + 1])) {
    lex_advance(s);
    if (!scan_digits(s, ms_ascii_is_digit, false)) {
      return false;
    }
  }
  if (s->offset < s->n && (s->src[s->offset] == 'e' || s->src[s->offset] == 'E') && !scan_exponent(s)) {
    return false;
  }
  if (s->offset < s->n && s->src[s->offset] == 'd') {
    lex_advance(s);
  }
  if (s->offset < s->n && ms_ascii_is_ident_start(s->src[s->offset])) {
    return fail_number_suffix(s, p, start);
  }
  lex_emit(s, MS_T_Number, start, s->offset, p);
  return true;
}
