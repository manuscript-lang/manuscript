/* Owns text literals: escapes, multi-line dedent and interpolation. */
#include "base/search.h"
#include "compiler/syntax/parse_internal.h"

/* ---- text ---- */

static MsPos text_pos(MsPos pos, MsSpan full, size_t index, const MsBounds *bounds) {
  size_t last = (size_t)-1;
  uint32_t newline_count = 0;
  for (size_t i = 0; i < index; i++) {
    if (full.ptr[i] == '\n') {
      last = i;
      newline_count++;
    }
  }
  uint32_t offset = (uint32_t)(pos.offset + index);
  MsPos position;
  if (last == (size_t)-1) {
    position = (MsPos){offset, pos.line, (uint32_t)(pos.column + index)};
  } else {
    position = (MsPos){offset, pos.line + newline_count, (uint32_t)(index - last)};
  }
  return ms_bounds_restore_offset(bounds, pos, position);
}

/* Splits the text between multi-line delimiters into its content (without the line break after the
 * opening quotes and the closing line), the closing line's indentation width, and the content's
 * start within `body`. */
static void multiline_body(MsSpan body, MsSpan *content, size_t *indent, size_t *first) {
  size_t last = 0;
  for (size_t i = body.len; i > 0; i--) {
    if (body.ptr[i - 1] == '\n') {
      last = i - 1;
      break;
    }
  }
  *indent = body.len - last - 1;
  size_t f = last < 1 ? last : 1;
  content->ptr = body.ptr + f;
  content->len = (uint32_t)(last - f);
  *first = f;
}

/* Removes up to `indent` leading blanks from every line of `content`. */
static MsSpan parse_dedent(Parser *p, MsSpan content, size_t indent) {
  size_t bm = p->bytes->len;
  size_t i = 0;
  bool line_begin = true;
  while (i < content.len) {
    if (line_begin) {
      size_t blanks = 0;
      while (blanks < indent && i < content.len && (content.ptr[i] == ' ' || content.ptr[i] == '\t')) {
        blanks++;
        i++;
      }
      line_begin = false;
      continue;
    }
    uint8_t c = content.ptr[i++];
    parse_bytes_byte(p, c);
    if (c == '\n') {
      line_begin = true;
    }
  }
  return parse_bytes_take(p, bm);
}

MS_NODISCARD static bool interpolation(Parser *p, MsToken token, size_t at, MsSpan source, MsPos position,
                                       MsExpr **out);

/* Where text_parts stands in the raw text and in the literal it is building. */
typedef struct TextCursor {
  const uint8_t *raw;
  size_t at;     /* next byte of the raw text */
  size_t stop;   /* end of the content */
  size_t indent; /* indentation removed from each line of multi-line text */
  size_t bytes;  /* start of the literal being built, on the byte stack */
  bool line_start;
} TextCursor;

/* Turns the literal bytes built so far into a part and pushes it. */
static void flush_literal(Parser *p, size_t literal_start) {
  if (p->bytes->len == literal_start) {
    return;
  }
  MsTextPart part = {parse_bytes_take(p, literal_start), NULL};
  parse_push(p, &part, sizeof part);
}

/* Appends the character an escape stands for; the cursor is after the backslash. */
static void append_escape(Parser *p, TextCursor *c) {
  uint8_t escape = c->raw[c->at++];
  switch (escape) {
  case 'n':
    parse_bytes_byte(p, '\n');
    return;
  case 'r':
    parse_bytes_byte(p, '\r');
    return;
  case 't':
    parse_bytes_byte(p, '\t');
    return;
  case 'u':
    break;
  default:
    parse_bytes_byte(p, escape);
    return;
  }
  size_t digits = c->at + 1; /* after the '{' */
  c->at = digits;
  while (c->raw[c->at] != '}') {
    c->at++;
  }
  uint32_t scalar = 0;
  for (size_t k = digits; k < c->at; k++) {
    uint8_t h = c->raw[k];
    uint32_t digit = 0;
    if (ms_hex_digit_value(h, &digit)) { /* the lexer admitted only hex digits */
      scalar = scalar * 16 + digit;
    }
  }
  uint8_t encoded[4];
  size_t width = ms_utf8_encode(scalar, encoded);
  parse_bytes_append(p, ms_span_of(encoded, width));
  c->at++;
}

