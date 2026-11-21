/* Owns the layout rules: indentation, suites, continuation lines and the hints for layout errors. */
#include "compiler/syntax/lex_internal.h"

/* ---- layout helpers ---- */

/* Whether the next code line begins with '.' or '|', which continues the statement on the current
 * line. Blank and comment-only lines are skipped. */
bool lex_continues_next(const Scanner *s) {
  size_t n = s->n;
  size_t i = s->offset;
  if (i >= n) {
    return false;
  }
  i++;
  while (i < n) {
    size_t j = i;
    while (j < n && (s->src[j] == ' ' || s->src[j] == '\t')) {
      j++;
    }
    if (j >= n) {
      return false;
    }
    uint8_t c = s->src[j];
    if (c == '\n') {
      i = j + 1;
    } else if (c == '/' && lex_peek(s, j + 1) == '/') {
      while (j < n && s->src[j] != '\n') {
        j++;
      }
      i = j + 1;
    } else if (c == '/' && lex_peek(s, j + 1) == '*') {
      size_t k = j + 2;
      bool found = false;
      while (k + 1 < n) {
        if (s->src[k] == '*' && s->src[k + 1] == '/') {
          found = true;
          break;
        }
        k++;
      }
      if (!found) {
        return false;
      }
      j = k + 2;
      while (j < n && s->src[j] != '\n') {
        j++;
      }
      i = j + 1;
    } else if (c == '|') {
      return true;
    } else if (c == '.') {
      return j + 1 < n && !ms_ascii_is_digit(s->src[j + 1]) && s->src[j + 1] != '.';
    } else {
      return false;
    }
  }
  return false;
}

/* The first token of the unfinished line before the trailing newlines, or NULL when that line is not a
 * single-line header ending at `last`. `*last_out` is its last token. */
static const MsToken *previous_line_start(const Scanner *s, const MsToken **last_out) {
  size_t nt = lex_token_count(s);
  size_t li = nt;
  while (li > 0 &&
         (lex_token_at(s, li - 1)->kind == MS_T_Newline || lex_token_at(s, li - 1)->kind == MS_T_Comment)) {
    li--;
  }
  if (li == 0) {
    return NULL;
  }
  const MsToken *last = lex_token_at(s, li - 1);
  if (last->kind == MS_T_Colon || last->kind == MS_T_Indent || last->kind == MS_T_Dedent) {
    return NULL;
  }
  size_t i = nt;
  while (i > 0 && lex_token_at(s, i - 1)->kind == MS_T_Newline) {
    i--;
  }
  size_t j = i;
  while (j > 0) {
    int k = lex_token_at(s, j - 1)->kind;
    if (k == MS_T_Newline || k == MS_T_Indent || k == MS_T_Dedent) {
      break;
    }
    j--;
  }
  if (j == i) {
    return NULL;
  }
  const MsToken *first = lex_token_at(s, j);
  if (first->pos.line != last->end.line) {
    return NULL;
  }
  *last_out = last;
  return first;
}

static bool starts_block_header(MsTok kind) {
  switch (kind) {
  case MS_T_Fn:
  case MS_T_If:
  case MS_T_Else:
  case MS_T_For:
  case MS_T_While:
  case MS_T_Match:
  case MS_T_Type:
  case MS_T_Enum:
  case MS_T_Impl:
  case MS_T_Test:
  case MS_T_Interface:
    return true;
  default:
    return false;
  }
}

/* Whether a ':' outside brackets already ends a line's header (`if x: return`), so an indented line after
 * it is over-indented, not a missing ':'. */
static bool line_has_colon(const Scanner *s, uint32_t line) {
  int depth = 0;
  for (size_t k = 0; k < lex_token_count(s); k++) {
    const MsToken *t = lex_token_at(s, k);
    if (t->pos.line != line) {
      continue;
    }
    switch (t->kind) {
    case MS_T_LParen:
    case MS_T_LBracket:
    case MS_T_LBrace:
      depth++;
      break;
    case MS_T_RParen:
    case MS_T_RBracket:
    case MS_T_RBrace:
      depth--;
      break;
    case MS_T_Colon:
      if (depth == 0) {
        return true;
      }
      break;
    default:
      break;
    }
  }
  return false;
}

