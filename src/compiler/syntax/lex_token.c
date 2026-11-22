/* Owns the scanning of one token: words, operators, delimiters and unexpected characters. */
#include "compiler/syntax/lex_internal.h"

/* ---- tokens ---- */

static void scan_word(Scanner *s, MsPos pos) {
  size_t start = s->offset;
  size_t end = start;
  while (end < s->n && lex_is_word_byte(s->src[end])) {
    end++;
  }
  s->column += (uint32_t)(end - start);
  s->offset = end;
  MsTok kind = ms_tok_from_word(ms_span_of(s->src + start, end - start));
  if (ms_tok_is_contextual(kind) && lex_names_a_member(s, end)) {
    kind = MS_T_Name;
  }
  if (kind == MS_T_Fn || kind == MS_T_Match) {
    size_list_push(&s->function_depths, lex_open_delimiters(s));
  }
  lex_emit(s, kind, start, end, pos);
}

static bool scan_raw_text_token(Scanner *s, MsPos pos) {
  size_t start = s->offset;
  bool ok =
      lex_starts_with(s, s->offset + 1, "\"\"\"") ? lex_scan_multiline(s, true, false) : lex_scan_raw_line(s);
  if (ok) {
    lex_emit(s, MS_T_String, start, s->offset, pos);
  }
  return ok;
}

static bool scan_text_token(Scanner *s, MsPos pos) {
  size_t start = s->offset;
  bool formatted = s->src[start] == 'f';
  if (formatted) {
    lex_advance(s);
  }
  if (!lex_scan_string(s, formatted)) {
    return false;
  }
  lex_emit(s, MS_T_String, start, s->offset, pos);
  return true;
}

/* The two-character operator at the cursor, or -1. */
static int two_char_kind(uint8_t first, int second) {
  switch (first) {
  case '.':
    return second == '.' ? MS_T_DotDot : -1;
  case '-':
    return second == '>' ? MS_T_Arrow : -1;
  case ':':
    return second == '=' ? MS_T_ColonAssign : -1;
  case '=':
    return second == '=' ? MS_T_EqEq : -1;
  case '!':
    return second == '=' ? MS_T_NotEq : -1;
  case '<':
    return second == '=' ? MS_T_Le : -1;
  case '>':
    return second == '=' ? MS_T_Ge : -1;
  default:
    return -1;
  }
}

static bool scan_operator_token(Scanner *s, MsPos pos, size_t length, MsTok kind) {
  size_t start = s->offset;
  for (size_t i = 0; i < length; i++) {
    lex_advance(s);
  }
  lex_emit(s, kind, start, start + length, pos);
  return true;
}

/* `!` directly after a type-ending character is the Result suffix of `T!` or `T!E`; anywhere else
 * it stays the removed negation. */
static bool bang_is_result_suffix(const Scanner *s) {
  if (s->offset == 0 || lex_token_count(s) == 0) {
    return false;
  }
  int last = lex_last_kind(s);
  uint8_t before = s->src[s->offset - 1];
  bool after_type = last == MS_T_Name || last == MS_T_RBracket || last == MS_T_RParen ||
                    last == MS_T_Question || last == MS_T_Bang;
  return after_type &&
         (lex_is_word_byte(before) || before == ']' || before == ')' || before == '?' || before == '!');
}

/* The kind of a single-character token, or MS_T_Eof when the character is not one. */
static MsTok single_char_kind(uint8_t b) {
  switch (b) {
  case '(':
    return MS_T_LParen;
  case ')':
    return MS_T_RParen;
  case '[':
    return MS_T_LBracket;
  case ']':
    return MS_T_RBracket;
  case '{':
    return MS_T_LBrace;
  case '}':
    return MS_T_RBrace;
  case ':':
    return MS_T_Colon;
  case ',':
    return MS_T_Comma;
  case '.':
    return MS_T_Dot;
  case '?':
    return MS_T_Question;
  case '+':
    return MS_T_Plus;
  case '-':
    return MS_T_Minus;
  case '*':
    return MS_T_Star;
  case '/':
    return MS_T_Slash;
  case '%':
    return MS_T_Percent;
  case '<':
    return MS_T_Lt;
  case '>':
    return MS_T_Gt;
  case '=':
    return MS_T_Assign;
  case '&':
    return MS_T_Amp;
  case '|':
    return MS_T_Pipe;
  case '@':
    return MS_T_At;
  default:
    return MS_T_Eof;
  }
}

static bool fail_unexpected_char(Scanner *s, uint8_t b) {
  if (b >= 0x80) {
    MsRune rune = ms_utf8_decode(s->src + s->offset, s->n - s->offset);
    MsSpan quoted = lex_quote_rune(s, rune.rune);
    return lex_fail_format(s,
                           "unexpected source character %S; non-ASCII characters are only allowed inside "
                           "text and comments, and identifiers are ASCII",
                           quoted);
  }
  MsSpan quoted = lex_quote_rune(s, b);
  const char *replacement = NULL;
  if (b == ';' && lex_trailing_semicolon(s)) {
    replacement = ""; /* removing a mid-line `;` would fuse two statements */
  } else if (b == '!') {
    replacement = "not ";
  } else if (b == '#') {
    replacement = "//";
  }
  MsSpan message = ms_message_format(s->arena, "unexpected source character %S%s", quoted,
                                     lex_character_hint(b));
  return lex_fail_char(s, message, replacement);
}