/* Consumes `{expr}` (the cursor is after the brace) and parses it. */
MS_NODISCARD static bool text_interpolation(Parser *p, MsToken token, MsSpan raw, size_t quotes,
                                            TextCursor *c, MsPos *position, size_t *positioned) {
  size_t start = c->at;
  size_t brace = p->source_origin + token.lo + quotes + start - 1;
  size_t close = ms_bounds_interp_end(p->bounds, brace);
  c->at = close - (p->source_origin + token.lo + quotes);
  MsSpan source = {raw.ptr + start, (uint32_t)(c->at - 1 - start)};
  /* Advance through each prefix once, including physical lines in multiline text. */
  size_t at = quotes + start;
  MsSpan full = parse_text(p, token);
  MsSpan rest = {full.ptr + *positioned, (uint32_t)(full.len - *positioned)};
  *position = text_pos(*position, rest, at - *positioned, p->bounds);
  *positioned = at;
  MsExpr *value = NULL;
  if (!interpolation(p, token, at, source, *position, &value))
    return false;
  MsTextPart part = {{NULL, 0}, value};
  parse_push(p, &part, sizeof part);
  return true;
}

/* Skips the indentation a multi-line text's closing line removes from each content line. */
static void skip_text_indent(TextCursor *c) {
  size_t skipped = 0;
  while (skipped < c->indent && c->at < c->stop && (c->raw[c->at] == ' ' || c->raw[c->at] == '\t')) {
    skipped++;
    c->at++;
  }
}

MS_NODISCARD static bool text_parts(Parser *p, MsToken token, MsSpan raw, size_t quotes, bool interpolating,
                                    TextParts *out) {
  TextCursor c = {.raw = (const uint8_t *)raw.ptr, .stop = raw.len};
  if (quotes >= 3) {
    MsSpan content;
    multiline_body(raw, &content, &c.indent, &c.at);
    c.stop = c.at + content.len;
  }
  size_t parts_start = parse_mark(p); /* parts, on the scratch stack */
  c.bytes = p->bytes->len;
  c.line_start = c.indent > 0;
  size_t positioned = 0;
  MsPos position = token.pos;
  while (c.at < c.stop) {
    if (c.line_start) {
      c.line_start = false;
      skip_text_indent(&c);
      continue;
    }
    uint8_t b = c.raw[c.at++];
    if (b == '\\') {
      append_escape(p, &c);
    } else if (interpolating && b == '{') {
      flush_literal(p, c.bytes);
      if (!text_interpolation(p, token, raw, quotes, &c, &position, &positioned))
        return false;
    } else {
      parse_bytes_byte(p, b);
      c.line_start = b == '\n' && c.indent > 0;
    }
  }
  flush_literal(p, c.bytes);
  TextParts result;
  result.ptr = parse_finish(p, parts_start, &result.len, sizeof(MsTextPart), _Alignof(MsTextPart));
  if (result.len == 0) {
    result.ptr = MS_ARENA_NEW_ARRAY(p->arena, MsTextPart, 1);
    result.ptr[0].lit = ms_span_of_text("");
    result.len = 1;
  }
  *out = result;
  return true;
}

static TextParts one_literal(Parser *p, MsSpan s) {
  TextParts out = {MS_ARENA_NEW_ARRAY(p->arena, MsTextPart, 1), 1};
  out.ptr[0].lit = s;
  out.ptr[0].expr = NULL;
  return out;
}

/* Decodes a text token into literal and interpolated parts. Only `f"..."` and `f"""` text
 * interpolates; braces are plain in the other forms. */
