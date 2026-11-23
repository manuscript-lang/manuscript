/* Owns the lexer entry points: input checks, the line loop and the exported token arrays. */
#include <stdlib.h>
#include "base/fatal.h"
#include "base/sort.h"

#include "compiler/syntax/lex_internal.h"

/* ---- end of a line ---- */

static bool function_open_at_depth(const Scanner *s) {
  for (size_t i = 0; i < s->function_depths.len; i++) {
    if (s->function_depths.ptr[i] == lex_open_delimiters(s)) {
      return true;
    }
  }
  return false;
}

/* The wrapper's closing parenthesis ends an interpolation's tokens. */
static bool close_virtual_paren(Scanner *s) {
  if (!s->virtual_paren || s->offset != s->n) {
    return true;
  }
  if (!(lex_open_delimiters(s) == 1 && s->delimiters.ptr[0] == '(')) {
    /* The wrapper's closing parenthesis reports this error. */
    return lex_fail(s, ms_span_of_text("interpolation leaves a delimiter open"));
  }
  s->delimiters.len--;
  s->opened.len--;
  s->groups.len = 0;
  s->function_depths.len = 0;
  lex_emit_layout(s, MS_T_RParen);
  return true;
}

/* Ends the line: it opens a suite (`:`), continues (`.` or `|` next), or ends its statement. */
static void end_line(Scanner *s, LineLayout *layout, const LineInfo *info, size_t line_start,
                     size_t leading) {
  if (lex_token_count(s) <= line_start) {
    return;
  }
  if (lex_last_kind(s) == MS_T_Colon &&
      (lex_open_delimiters(s) == info->top_depth || function_open_at_depth(s))) {
    layout->pending = true;
    layout->header_indent = leading;
    layout->header_start = layout->statement_indent;
    layout->pending_depth = lex_open_delimiters(s);
    lex_emit_layout(s, MS_T_Newline);
    s->function_depths.len = 0;
  } else if (lex_open_delimiters(s) == info->top_depth) {
    s->function_depths.len = 0;
    if (lex_continues_next(s)) {
      layout->continuing = true;
    } else {
      lex_emit_layout(s, MS_T_Newline);
    }
  } else if (s->groups.len != 0 && s->groups.ptr[s->groups.len - 1] == lex_open_delimiters(s)) {
    /* A `var (` group holds one binding per line, so its lines end like statements even
     * though a delimiter is open. */
    lex_emit_layout(s, MS_T_Newline);
  }
}

static bool fail_unterminated_delimiter(Scanner *s) {
  uint8_t open = s->delimiters.ptr[s->delimiters.len - 1];
  MsPos opener = s->opened.ptr[s->opened.len - 1];
  MsSpan message = ms_message_format(
      s->arena,
      "unterminated delimiter '%c' opened at line %u:%u; add the matching '%c' before the end of the file",
      open, opener.line, opener.column, lex_closer_of(open));
  lex_new_diag(s, lex_pos(s), message)->opener_line = opener.line;
  return false;
}

static bool finish_input(Scanner *s, const LineLayout *layout) {
  if (layout->pending) {
    lex_emit_layout(s, MS_T_Indent);
    lex_emit_layout(s, MS_T_Dedent);
  }
  if (lex_open_delimiters(s) != 0) {
    return fail_unterminated_delimiter(s);
  }
  while (s->levels.len > 1) {
    s->levels.len--;
    lex_emit_layout(s, MS_T_Dedent);
  }
  lex_emit_layout(s, MS_T_Eof);
  return true;
}

