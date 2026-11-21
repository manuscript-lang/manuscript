/* Owns the scanning of text literals: escapes, interpolation, one-line and multi-line text. */
#include "compiler/syntax/lex_internal.h"

#include "base/chars.h"
#include "base/search.h"
#include "base/utf8.h"

enum { MAX_INTERPOLATION_DEPTH = 1000 };

static const char TEXT_BIDI[] =
    "bidirectional text controls (U+202A..U+202E, U+2066..U+2069) are not allowed in text because they can "
    "make source display differently from how it is read; write the escape instead, e.g. \\u{202E}";
static const char BRACE_HINT[] =
    "'{' starts an interpolation in f\"...\" text; write \\{ and \\} for literal braces, or drop the f";
static const char TEXT_UNMATCHED_BRACE[] = "an unmatched closing brace must be escaped in f\"...\" text; "
                                           "write \\} for a literal brace (and \\{ for the "
                                           "opening brace), or drop the f so braces are plain";
static const char TEXT_PLAIN_BRACE[] =
    "braces are plain characters in \"...\" text, so write { and } without a backslash; only f\"...\" text "
    "interpolates and escapes them";

/* Fails at `pos` with `cause` followed by the hint about braces in f text. */
static bool fail_hinted_at(Scanner *s, MsPos pos, const char *cause) {
  return lex_fail_at(s, pos, ms_message_format(s->arena, "%s (%s)", cause, BRACE_HINT));
}

static bool is_simple_escape(uint8_t c) {
  return c == '"' || c == '\\' || c == 'n' || c == 'r' || c == 't' || c == '{' || c == '}';
}

/* ---- text ---- */

