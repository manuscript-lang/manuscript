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

/* A delimiter is stored as `{` for a map literal and `B` for a block; both print as `{`. */
uint8_t lex_open_char(uint8_t delimiter) {
  return delimiter == 'B' ? '{' : delimiter;
}

/* Whether a newline ends a statement here: at the top or directly inside a block's braces. */
bool lex_statement_level(const Scanner *s) {
  return s->delimiters.len == 0 || s->delimiters.ptr[s->delimiters.len - 1] == 'B';
}

/* Recovery's per-line flag: whether a delimiter is open there. */
/* Skips the blanks at the start of a line; a tab counts as four columns. */
bool lex_read_leading_space(Scanner *s, size_t *leading) {
  /* Spaces and tabs are not newlines, so the cursor moves along the line: offset and column step together. */
  size_t at = s->offset;
  size_t count = 0;
  while (at < s->n && (s->src[at] == ' ' || s->src[at] == '\t')) {
    if (s->src[at] == '\t') {
      s->column += 3;
      count += 3;
    }
    at++;
    count++;
  }
  s->column += at - s->offset;
  s->offset = at;
  *leading = count;
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
