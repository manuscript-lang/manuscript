/* syntax/format_internal.h: what the formatter's files share: the context of one `ms_format` call, text
 * helpers over spans, and the entry points of the passes. A pass takes source text and returns new text;
 * parse and lex results live in a scratch arena the pass frees, so only the strings it returns stay
 * allocated. Private to the formatter. */
#ifndef MS_SYNTAX_FORMAT_INTERNAL_H
#define MS_SYNTAX_FORMAT_INTERNAL_H

#include <stdlib.h>
#include <string.h>

#include "base/chars.h"
#include "base/list.h"
#include "base/search.h"
#include "base/strbuild.h"
#include "base/utf8.h"
#include "compiler/syntax/ast.h"
#include "compiler/syntax/lex.h"
#include "base/message.h"
#include "compiler/syntax/parse.h"

enum { FMT_WIDTH = 88, FMT_FLOW_WIDTH = 50 };
#define FMT_NONE SIZE_MAX

/* One formatting run: where result strings live, the names the parser interns, and the first syntax error. */
/* A text that parsed or lexed, with its result: the passes hand each other the same text, so each is read once. */
typedef struct FmtParsed {
  MsSpan text; /* a copy the result's spans point into */
  MsModule module;
  MsLexed lexed;
  bool has_module;
  bool has_lexed;
} FmtParsed;

typedef struct Fmt {
  MsArena *arena;
  MsNames *names;
  MsDiag diag;
  MsArena memo;       /* owns the cached texts and their results, until the run ends */
  FmtParsed *parsed;  /* the texts seen so far, a short list */
  size_t nparsed;
  size_t cap_parsed;
} Fmt;

/* The entry for `source`, added empty when new. */
FmtParsed *fmt_parsed_entry(Fmt *f, MsSpan source);

MS_LIST_DEFINE(SpanList, span_list, MsSpan)
MS_LIST_DEFINE(RangeList, range_list, MsByteRange)
MS_LIST_DEFINE(U32List, u32_list, uint32_t)
MS_LIST_DEFINE(TokenList, token_list, MsToken)
MS_LIST_DEFINE(FlagList, flag_list, bool)
MS_LIST_DEFINE(IndexList, index_list, size_t)

/* ---- text ---- */

static inline MsSpan fmt_slice(MsSpan s, size_t from, size_t to) {
  return ms_span_of(s.ptr + from, to - from);
}

static inline bool fmt_eq(MsSpan a, MsSpan b) {
  return ms_span_equal(a, b);
}

static inline bool fmt_is(MsSpan s, const char *text) {
  return ms_span_is_text(s, text);
}

static inline bool fmt_starts(MsSpan s, const char *prefix) {
  return ms_span_starts_with(s, ms_span_of_text(prefix));
}

static inline bool fmt_ends(MsSpan s, const char *suffix) {
  return ms_span_ends_with(s, ms_span_of_text(suffix));
}

/* Bytewise order: negative, zero or positive. */
static inline int fmt_compare(MsSpan a, MsSpan b) {
  size_t common = a.len < b.len ? a.len : b.len;
  for (size_t index = 0; index < common; index++) {
    if (a.ptr[index] != b.ptr[index]) {
      return a.ptr[index] < b.ptr[index] ? -1 : 1;
    }
  }
  return a.len == b.len ? 0 : (a.len < b.len ? -1 : 1);
}

/* The offset of the first `needle` in `hay` (an empty needle matches at 0), or FMT_NONE. */
static inline size_t fmt_find(MsSpan hay, MsSpan needle) {
  return ms_find(hay.ptr, hay.len, needle.ptr, needle.len);
}

static inline bool fmt_contains(MsSpan hay, const char *needle) {
  return fmt_find(hay, ms_span_of_text(needle)) != FMT_NONE;
}

static inline size_t fmt_find_byte(MsSpan s, uint8_t byte) {
  return ms_find(s.ptr, s.len, &byte, 1);
}

/* The offset of the last `byte`, or FMT_NONE. */
static inline size_t fmt_rfind_byte(MsSpan s, uint8_t byte) {
  return ms_rfind(s.ptr, s.len, &byte, 1);
}

/* ---- scalars ---- */

/* Scalars in the text, as Rust's `chars().count()`. */
static inline size_t fmt_chars(MsSpan s) {
  size_t count = 0;
  for (size_t index = 0; index < s.len; index++) {
    count += !ms_utf8_is_continuation(s.ptr[index]);
  }
  return count;
}

/* The scalar at byte `at` of valid UTF-8 and its width. */
static inline size_t fmt_scalar_at(MsSpan s, size_t at, uint32_t *scalar) {
  MsRune rune = ms_utf8_decode(s.ptr + at, s.len - at);
  *scalar = rune.rune;
  return rune.width;
}