MS_NODISCARD bool parse_text_parts_of(Parser *p, MsToken token, TextParts *out) {
  MsSpan full = parse_text(p, token);
  if (ms_span_starts_with(full, ms_span_of_text("r\"\"\""))) {
    MsSpan body = {full.ptr + 4, full.len - 4 - 3};
    MsSpan content;
    size_t indent, f;
    multiline_body(body, &content, &indent, &f);
    *out = one_literal(p, parse_dedent(p, content, indent));
    return true;
  }
  if (ms_span_starts_with(full, ms_span_of_text("f\"\"\""))) {
    MsSpan body = {full.ptr + 4, full.len - 4 - 3};
    return text_parts(p, token, body, 4, true, out);
  }
  if (ms_span_starts_with(full, ms_span_of_text("\"\"\""))) {
    MsSpan body = {full.ptr + 3, full.len - 6};
    return text_parts(p, token, body, 3, false, out);
  }
  if (ms_span_starts_with(full, ms_span_of_text("r\""))) {
    *out = one_literal(p, (MsSpan){full.ptr + 2, full.len - 3});
    return true;
  }
  if (ms_span_starts_with(full, ms_span_of_text("f\""))) {
    MsSpan body = {full.ptr + 2, full.len - 3};
    return text_parts(p, token, body, 2, true, out);
  }
  MsSpan raw = {full.ptr + 1, full.len - 2};
  size_t backslash = ms_find(raw.ptr, raw.len, (const uint8_t *)"\\", 1);
  if (backslash == SIZE_MAX) {
    *out = one_literal(p, raw);
    return true;
  }
  return text_parts(p, token, raw, 1, false, out);
}

static MsSpan append_suffix(Parser *p, MsSpan message, MsSpan suffix) {
  MsSpan parts[] = {message, suffix};
  return ms_message_join(p->arena, parts, MS_COUNT_OF(parts));
}

static void parser_init_nested(Parser *n, const Parser *p, MsSpan src, const MsToken *tokens, size_t ntokens,
                               size_t origin) {
  __builtin_memset(n, 0, sizeof *n);
  n->arena = p->arena;
  n->names = p->names;
  n->source = src;
  n->tokens = tokens;
  n->ntokens = ntokens;
  n->bounds = p->bounds;
  n->source_origin = origin;
  n->depth = p->depth;
  n->next_id = p->next_id;
  n->scratch = p->scratch;
  n->bytes = p->bytes;
  n->diag = p->diag;
  n->type_brackets = parse_compute_type_brackets(p->arena, tokens, ntokens);
}

/* Parses the one expression of an interpolation with a nested parser; on failure appends `suffix`
 * to the message and rethrows into `p`. `eof_by_need` makes the final check `parse_need(Eof)`. */
MS_NODISCARD static bool nested_body(Parser *n, bool eof_by_need, MsExpr **out) {
  if (!parse_expression(n, 0, out))
    return false;
  parse_newlines(n);
  if (eof_by_need) {
    return parse_need(n, MS_T_Eof);
  }
  if (parse_kind(n) != MS_T_Eof) {
    MsToken at = parse_peek(n);
    MsSpan found = parse_describe(n, at);
    parse_fail(n, at,
               parse_fmt(n,
                         "an interpolation holds one expression, found %S after it; close the brace after "
                         "the expression, or bind the rest to a name first",
                         found));
    return false;
  }
  return true;
}

MS_NODISCARD static bool nested_expression(Parser *p, Parser *n, MsSpan suffix, MsSpan source,
                                           bool eof_by_need, MsExpr **out) {
  (void)source;
  size_t scratch = n->scratch->len;
  size_t bytes = n->bytes->len;
  MsExpr *value = NULL;
  bool ok = nested_body(n, eof_by_need, &value);
  p->next_id = n->next_id;
  if (ok) {
    *out = value;
    return true;
  }
  p->diag->message = append_suffix(p, p->diag->message, suffix);
  p->scratch->len = scratch;
  p->bytes->len = bytes;
  return false;
}

