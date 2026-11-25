/* syntax/lex_internal.h: the scanner state and the functions its files share. Private to the lexer. */
#ifndef MS_SYNTAX_LEX_INTERNAL_H
#define MS_SYNTAX_LEX_INTERNAL_H

#include <stdarg.h>

#include "base/chars.h"
#include "base/list.h"
#include "base/utf8.h"
#include "compiler/syntax/lex.h"
#include "base/message.h"

typedef struct LinePos {
  size_t at;
  MsPos pos;
} LinePos;

MS_LIST_DEFINE(TokenList, token_list, MsToken)
MS_LIST_DEFINE(ByteList, byte_list, uint8_t)
MS_LIST_DEFINE(SizeList, size_list, size_t)
MS_LIST_DEFINE(PosList, pos_list, MsPos)
MS_LIST_DEFINE(RangeList, range_list, MsByteRange)
MS_LIST_DEFINE(LineList, line_list, LinePos)

typedef struct Scanner {
  MsArena *arena;
  const uint8_t *src;
  size_t n;
  size_t offset;
  uint32_t line, column;
  TokenList tokens;
  ByteList delimiters;
  SizeList groups;
  PosList opened;
  PosList interpolations;
  const uint32_t *line_offsets;       /* NULL when the source had no CRLF */
  RangeList strings, interps, blocks; /* discovered boundaries */
  const MsBounds *cached;
  size_t boundary_origin;
  uint32_t base_offset, base_line; /* where a slice of a larger file starts */
  bool virtual_paren;
  bool tolerant;     /* skip a line that fails to lex, restoring the delimiters it found: only the delimiter state matters */
  bool open_at_end;  /* the input ended inside an unterminated delimiter or multi-line text */
  MsDiag *diag;
} Scanner;

/* ---- shared by the lexer files (each is defined in the file named by its group) ---- */

uint8_t lex_advance(Scanner *s);
bool lex_at_block_comment(const Scanner *s);
bool lex_at_line_comment(const Scanner *s);
bool lex_bidi_control_at(const Scanner *s, size_t i);
const char *lex_character_hint(uint8_t b);
uint8_t lex_closer_of(uint8_t open);
bool lex_continues_next(const Scanner *s);
void lex_emit(Scanner *s, MsTok kind, size_t lo, size_t hi, MsPos pos);
void lex_emit_layout(Scanner *s, MsTok kind);
bool lex_fail(Scanner *s, MsSpan message);
bool lex_fail_at(Scanner *s, MsPos pos, MsSpan message);
bool lex_fail_at_format_(Scanner *s, MsPos pos, const char *format, ...);
#define lex_fail_at_format(s, pos, ...) lex_fail_at_format_((s), (pos), MS_FMT_ARGS(__VA_ARGS__))
bool lex_fail_char(Scanner *s, MsSpan message, const char *replacement);
bool lex_fail_format_(Scanner *s, const char *format, ...);
#define lex_fail_format(s, ...) lex_fail_format_((s), MS_FMT_ARGS(__VA_ARGS__))
bool lex_fail_previous_byte(Scanner *s, MsSpan message);
bool lex_is_debug_escaped(uint32_t scalar);
bool lex_is_graphic(uint8_t byte);
static inline bool lex_is_word_byte(uint8_t byte) {
  return ms_ascii_is_ident_start(byte) || ms_ascii_is_digit(byte);
}
int lex_last_kind(const Scanner *s);
bool lex_names_a_member(const Scanner *s, size_t hi);
MsDiag *lex_new_diag(Scanner *s, MsPos pos, MsSpan message);
size_t lex_open_delimiters(const Scanner *s);
int lex_peek(const Scanner *s, size_t i);
MsPos lex_pos(const Scanner *s);
MsSpan lex_quote_rune(Scanner *s, uint32_t scalar);
bool lex_read_leading_space(Scanner *s, size_t *leading);
MsSpan lex_normalize(MsArena *arena, MsSpan source, const uint32_t **offsets);
void lex_scanner_init(Scanner *s, MsArena *arena, MsSpan text, const uint32_t *line_offsets, MsDiag *diag);
void lex_scanner_free(Scanner *s);
MS_NODISCARD bool lex_scan_multiline(Scanner *s, bool raw, bool interpolating);
MS_NODISCARD bool lex_scan_number(Scanner *s, MsPos p);
MS_NODISCARD bool lex_scan_raw_line(Scanner *s);
MS_NODISCARD bool lex_scan_string(Scanner *s, bool interpolating);
bool lex_skip_blank_line(Scanner *s, bool *skipped);
MS_NODISCARD bool lex_skip_block_comment(Scanner *s);
MS_NODISCARD bool lex_skip_comment(Scanner *s);
bool lex_starts_with(const Scanner *s, size_t i, const char *lit);
MsToken *lex_token_at(const Scanner *s, size_t i);
size_t lex_token_count(const Scanner *s);
bool lex_trailing_semicolon(const Scanner *s);
bool lex_fail_text(Scanner *s, const char *message);
bool lex_fail_at_text(Scanner *s, MsPos pos, const char *message);
bool lex_fail_range(Scanner *s, MsPos start, MsSpan message);
bool lex_is_binary_digit(uint8_t byte);
bool lex_scan_line_tokens(Scanner *s);
bool lex_statement_level(const Scanner *s);
uint8_t lex_open_char(uint8_t delimiter);

#endif