/* The scalar that ends at byte `to` and its width. */
static inline size_t fmt_scalar_before(MsSpan s, size_t to, uint32_t *scalar) {
  size_t from = to - 1;
  while (from > 0 && ms_utf8_is_continuation(s.ptr[from])) {
    from--;
  }
  *scalar = ms_utf8_decode(s.ptr + from, to - from).rune;
  return to - from;
}

static inline bool fmt_in_set(uint8_t byte, const char *set) {
  MsSpan members = ms_span_of_text(set);
  return byte != 0 && ms_find(members.ptr, members.len, &byte, 1) != SIZE_MAX;
}

/* Rust's `trim_start_matches` and `trim_end_matches` over a set of ASCII characters. */
static inline MsSpan fmt_trim_start_set(MsSpan s, const char *set) {
  size_t from = 0;
  while (from < s.len && fmt_in_set(s.ptr[from], set)) {
    from++;
  }
  return fmt_slice(s, from, s.len);
}

static inline MsSpan fmt_trim_end_set(MsSpan s, const char *set) {
  size_t to = s.len;
  while (to > 0 && fmt_in_set(s.ptr[to - 1], set)) {
    to--;
  }
  return fmt_slice(s, 0, to);
}

/* Rust's `trim_start`, `trim_end` and `trim`: Unicode White_Space. */
static inline MsSpan fmt_trim_start(MsSpan s) {
  size_t from = 0;
  while (from < s.len) {
    uint32_t scalar = 0;
    size_t width = fmt_scalar_at(s, from, &scalar);
    if (!ms_utf8_is_space(scalar)) {
      break;
    }
    from += width;
  }
  return fmt_slice(s, from, s.len);
}

static inline MsSpan fmt_trim_end(MsSpan s) {
  size_t to = s.len;
  while (to > 0) {
    uint32_t scalar = 0;
    size_t width = fmt_scalar_before(s, to, &scalar);
    if (!ms_utf8_is_space(scalar)) {
      break;
    }
    to -= width;
  }
  return fmt_slice(s, 0, to);
}

static inline MsSpan fmt_trim(MsSpan s) {
  return fmt_trim_end(fmt_trim_start(s));
}

static inline bool fmt_is_blank(MsSpan s) {
  return fmt_trim(s).len == 0;
}

/* Leading spaces of a line. */
static inline size_t fmt_indent_of(MsSpan line) {
  return line.len - fmt_trim_start_set(line, " ").len;
}

/* ---- building strings ---- */

/* A copy of `s` in the arena. */
static inline MsSpan fmt_copy(Fmt *f, MsSpan s) {
  return ms_arena_copy(f->arena, s);
}

/* The builder's text moved into the arena; the builder is freed. */
static inline MsSpan fmt_take(Fmt *f, MsStrBuild *builder) {
  MsSpan text = fmt_copy(f, ms_strbuild_span(builder));
  ms_strbuild_free(builder);
  return text;
}

static inline void fmt_put(MsStrBuild *builder, MsSpan s) {
  ms_strbuild_append(builder, s);
}

static inline void fmt_spaces(MsStrBuild *builder, size_t count) {
  for (size_t index = 0; index < count; index++) {
    ms_strbuild_append_byte(builder, ' ');
  }
}

/* The bytes of the builder after offset `from`. */
static inline MsSpan fmt_tail(const MsStrBuild *builder, size_t from) {
  MsSpan all = ms_strbuild_span(builder);
  return ms_span_of(all.ptr + from, all.len - from);
}

/* ---- tokens ---- */

static inline bool fmt_layout_token(MsTok kind) {
  return kind == MS_T_Newline || kind == MS_T_Eof;
}

static inline MsSpan fmt_token_text(MsSpan source, const MsToken *t) {
  return fmt_slice(source, t->lo, t->hi);
}

static inline bool fmt_is_comparison(MsTok k) {
  return k == MS_T_EqEq || k == MS_T_NotEq || k == MS_T_Lt || k == MS_T_Gt || k == MS_T_Le || k == MS_T_Ge;
}

static inline bool fmt_is_arith(MsTok k) {
  return k == MS_T_Plus || k == MS_T_Minus || k == MS_T_Star || k == MS_T_Slash || k == MS_T_Percent;
}

static inline bool fmt_is_open(MsTok k) {
  return k == MS_T_LParen || k == MS_T_LBracket || k == MS_T_LBrace;
}

/* Whether a space separates `tokens[at - 1]` and `tokens[at]` on one line of code. */
bool fmt_token_space(const MsToken *tokens, size_t at);