/* Maps a position in the parenthesised copy of an interpolation back to the text it came from. */
static MsPos shift_position(const Parser *p, MsToken token, size_t at, size_t source_length, MsPos point) {
  MsSpan full = parse_text(p, token);
  uint32_t limit = (uint32_t)source_length + 1;
  return text_pos(token.pos, full, at - 1 + (point.offset < limit ? point.offset : limit), p->bounds);
}

/* The wrapper path for an expression whose lexical error depends on its physical closing
 * parenthesis. */
MS_NODISCARD static bool interpolation_wrapped(Parser *p, MsToken token, size_t at, MsSpan source,
                                               MsExpr **out) {
  MsSpan full = parse_text(p, token);
  MsPos open_pos = text_pos(token.pos, full, at - 1, p->bounds);
  MsSpan suffix = parse_fmt(p,
                            " ('{' at column %u starts an interpolation in f\"...\" text; write \\{ and \\} "
                            "for literal braces, or drop the f)",
                            open_pos.column);
  MsSpan wrapped = ms_message_format(p->arena, "(%S)", source);
  MsLexed lexed;
  MsDiag ld;
  if (!ms_lex(p->arena, wrapped, &lexed, &ld)) {
    ld.pos = shift_position(p, token, at, source.len, ld.pos);
    if (ld.has_end) {
      ld.end = shift_position(p, token, at, source.len, ld.end);
    }
    if (ld.has_fix) {
      ld.fix_pos = shift_position(p, token, at, source.len, ld.fix_pos);
      ld.fix_end = shift_position(p, token, at, source.len, ld.fix_end);
    }
    ld.message = append_suffix(p, ld.message, suffix);
    *p->diag = ld;
    return false;
  }
  size_t closing = lexed.ntokens - 3;
  MsToken *toks = lexed.tokens;
  __builtin_memmove(toks + closing, toks + closing + 1, (lexed.ntokens - closing - 1) * sizeof(MsToken));
  size_t nt = lexed.ntokens - 1;
  __builtin_memmove(toks, toks + 1, (nt - 1) * sizeof(MsToken));
  nt--;
  for (size_t k = 0; k < nt; k++) {
    toks[k].pos = shift_position(p, token, at, source.len, toks[k].pos);
    toks[k].end = shift_position(p, token, at, source.len, toks[k].end);
  }
  size_t origin = p->source_origin + token.lo + at - 1;
  Parser n;
  parser_init_nested(&n, p, lexed.source, toks, nt, origin);
  return nested_expression(p, &n, suffix, source, true, out);
}

/* Lexes and parses the expression inside one `{...}` of `f` text. */
MS_NODISCARD static bool interpolation(Parser *p, MsToken token, size_t at, MsSpan source, MsPos position,
                                       MsExpr **out) {
  MsSpan suffix = parse_fmt(p,
                            " ('{' at column %u starts an interpolation in f\"...\" text; write \\{ and \\} "
                            "for literal braces, or drop the f)",
                            position.column - 1);
  size_t origin = p->source_origin + token.lo + at;
  MsToken *tokens;
  size_t nt;
  MsDiag ld;
  if (!ms_lex_interpolation(p->arena, source, origin, p->bounds, &tokens, &nt, &ld)) {
    return interpolation_wrapped(p, token, at, source, out);
  }
  /* The lexer rejects physical newlines inside an interpolation, so each token maps from its
   * relative byte offset. */
  for (size_t k = 0; k < nt; k++) {
    MsPos *ps[2] = {&tokens[k].pos, &tokens[k].end};
    for (int j = 0; j < 2; j++) {
      uint32_t off = ps[j]->offset < source.len ? ps[j]->offset : (uint32_t)source.len;
      *ps[j] = (MsPos){position.offset + off, position.line, position.column + off};
    }
  }
  Parser n;
  parser_init_nested(&n, p, source, tokens, nt, origin);
  return nested_expression(p, &n, suffix, source, false, out);
}