/* Scans the whole source. Returns false with the diagnostic in s->diag on the first error. */
MS_NODISCARD static bool run(Scanner *s) {
  LineLayout layout = {0};
  while (s->offset < s->n) {
    size_t leading = 0;
    if (!lex_read_leading_space(s, &leading)) {
      return false;
    }
    if (s->offset == s->n) {
      break;
    }
    bool skipped = false;
    if (!lex_skip_blank_line(s, &skipped)) {
      return false;
    }
    if (skipped) {
      continue;
    }
    if (!lex_apply_layout(s, &layout, leading)) {
      return false;
    }
    Level top = s->levels.ptr[s->levels.len - 1];
    LineInfo info = {.leading = leading, .top_indent = top.indent, .top_depth = top.depth};
    if (lex_token_count(s) != 0 && lex_last_kind(s) == MS_T_Dedent && lex_open_delimiters(s) == top.depth) {
      lex_emit_layout(s, MS_T_Newline);
    }
    size_t line_start = lex_token_count(s);
    if (!lex_scan_line_tokens(s, &info) || !close_virtual_paren(s)) {
      return false;
    }
    end_line(s, &layout, &info, line_start, leading);
    if (s->offset < s->n) {
      lex_advance(s);
    }
  }
  return finish_input(s, &layout);
}

/* ---- entry points ---- */

void lex_scanner_init(Scanner *s, MsArena *arena, MsSpan text, const uint32_t *line_offsets, MsDiag *diag) {
  *s = (Scanner){.arena = arena,
                 .src = text.ptr,
                 .n = text.len,
                 .line = 1,
                 .column = 1,
                 .line_offsets = line_offsets,
                 .diag = diag};
  level_list_push(&s->levels, (Level){0, 0});
  token_list_reserve(&s->tokens, text.len / 4 + 8); /* about one token per four source bytes */
}

void lex_scanner_free(Scanner *s) {
  token_list_free(&s->tokens);
  level_list_free(&s->levels);
  byte_list_free(&s->delimiters);
  size_list_free(&s->groups);
  pos_list_free(&s->opened);
  size_list_free(&s->function_depths);
  pos_list_free(&s->interpolations);
  range_list_free(&s->strings);
  range_list_free(&s->interps);
  range_list_free(&s->blocks);
}

static int64_t compare_ranges(uint8_t *env, const uint8_t *left, const uint8_t *right) {
  (void)env;
  const MsByteRange *a = (const void *)left;
  const MsByteRange *b = (const void *)right;
  size_t x = a->start;
  size_t y = b->start;
  return x < y ? -1 : x > y;
}

static void sort_ranges(RangeList *ranges) {
  if (ranges->len != 0) {
    ms_sort((uint8_t *)ranges->ptr, ranges->len, sizeof(MsByteRange), compare_ranges, NULL);
  }
}

static bool has_crlf(MsSpan source) {
  for (const uint8_t *at = __builtin_memchr(source.ptr, '\r', source.len); at != NULL;
       at = __builtin_memchr(at + 1, '\r', (size_t)(source.ptr + source.len - (at + 1)))) {
    if (at + 1 < source.ptr + source.len && at[1] == '\n') {
      return true;
    }
  }
  return false;
}

static size_t count_newlines(MsSpan source) {
  size_t count = 0;
  for (size_t index = 0; index < source.len; index++) {
    count += source.ptr[index] == '\n';
  }
  return count;
}

/* Replaces CRLF with LF and records, per normalised line, how many CR bytes precede it. The result is
 * `source` itself, with no offsets, when the source has no CRLF. */
MsSpan lex_normalize(MsArena *arena, MsSpan source, const uint32_t **offsets) {
  *offsets = NULL;
  if (!has_crlf(source)) {
    return source;
  }
  uint8_t *destination = ms_arena_alloc(arena, source.len + 1, 1);
  uint32_t *line_offsets = MS_ARENA_NEW_ARRAY(arena, uint32_t, count_newlines(source) + 1);
  size_t written = 0;
  size_t lines = 1;
  uint32_t removed = 0;
  for (size_t index = 0; index < source.len; index++) {
    uint8_t byte = source.ptr[index];
    if (byte == '\r' && index + 1 < source.len && source.ptr[index + 1] == '\n') {
      continue; /* the LF follows */
    }
    destination[written++] = byte;
    if (byte == '\n') {
      removed += index > 0 && source.ptr[index - 1] == '\r';
      line_offsets[lines++] = removed;
    }
  }
  destination[written] = 0;
  *offsets = line_offsets;
  return ms_span_of(destination, written);
}