/* A block header on the previous line that lacks its closing ':' when an indented line follows
 * it, with the fix that inserts the ':'. Returns false when there is none. */
static bool missing_colon(Scanner *s) {
  const MsToken *last = NULL;
  const MsToken *first = previous_line_start(s, &last);
  if (first == NULL || !starts_block_header((MsTok)first->kind) || line_has_colon(s, first->pos.line)) {
    return false;
  }
  MsPos end = last->end;
  MsSpan message = ms_message_format(s->arena,
                                     "the '%s' block header on line %u does not end with ':'; add ':' at the "
                                     "end of that line so the indented lines below become its body",
                                     ms_tok_str((MsTok)first->kind), first->pos.line);
  MsDiag *d = lex_new_diag(s, end, message);
  d->has_end = true;
  d->end = end;
  d->has_fix = true;
  d->fix_pos = end;
  d->fix_end = end;
  d->replacement = ms_span_of_text(":");
  return true;
}

/* Explains the usual cause of an over-indented line that starts with a binary operator. */
static const char *continuation_hint(const Scanner *s) {
  for (size_t i = lex_token_count(s); i > 0; i--) {
    int k = lex_token_at(s, i - 1)->kind;
    if (k == MS_T_Newline || k == MS_T_Indent || k == MS_T_Dedent) {
      continue;
    }
    if (k == MS_T_Pipe) {
      return "; a pipe step cannot follow the '|' on the next line, so end the previous line before '|' and "
             "start the continuation line with '|'";
    }
    break;
  }
  size_t end = s->offset;
  while (end < s->n && s->src[end] != ' ' && s->src[end] != '\n') {
    end++;
  }
  MsSpan word = ms_span_of(s->src + s->offset, end - s->offset);
  static const char *const ops[] = {"and", "or", "+", "-", "*", "/", "%", "==", "!=", "<", ">", "<=", ">="};
  for (size_t i = 0; i < MS_COUNT_OF(ops); i++) {
    if (ms_span_is_text(word, ops[i])) {
      return "; to continue an expression on the next line, wrap the whole expression in parentheses";
    }
  }
  return "";
}

const char *lex_character_hint(uint8_t b) {
  switch (b) {
  case ';':
    return "; Manuscript ends a statement at the end of the line, so remove the semicolon";
  case '\'':
    return "; text uses double quotes, e.g. \"text\"";
  case '!':
    return "; write 'not x' for negation and '!=' for inequality";
  case '`':
    return "; text uses double quotes with {expression} interpolation";
  case '#':
    return "; comments start with '//' (or '/* */' for a block)";
  case '$':
  case '@':
  case '\\':
  case '^':
  case '~':
    return "; this character is not part of Manuscript's syntax outside text";
  default:
    return "; this character is not part of Manuscript's syntax";
  }
}

/* ---- the main loop ---- */

/* What the layout rules carry from one line to the next. */
size_t lex_open_delimiters(const Scanner *s) {
  return s->delimiters.len;
}

uint8_t lex_closer_of(uint8_t open) {
  switch (open) {
  case '(':
    return ')';
  case '[':
    return ']';
  default:
    return '}';
  }
}

/* Recovery's per-line flag: whether a delimiter is open there. */
/* Measures the indentation: a tab is one indent level of four columns. */
bool lex_read_leading_space(Scanner *s, size_t *leading) {
  bool spaced = false;
  *leading = 0;
  while (s->offset < s->n && (s->src[s->offset] == ' ' || s->src[s->offset] == '\t')) {
    if (s->src[s->offset] == '\t') {
      if (spaced) {
        return lex_fail_text(
            s, "a tab cannot follow spaces in indentation; indent with tabs, then align with spaces");
      }
      lex_advance(s);
      s->column += 3;
      *leading += 4;
    } else {
      lex_advance(s);
      spaced = true;
      *leading += 1;
    }
  }
  return true;
}

/* Consumes a line that holds no code (a comment or an empty line) and sets *skipped. */
bool lex_skip_blank_line(Scanner *s, bool *skipped) {
  *skipped = true;
  if (lex_at_line_comment(s)) {
    if (!lex_skip_comment(s)) {
      return false;
    }
  } else if (lex_at_block_comment(s)) {
    if (!lex_skip_block_comment(s)) {
      return false;
    }
  } else if (s->src[s->offset] != '\n') {
    *skipped = false;
    return true;
  }
  if (s->offset < s->n) {
    lex_advance(s);
  }
  return true;
}