static const MsByteRange *find_range(const MsByteRange *r, size_t n, size_t start) {
  size_t lo = 0, hi = n;
  while (lo < hi) {
    size_t mid = (lo + hi) / 2;
    if (r[mid].start < start) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo < n && r[lo].start == start ? &r[lo] : NULL;
}

size_t ms_bounds_interp_end(const MsBounds *b, size_t start) {
  const MsByteRange *r = find_range(b->interps, b->ninterps, start);
  return r != NULL ? r->end : 0;
}

MsPos ms_bounds_restore_offset(const MsBounds *b, MsPos from, MsPos to) {
  if (b->line_offsets != NULL) {
    uint32_t before = from.line - b->base_line - 1;
    uint32_t after = to.line - b->base_line - 1;
    to.offset += b->line_offsets[after] - b->line_offsets[before];
  }
  return to;
}

/* Validates the escape after a consumed backslash. */
MS_NODISCARD static bool scan_escape(Scanner *s, bool interpolating) {
  size_t n = s->n;
  MsPos backslash = lex_pos(s);
  backslash.column -= 1;
  backslash.offset -= 1;
  if (s->offset == n) {
    return lex_fail_text(s, "unterminated text escape; a backslash needs a following character, e.g. \\n");
  }
  uint8_t c = lex_advance(s);
  if (c == 'u') {
    if (s->offset == n || lex_advance(s) != '{') {
      MsSpan message = ms_span_of_text(
          "Unicode escapes use \\u{H}; write 1 to 6 hexadecimal digits in braces, e.g. \\u{1F600}");
      if (s->src[s->offset - 1] < 0x80) {
        return lex_fail(s, message);
      }
      return lex_fail_previous_byte(s, message);
    }
    size_t start = s->offset;
    uint64_t value = 0;
    while (s->offset < n && s->src[s->offset] != '}') {
      uint8_t ch = lex_advance(s);
      uint32_t d = 0;
      if (!ms_hex_digit_value(ch, &d)) {
        MsSpan message = ms_span_of_text(
            "invalid Unicode scalar escape; use only hexadecimal digits 0-9 and a-f inside \\u{...}");
        if (ch < 0x80) {
          return lex_fail(s, message);
        }
        return lex_fail_previous_byte(s, message);
      }
      /* saturating_mul(16).saturating_add(d) */
      value = value > (UINT64_MAX - d) / 16 ? UINT64_MAX : value * 16 + d;
    }
    size_t digits = s->offset - start;
    if (s->offset == n || digits < 1 || digits > 6 || value > 0x10ffff ||
        (value >= 0xd800 && value <= 0xdfff)) {
      return lex_fail_text(s, "invalid Unicode scalar escape; use 1 to 6 hexadecimal digits for a value up "
                              "to 10FFFF that is not a surrogate (D800-DFFF)");
    }
    lex_advance(s);
  } else if (!interpolating && (c == '{' || c == '}')) {
    return lex_fail_at_text(s, backslash, TEXT_PLAIN_BRACE);
  } else if (!is_simple_escape(c)) {
    MsSpan escape;
    if (lex_is_graphic(c)) {
      escape = ms_message_format(s->arena, " \\%c", c);
    } else {
      MsRune full = ms_utf8_decode(s->src + s->offset - 1, s->n - (s->offset - 1));
      escape = ms_message_format(s->arena, ": a backslash followed by %S", lex_quote_rune(s, full.rune));
    }
    const char *braces = interpolating ? "\\{ \\} (f text only) " : "";
    return lex_fail_at_format(s, backslash,
                              "unknown text escape%S; valid escapes are \\n \\t \\r \\\\ \\\" %sand \\u{H}",
                              escape, braces);
  }
  return true;
}

static bool text_is_blank(MsSpan text) {
  /* trim_matches(char::is_whitespace).is_empty() */
  for (size_t index = 0; index < text.len;) {
    MsRune rune = ms_utf8_decode(text.ptr + index, text.len - index);
    if (!ms_utf8_is_space(rune.rune)) {
      return false;
    }
    index += rune.width;
  }
  return true;
}

MS_NODISCARD static bool interpolation_body(Scanner *s, MsPos open) {
  size_t n = s->n;
  int depth = 1;
  size_t start = s->offset;
  while (s->offset < n) {
    uint8_t b = s->src[s->offset];
    if (b == '\n' || b == '\r' || lex_at_line_comment(s) || lex_at_block_comment(s)) {
      return fail_hinted_at(s, open,
                            "newlines and comments are not allowed inside interpolation; keep the expression "
                            "on one line, or bind it to a name first and interpolate the name");
    }
    if (b == '\\') {
      return fail_hinted_at(s, open, "a backslash cannot appear in the interpolated expression");
    }
    if (b == '"') {
      if (!lex_scan_string(s, false)) {
        return false;
      }
      continue;
    }
    bool after_word = s->offset > 0 && (ms_ascii_is_ident_start(s->src[s->offset - 1]) ||
                                        ms_ascii_is_digit(s->src[s->offset - 1]));
    if (b == 'f' && lex_peek(s, s->offset + 1) == '"' && !after_word) {
      lex_advance(s);
      if (!lex_scan_string(s, true)) {
        return false;
      }
      continue;
    }
    if (b == 'r' && lex_peek(s, s->offset + 1) == '"' && !lex_starts_with(s, s->offset + 2, "\"\"") &&
        !after_word) {
      if (!lex_scan_raw_line(s)) {
        return false;
      }
      continue;
    }
    lex_advance(s);
    if (b == '{') {
      depth++;
    }
    if (b == '}') {
      depth--;
      if (depth == 0) {
        if (text_is_blank(ms_span_of(s->src + start, s->offset - 1 - start))) {
          return lex_fail_text(
              s,
              "empty interpolation; put an expression between the braces, or write \\{ for a literal brace");
        }
        return true;
      }
    }
  }
  return fail_hinted_at(s, open, "unterminated interpolation; add the closing } before the closing quote");
}

MS_NODISCARD static bool scan_interpolation(Scanner *s) {
  size_t start = s->boundary_origin + s->offset - 1;
  MsPos open = lex_pos(s);
  open.column -= 1;
  open.offset -= 1;
  if (s->interpolations.len >= MAX_INTERPOLATION_DEPTH) {
    return lex_fail_at_format(
        s, open, "nesting exceeds %u levels; split the expression, type, or block into named parts",
        (unsigned)MAX_INTERPOLATION_DEPTH);
  }
  pos_list_push(&s->interpolations, open);
  if (!interpolation_body(s, open)) {
    return false;
  }
  s->interpolations.len--;
  MsByteRange r = {start, s->boundary_origin + s->offset};
  range_list_push(&s->interps, r);
  return true;
}

/* Scans `"..."` text, or `f"..."` text when `interpolating` (the caller has consumed the `f`).
 * Braces are plain characters unless interpolating. */
MS_NODISCARD bool lex_scan_string(Scanner *s, bool interpolating) {
  size_t start = s->offset;
  if (lex_starts_with(s, start, "\"\"\"")) {
    return lex_scan_multiline(s, false, interpolating);
  }
  if (s->cached != NULL) {
    const MsByteRange *r = find_range(s->cached->strings, s->cached->nstrings, s->boundary_origin + start);
    if (r != NULL) {
      s->column += (uint32_t)(r->end - s->boundary_origin - start);
      s->offset = r->end - s->boundary_origin;
      return true;
    }
  }
  size_t n = s->n;
  MsPos opened = lex_pos(s);
  lex_advance(s);
  while (s->offset < n) {
    uint8_t b = lex_advance(s);
    if (b == '"') {
      if (s->interpolations.len != 0) {
        MsByteRange r = {s->boundary_origin + start, s->boundary_origin + s->offset};
        range_list_push(&s->strings, r);
      }
      return true;
    }
    if (b == '\n') {
      if (s->interpolations.len != 0) {
        MsPos brace = s->interpolations.ptr[s->interpolations.len - 1];
        return fail_hinted_at(
            s, brace,
            "unterminated interpolation; the quote after this '{' opens a nested text that never closes");
      }
      return lex_fail_at_text(s, opened,
                              "unterminated text literal; text must close with '\"' on the same line, so add "
                              "the quote or write \\n for a line break");
    }
    if (b < 32) {
      return lex_fail_text(
          s,
          "literal control characters are not allowed in text; write an escape such as \\t, \\r, or \\u{H}");
    }
    if (b == 0xE2 && lex_bidi_control_at(s, s->offset - 1)) {
      return lex_fail_previous_byte(s, ms_span_of_text(TEXT_BIDI));
    }
    if (b == '\\') {
      if (!scan_escape(s, interpolating)) {
        return false;
      }
    } else if (interpolating && b == '{') {
      if (!scan_interpolation(s)) {
        return false;
      }
    } else if (interpolating && b == '}') {
      return lex_fail_text(s, TEXT_UNMATCHED_BRACE);
    }
  }
  return lex_fail_at_text(s, opened, "unterminated text literal; add the closing '\"' on the same line");
}

/* Scans one-line raw text `r"..."`: every character is literal up to the first `"`. */
MS_NODISCARD bool lex_scan_raw_line(Scanner *s) {
  MsPos opened = lex_pos(s);
  lex_advance(s);
  lex_advance(s);
  while (s->offset < s->n) {
    uint8_t b = lex_advance(s);
    if (b == '"') {
      return true;
    }
    if (b == '\n') {
      return lex_fail_at_text(s, opened,
                              "unterminated raw text literal; r\"...\" must close on the same line and "
                              "cannot hold a quote, so add the quote or use r\"\"\" multi-line raw text");
    }
    if (b < 32) {
      return lex_fail_text(s, "literal control characters are not allowed in text; use r\"\"\" raw text for "
                              "tabs, or write an escape such as \\t in non-raw text");
    }
    if (b == 0xE2 && lex_bidi_control_at(s, s->offset - 1)) {
      return lex_fail_previous_byte(s, ms_span_of_text(TEXT_BIDI));
    }
  }
  return lex_fail_at_text(s, opened, "unterminated raw text literal; add the closing '\"' on the same line");
}

static bool blank_line(const uint8_t *line, size_t length) {
  for (size_t i = 0; i < length; i++) {
    if (line[i] != ' ' && line[i] != '\t') {
      return false;
    }
  }
  return true;
}

/* Every content line must carry the closing line's indentation; `quote` is the closing quotes'
 * offset and `indent_len` that indentation's width. */
static bool check_text_indentation(Scanner *s, const LineList *lines, size_t quote, size_t indent_len,
                                   size_t line_start) {
  const uint8_t *indent = s->src + line_start;
  for (size_t k = 0; k < (*lines).len; k++) {
    LinePos line = (*lines).ptr[k];
    const uint8_t *rest = s->src + line.at;
    size_t rest_len = s->n - line.at;
    size_t line_len = ms_find(rest, rest_len, (const uint8_t *)"\n", 1);
    if (line_len == SIZE_MAX) {
      line_len = rest_len;
    }
    bool has_prefix =
        line_len >= indent_len && ms_span_equal(ms_span_of(rest, indent_len), ms_span_of(indent, indent_len));
    if (line.at < quote && !blank_line(rest, line_len) && !has_prefix) {
      return lex_fail_at(s, line.pos,
                         ms_span_of_text("text line is indented less than the closing '\"\"\"'; indent it to "
                                         "the closing quotes' column, or move the closing quotes left"));
    }
  }
  return true;
}

/* The cursor is just past the first closing quote: checks the closing line and consumes the rest. */
static bool finish_multiline(Scanner *s, const LineList *lines, size_t line_start) {
  size_t quote = s->offset - 1;
  size_t indent_len = quote - line_start;
  if (!blank_line(s->src + line_start, indent_len)) {
    return lex_fail_previous_byte(
        s,
        ms_span_of_text(
            "multi-line text closes with '\"\"\"' alone on its own line; move the closing quotes to a new "
            "line (a '\"\"\"' inside the text is not allowed, so write \\\" for a quote in non-raw text)"));
  }
  if (!check_text_indentation(s, lines, quote, indent_len, line_start)) {
    return false;
  }
  lex_advance(s);
  lex_advance(s);
  return true;
}

/* The body of a multi-line text; `lines` collects where each content line starts. */
MS_NODISCARD static bool scan_multiline_body(Scanner *s, bool raw, bool interpolating, MsPos opened,
                                             LineList *lines) {
  size_t line_start = s->offset + 1;
  while (s->offset < s->n) {
    uint8_t b = lex_advance(s);
    if (b == '\n') {
      line_start = s->offset;
      line_list_push(&*lines, ((LinePos){line_start, lex_pos(s)}));
    } else if (b == '"' && lex_starts_with(s, s->offset, "\"\"")) {
      return finish_multiline(s, lines, line_start);
    } else if (b < 32 && b != '\t') {
      return lex_fail_text(
          s,
          "literal control characters are not allowed in text; write an escape such as \\t, \\r, or \\u{H}");
    } else if (b == 0xE2 && lex_bidi_control_at(s, s->offset - 1)) {
      return lex_fail_previous_byte(s, ms_span_of_text(TEXT_BIDI));
    } else if (raw) {
      continue;
    } else if (b == '\\') {
      if (!scan_escape(s, interpolating)) {
        return false;
      }
    } else if (interpolating && b == '{') {
      if (!scan_interpolation(s)) {
        return false;
      }
    } else if (interpolating && b == '}') {
      return lex_fail_text(s, TEXT_UNMATCHED_BRACE);
    }
  }
  return lex_fail_at_text(s, opened,
                          "unterminated multi-line text; close it with '\"\"\"' alone on its own line");
}

/* Scans `"""` text (and `r"""` raw text when `raw`): the opening quotes end their line, the
 * closing quotes start theirs, and every content line carries the closing line's indentation. */
MS_NODISCARD bool lex_scan_multiline(Scanner *s, bool raw, bool interpolating) {
  MsPos opened = lex_pos(s);
  if (s->interpolations.len != 0) {
    return lex_fail_text(s, "multi-line text cannot appear inside an interpolation; bind it to a name first "
                            "and interpolate the name");
  }
  for (int i = 0; i < (raw ? 4 : 3); i++) {
    lex_advance(s);
  }
  if (s->offset == s->n || s->src[s->offset] != '\n') {
    return lex_fail_at_text(s, opened,
                            "multi-line text must start on the line after its opening '\"\"\"'; add a line "
                            "break after the opening quotes");
  }
  LineList lines = {0};
  bool ok = scan_multiline_body(s, raw, interpolating, opened, &lines);
  line_list_free(&lines);
  return ok;
}
