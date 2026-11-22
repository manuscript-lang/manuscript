/* runtime/std/regex_screen.c: the scan that refuses the features outside the regex dialect. Back-references
 * written as \1 are found after compiling (PCRE2_INFO_BACKREFMAX); this scan finds the rest. */
#include "runtime/std/regex_engine.h"

#include "base/chars.h"

static const char *const reason_backref = "back-references and subroutine calls are not supported";

typedef struct Screen {
  const uint8_t *p;
  size_t n;
  size_t at; /* where the refused feature starts */
} Screen;

static bool is_hex(uint8_t c) {
  return (c >= '0' && c <= '9') || ((c | 0x20) >= 'a' && (c | 0x20) <= 'f');
}

/* \x takes one or two hex digits, or hex digits in braces; PCRE2 alone would read \x+1 as a NUL then a
 * quantifier. */
static bool hex_escape_ok(const Screen *s, size_t i) {
  if (i + 2 < s->n && s->p[i + 2] == '{') {
    size_t j = i + 3;
    while (j < s->n && is_hex(s->p[j])) {
      j++;
    }
    return j > i + 3 && j < s->n && s->p[j] == '}';
  }
  return i + 2 < s->n && is_hex(s->p[i + 2]);
}

/* The backslash at `*i`: skips the escape, or returns why it is refused. */
static const char *screen_escape(Screen *s, size_t *i) {
  const uint8_t d = *i + 1 < s->n ? s->p[*i + 1] : 0;
  if (d == 'Q') { /* literal text up to \E */
    *i += 2;
    while (*i < s->n && !(s->p[*i] == '\\' && *i + 1 < s->n && s->p[*i + 1] == 'E')) {
      (*i)++;
    }
    *i += 2;
    return NULL;
  }
  s->at = *i;
  if (d == 'g' || d == 'k') {
    return reason_backref;
  }
  if (d == 'x' && !hex_escape_ok(s, *i)) {
    return "invalid hexadecimal escape";
  }
  *i += 2;
  return NULL;
}

/* Skips a POSIX class such as [:alpha:] whose opener is at `j`; returns the offset after it. */
static size_t skip_posix_class(const Screen *s, size_t j) {
  const uint8_t q = s->p[j + 1];
  j += 2;
  while (j + 1 < s->n && !(s->p[j] == q && s->p[j + 1] == ']')) {
    j++;
  }
  return j + 2;
}

/* The bracket class at `*i`: skips it, or returns why it is refused. */
static const char *screen_class(Screen *s, size_t *i) {
  size_t j = *i + 1;
  if (j < s->n && s->p[j] == '^') {
    j++;
  }
  if (j < s->n && s->p[j] == ']') {
    j++;
  }
  while (j < s->n && s->p[j] != ']') {
    if (s->p[j] == '\\') {
      if (j + 1 < s->n && s->p[j + 1] == 'x' && !hex_escape_ok(s, j)) {
        s->at = j;
        return "invalid hexadecimal escape";
      }
      j += 2;
    } else if (s->p[j] == '[' && j + 1 < s->n &&
               (s->p[j + 1] == ':' || s->p[j + 1] == '.' || s->p[j + 1] == '=')) {
      j = skip_posix_class(s, j);
    } else {
      j++;
    }
  }
  *i = j + 1;
  return NULL;
}

/* Why the group syntax `(?` followed by `e` and `f` is refused, or NULL. */
static const char *refused_group(uint8_t e, uint8_t f) {
  if (e == '=' || e == '!') {
    return "lookahead is not supported";
  }
  if (e == '<' && (f == '=' || f == '!')) {
    return "lookbehind is not supported";
  }
  if (e == 'R' || e == '&' || (e >= '0' && e <= '9') || ((e == '+' || e == '-') && f >= '0' && f <= '9')) {
    return "recursion and subroutine calls are not supported";
  }
  if (e == 'P' && (f == '>' || f == '=')) {
    return reason_backref;
  }
  if (e == '(') {
    return "conditional groups are not supported";
  }
  return e == 'C' ? "callouts are not supported" : NULL;
}

/* A flag group `(?flags)` or `(?flags:` at `open` that repeats a flag or its negation: why, with `s->at` at the
 * second occurrence; NULL for any other group. */
static const char *flag_flaw(Screen *s, size_t open) {
  bool seen[256] = {false};
  bool negated = false;
  for (size_t j = open + 2; j < s->n; j++) {
    const uint8_t c = s->p[j];
    if (c == ')' || c == ':') {
      return NULL;
    }
    if (c == '-') {
      if (negated) {
        s->at = j;
        return "flag negation operator repeated";
      }
      negated = true;
    } else if (c == 'i' || c == 'm' || c == 's' || c == 'x' || c == 'U' || c == 'u' || c == 'R') {
      if (seen[c]) {
        s->at = j;
        return "duplicate flag";
      }
      seen[c] = true;
    } else {
      return NULL;
    }
  }
  return NULL;
}

/* The parenthesis at `*i`: skips its opener, or returns why it is refused. */
static const char *screen_group(Screen *s, size_t *i) {
  const uint8_t d = *i + 1 < s->n ? s->p[*i + 1] : 0;
  s->at = *i;
  if (d == '*') {
    return "verbs are not supported";
  }
  if (d == '?') {
    const uint8_t e = *i + 2 < s->n ? s->p[*i + 2] : 0;
    const uint8_t f = *i + 3 < s->n ? s->p[*i + 3] : 0;
    const char *why = refused_group(e, f);
    if (why != NULL) {
      return why;
    }
    const char *flaws = flag_flaw(s, *i);
    if (flaws != NULL) {
      return flaws;
    }
    if (e == '#') { /* a comment: skip it */
      *i += 3;
      while (*i < s->n && s->p[*i] != ')') {
        (*i)++;
      }
      return NULL;
    }
  }
  (*i)++;
  return NULL;
}

const char *ms_re_screen(MsSpan pattern, size_t *at) {
  Screen s = {.p = pattern.ptr, .n = pattern.len, .at = 0};
  size_t i = 0;
  while (i < s.n) {
    const char *why = NULL;
    if (s.p[i] == '\\') {
      why = screen_escape(&s, &i);
    } else if (s.p[i] == '[') {
      why = screen_class(&s, &i);
    } else if (s.p[i] == '(') {
      why = screen_group(&s, &i);
    } else {
      i++;
    }
    if (why != NULL) {
      *at = s.at;
      return why;
    }
  }
  return NULL;
}

size_t ms_re_column(MsSpan pattern, size_t offset) {
  size_t column = 1; /* counted in characters from the start of the pattern's line */
  for (size_t i = 0; i < offset && i < pattern.len; i++) {
    if (pattern.ptr[i] == '\n') {
      column = 1;
    } else if (!ms_utf8_is_continuation(pattern.ptr[i])) {
      column++;
    }
  }
  return column;
}