static bool fail_indent_width(Scanner *s, size_t leading) {
  const char *inside =
      lex_open_delimiters(s) == 0
          ? ""
          : "; a line inside brackets is indented by fours too, so do not align it with the opening bracket";
  return lex_fail_format(s, "indentation must be a multiple of four spaces, found %z; use %z or %z%s",
                         leading, leading / 4 * 4, leading / 4 * 4 + 4, inside);
}

/* The line after a ':' header: it opens the suite, or it is an empty declaration suite. */
static bool resolve_pending_suite(Scanner *s, LineLayout *layout, size_t leading, bool *started) {
  if (leading == layout->header_indent + 4) {
    level_list_push(&s->levels, ((Level){leading, layout->pending_depth}));
    lex_emit_layout(s, MS_T_Indent);
    *started = true;
  } else if (leading > layout->header_start && leading <= layout->header_indent) {
    return lex_fail_format(s,
                           "a suite begins four spaces after the line that ends with ':' (at %z spaces); "
                           "indent this line to %z, or move that closing line back to %z spaces",
                           layout->header_indent, layout->header_indent + 4, layout->header_start);
  } else if (leading <= layout->header_indent) {
    /* An empty declaration suite has the same layout boundaries as a populated one. */
    lex_emit_layout(s, MS_T_Indent);
    lex_emit_layout(s, MS_T_Dedent);
  } else {
    return lex_fail_format(s,
                           "a suite must begin exactly four spaces after its header; the header is at %z "
                           "spaces, so indent this line to %z",
                           layout->header_indent, layout->header_indent + 4);
  }
  layout->pending = false;
  return true;
}

static bool fail_unexpected_indent(Scanner *s, size_t leading, size_t expected) {
  if (missing_colon(s)) {
    return false;
  }
  const char *hint = continuation_hint(s);
  return lex_fail_format(s,
                         "unexpected indentation, %z spaces where %z are expected; the previous line must "
                         "end with ':' to open a block (fn, if, else, for, while, match, type, impl "
                         "headers), otherwise align this line with it%s",
                         leading, expected, hint);
}

/* Closes the suites this line dedents out of, then checks it lines up with the one it is in. */
static bool align_to_level(Scanner *s, size_t leading) {
  /* A continuation line inside delimiters opened within a level does not close that level; only
   * suites opened inside the open delimiters can. */
  while (s->levels.len > 1) {
    Level top = s->levels.ptr[s->levels.len - 1];
    if (!(leading < top.indent && top.depth >= lex_open_delimiters(s))) {
      break;
    }
    s->levels.len--;
    lex_emit_layout(s, MS_T_Dedent);
  }
  Level top = s->levels.ptr[s->levels.len - 1];
  if (lex_open_delimiters(s) != top.depth || leading == top.indent) {
    return true;
  }
  if (leading > top.indent) {
    return fail_unexpected_indent(s, leading, top.indent);
  }
  return lex_fail_format(s,
                         "inconsistent dedent to %z spaces; enclosing blocks are indented at %z or %z "
                         "spaces, so align with one of them",
                         leading, top.indent, top.indent >= 4 ? top.indent - 4 : 0);
}

/* Opens or closes suites for a line of code with `leading` columns of indentation. */
bool lex_apply_layout(Scanner *s, LineLayout *layout, size_t leading) {
  if (!s->virtual_paren && leading % 4 != 0) {
    return fail_indent_width(s, leading);
  }
  if (layout->continuing) {
    if (leading != layout->statement_indent + 4) {
      return lex_fail_format(s,
                             "a line starting with '.' or '|' continues the previous statement and must be "
                             "indented four spaces past it, to %z spaces, found %z",
                             layout->statement_indent + 4, leading);
    }
    layout->continuing = false;
    return true;
  }
  if (lex_open_delimiters(s) == s->levels.ptr[s->levels.len - 1].depth) {
    layout->statement_indent = leading;
  }
  bool started_suite = false;
  if (layout->pending && !resolve_pending_suite(s, layout, leading, &started_suite)) {
    return false;
  }
  return started_suite || align_to_level(s, leading);
}