static void open_delimiter(Scanner *s, MsPos pos, uint8_t b) {
  byte_list_push(&s->delimiters, b);
  pos_list_push(&s->opened, pos);
  if (b == '(' && lex_last_kind(s) == MS_T_Var) {
    size_list_push(&s->groups, lex_open_delimiters(s));
  }
}

static bool close_delimiter(Scanner *s, const LineInfo *info, uint8_t b) {
  if (s->virtual_paren && lex_open_delimiters(s) == 1 && s->delimiters.ptr[0] == '(' && b == ')') {
    /* The physical wrapper would leave its own closing parenthesis unmatched; use that path
     * for its exact error. */
    return lex_fail_text(s, "interpolation closes the virtual parenthesis");
  }
  if (lex_open_delimiters(s) == 0) {
    /* A lone `}` left behind by a braced block is removed by the fix. */
    const char *fix = (b == '}' && lex_trailing_semicolon(s)) ? "" : NULL;
    MsSpan message = ms_message_format(
        s->arena, "unmatched closing delimiter '%c'; remove it or add the matching opener before it", b);
    return lex_fail_char(s, message, fix);
  }
  if (s->levels.len > 1 && lex_open_delimiters(s) <= info->top_depth && info->leading >= info->top_indent) {
    return lex_fail_text(s, "an outer delimiter cannot close inside a function suite; close the bracket on "
                            "the line where the function body ends, or dedent the body");
  }
  uint8_t open = s->delimiters.ptr[s->delimiters.len - 1];
  if ((char)b != lex_closer_of(open)) {
    MsPos opener = s->opened.ptr[s->opened.len - 1];
    return lex_fail_format(s, "mismatched closing delimiter '%c'; the '%c' opened at line %u:%u needs '%c'",
                           b, open, opener.line, opener.column, lex_closer_of(open));
  }
  if (s->groups.len != 0 && s->groups.ptr[s->groups.len - 1] == lex_open_delimiters(s)) {
    s->groups.len--;
  }
  s->delimiters.len--;
  s->opened.len--;
  while (s->function_depths.len != 0 &&
         s->function_depths.ptr[s->function_depths.len - 1] > lex_open_delimiters(s)) {
    s->function_depths.len--;
  }
  return true;
}

/* Scans a punctuation token: an operator, a delimiter, or a character that is not Manuscript. */
static bool scan_symbol(Scanner *s, const LineInfo *info, MsPos pos, uint8_t b) {
  if (b == '.' && lex_peek(s, s->offset + 1) == '.' && lex_peek(s, s->offset + 2) == '.') {
    return scan_operator_token(s, pos, 3, MS_T_Ellipsis);
  }
  int two = two_char_kind(b, lex_peek(s, s->offset + 1));
  if (two >= 0) {
    return scan_operator_token(s, pos, 2, (MsTok)two);
  }
  MsTok kind = single_char_kind(b);
  if (b == '!' && bang_is_result_suffix(s)) {
    kind = MS_T_Bang;
  }
  if (kind == MS_T_Eof) {
    return fail_unexpected_char(s, b);
  }
  if (b == '(' || b == '[' || b == '{') {
    open_delimiter(s, pos, b);
  } else if ((b == ')' || b == ']' || b == '}') && !close_delimiter(s, info, b)) {
    return false;
  }
  return scan_operator_token(s, pos, 1, kind);
}

/* Scans one token or blank at the cursor; sets *line_done when a comment ends the line. */
static bool scan_token(Scanner *s, const LineInfo *info, bool *line_done) {
  uint8_t b = s->src[s->offset];
  MsPos pos = lex_pos(s);
  if (b == ' ') {
    lex_advance(s);
    return true;
  }
  if (lex_at_line_comment(s)) {
    *line_done = true;
    return lex_skip_comment(s);
  }
  if (lex_at_block_comment(s)) {
    return lex_fail_text(s, "a block comment must start its own line; write a trailing comment with '//'");
  }
  if (b == '\t' || b == '\r') {
    return lex_fail_text(s, "tabs are allowed only in indentation, and lone carriage returns not at all; use "
                            "spaces between tokens, and line endings of LF or CRLF");
  }
  if (b == 'r' && lex_peek(s, s->offset + 1) == '"') {
    return scan_raw_text_token(s, pos);
  }
  if (b == '"' || (b == 'f' && lex_peek(s, s->offset + 1) == '"')) {
    return scan_text_token(s, pos);
  }
  if (ms_ascii_is_ident_start(b)) {
    scan_word(s, pos);
    return true;
  }
  if (ms_ascii_is_digit(b)) {
    return lex_scan_number(s, pos);
  }
  return scan_symbol(s, info, pos, b);
}

bool lex_scan_line_tokens(Scanner *s, const LineInfo *info) {
  bool line_done = false;
  while (!line_done && s->offset < s->n && s->src[s->offset] != '\n') {
    if (!scan_token(s, info, &line_done)) {
      return false;
    }
  }
  return true;
}