/* Copies a scratch list into the arena; the result is never NULL. */
static void *copy_out(MsArena *arena, const void *items, size_t count, size_t size, size_t alignment) {
  size_t bytes = 0;
  if (!ms_size_mul(count, size, &bytes)) {
    ms_fatal(MS_FATAL_OVERFLOW, "lexer output size overflows");
  }
  void *copy = ms_arena_alloc(arena, bytes == 0 ? 1 : bytes, alignment);
  if (bytes != 0) {
    __builtin_memcpy(copy, items, bytes);
  }
  return copy;
}

static void export_lexed(Scanner *s, const uint32_t *offsets, MsLexed *out) {
  sort_ranges(&s->strings);
  sort_ranges(&s->interps);
  out->source = ms_span_of(s->src, s->n);
  out->tokens = copy_out(s->arena, s->tokens.ptr, s->tokens.len, sizeof(MsToken), _Alignof(MsToken));
  out->ntokens = s->tokens.len;
  out->blocks = copy_out(s->arena, s->blocks.ptr, s->blocks.len, sizeof(MsByteRange), _Alignof(MsByteRange));
  out->nblocks = s->blocks.len;
  out->bounds.strings =
      copy_out(s->arena, s->strings.ptr, s->strings.len, sizeof(MsByteRange), _Alignof(MsByteRange));
  out->bounds.nstrings = s->strings.len;
  out->bounds.interps =
      copy_out(s->arena, s->interps.ptr, s->interps.len, sizeof(MsByteRange), _Alignof(MsByteRange));
  out->bounds.ninterps = s->interps.len;
  out->bounds.line_offsets = offsets;
}

static bool fail_source(MsDiag *diag, MsPos pos, const char *message) {
  *diag = (MsDiag){.pos = pos, .message = ms_span_of_text(message)};
  return false;
}

bool ms_lex(MsArena *arena, MsSpan source, MsLexed *out, MsDiag *diag) {
  return ms_lex_at(arena, source, 0, 0, out, diag);
}

bool ms_lex_at(MsArena *arena, MsSpan source, uint32_t base_offset, uint32_t base_line, MsLexed *out,
               MsDiag *diag) {
  *out = (MsLexed){0};
  MsPos origin = {base_offset, base_line + 1, 1};
  if (!ms_utf8_is_valid(source.ptr, source.len)) {
    return fail_source(diag, origin,
                       "source must be valid UTF-8; re-save the file with UTF-8 encoding");
  }
  if (ms_span_starts_with(source, ms_span_of_text("\xEF\xBB\xBF"))) {
    return fail_source(diag, origin,
                       "a byte-order mark is not allowed; save the file as UTF-8 without BOM");
  }
  const uint32_t *offsets = NULL;
  MsSpan text = lex_normalize(arena, source, &offsets);
  Scanner s;
  lex_scanner_init(&s, arena, text, offsets, diag);
  s.base_offset = base_offset;
  s.base_line = base_line;
  s.line = base_line + 1;
  bool ok = run(&s);
  if (ok) {
    export_lexed(&s, offsets, out);
    out->bounds.base_line = base_line;
  }
  lex_scanner_free(&s);
  return ok;
}

bool ms_lex_interpolation(MsArena *arena, MsSpan source, size_t origin, const MsBounds *bounds,
                          MsToken **tokens, size_t *count, MsDiag *diag) {
  Scanner s;
  lex_scanner_init(&s, arena, source, NULL, diag);
  s.cached = bounds;
  s.boundary_origin = origin;
  s.virtual_paren = true;
  byte_list_push(&s.delimiters, '(');
  pos_list_push(&s.opened, (MsPos){0, 1, 1});
  if (!run(&s)) {
    lex_scanner_free(&s);
    return false;
  }
  /* Drop the wrapper's closing parenthesis: it sits just before Newline and Eof. */
  size_t closing = s.tokens.len - 3;
  __builtin_memmove(&s.tokens.ptr[closing], &s.tokens.ptr[closing + 1],
                    (s.tokens.len - closing - 1) * sizeof(MsToken));
  s.tokens.len--;
  *tokens = copy_out(arena, s.tokens.ptr, s.tokens.len, sizeof(MsToken), _Alignof(MsToken));
  *count = s.tokens.len;
  lex_scanner_free(&s);
  return true;
}