/* ---- parsing and lexing ---- */

/* Copies the text of a diagnostic out of the scratch arena that is about to be freed. */
static inline bool fmt_failed(Fmt *f) {
  f->diag.message = fmt_copy(f, f->diag.message);
  f->diag.replacement = fmt_copy(f, f->diag.replacement);
  return false;
}

/* Parses `source` into `module`, whose nodes live in `scratch`. False with f->diag filled on error. */
static inline bool fmt_parse(Fmt *f, MsArena *scratch, MsSpan source, MsModule *module) {
  (void)scratch; /* the result lives in f->memo, which outlives every pass; the module is read-only */
  FmtParsed *entry = fmt_parsed_entry(f, source);
  if (!entry->has_module) {
    if (!ms_parse(&f->memo, f->names, entry->text, &entry->module, &f->diag)) {
      return fmt_failed(f);
    }
    entry->has_module = true;
  }
  *module = entry->module;
  return true;
}

static inline bool fmt_lex(Fmt *f, MsArena *scratch, MsSpan source, MsLexed *lexed) {
  (void)scratch;
  FmtParsed *entry = fmt_parsed_entry(f, source);
  if (!entry->has_lexed) {
    if (!ms_lex(&f->memo, entry->text, &entry->lexed, &f->diag)) {
      return fmt_failed(f);
    }
    entry->has_lexed = true;
  }
  *lexed = entry->lexed;
  return true;
}

/* ---- syntax helpers shared by the passes ---- */

/* The statements of a lambda body without the bindings the parser made for destructured parameters. */
MsStmts fmt_written_body(const MsExpr *lambda);
/* A lambda whose body is a suite of several statements. */
bool fmt_block_lambda(const MsExpr *e);
/* The statement's value expression, or NULL. */
const MsExpr *fmt_statement_value(const MsStmt *s);
/* A lambda or a written match, seen through prefix operators. */
bool fmt_suite_expression(const MsExpr *e);
/* A written `match`, not the Bool match an `if` expression stands for. */
bool fmt_is_written_match(const MsExpr *e);
/* Whether the parser made this binding for a destructuring `for` or lambda parameter. */
bool fmt_is_destructure_head(const MsStmt *s);

/* ---- edits ---- */

/* A source edit: replace [from, to) with `text`. */
typedef struct FmtEdit {
  size_t from, to;
  MsSpan text;
} FmtEdit;
MS_LIST_DEFINE(EditList, edit_list, FmtEdit)

/* The source with source-ordered, nonoverlapping edits applied. */
MsSpan fmt_apply_edits(Fmt *f, MsSpan source, const FmtEdit *edits, size_t count);
/* Drops the `Error` of each written `T!Error`: `T!` already means that. False when there is none. */
bool fmt_drop_default_error(Fmt *f, const MsModule *module, MsSpan text, MsSpan *out);

/* ---- passes ---- */

/* Statement compaction (format_compact.c): the compacted source, or false when nothing changes. */
bool fmt_compact(Fmt *f, const MsModule *module, MsSpan source, MsSpan *out);
/* Expression layout (format_layout.c). False with f->diag filled when the text stops parsing. */
bool fmt_expression_layout(Fmt *f, MsSpan source, MsSpan *out);

/* ---- shared by the formatter files ---- */

bool fmt_lines(Fmt *f, MsSpan source, MsSpan *out);
bool fmt_once(Fmt *f, MsSpan source, MsSpan *out);
MsSpan fmt_normalize(Fmt *f, MsSpan text);
size_t fmt_split_lines(MsSpan text, SpanList *lines);
MsSpan fmt_join_lines(Fmt *f, const MsSpan *lines, size_t count);
int fmt_import_section(MsSpan path);
bool fmt_group_imports(Fmt *f, MsSpan source, const MsToken *tokens, size_t ntokens, MsSpan *out);
bool fmt_wrap_import(Fmt *f, const MsToken *parts, size_t nparts, MsSpan flat, MsSpan source, MsSpan *out);
void fmt_wrap_comments(Fmt *f, const MsSpan *lines, size_t count, SpanList *out);
bool fmt_normalize_blocks(Fmt *f, MsSpan text, const MsToken *tokens, size_t ntokens, MsSpan *out);
/* Joins neighbouring fields, parameters and payload names that share a type: `width, height Int`. */
bool fmt_group_names(Fmt *f, MsSpan text, const MsToken *tokens, size_t ntokens, MsSpan *out);
bool fmt_align_suite_headers(Fmt *f, const MsSpan *lines, size_t nlines, const MsToken *tokens,
                             size_t ntokens, SpanList *out);

#endif
