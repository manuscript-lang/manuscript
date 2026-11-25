/* Owns the ms_lint text helpers (see text.h). */
#include "lint/text.h"

size_t lint_text_length(const char *text) {
  size_t length = 0;
  while (text[length] != '\0') length++;
  return length;
}

bool lint_text_equal(const char *left, const char *right) {
  size_t index = 0;
  while (left[index] != '\0' && left[index] == right[index]) index++;
  return left[index] == right[index];
}

bool lint_text_starts_with(const char *text, const char *prefix) {
  size_t index = 0;
  while (prefix[index] != '\0') {
    if (text[index] != prefix[index]) return false;
    index++;
  }
  return true;
}

bool lint_text_contains(const char *text, const char *needle) {
  for (size_t at = 0; text[at] != '\0'; at++) {
    if (lint_text_starts_with(text + at, needle)) return true;
  }
  return false;
}

bool lint_text_ends_with(const char *text, const char *suffix) {
  size_t text_length = lint_text_length(text);
  size_t suffix_length = lint_text_length(suffix);
  if (suffix_length > text_length) return false;
  return lint_text_equal(text + (text_length - suffix_length), suffix);
}

void lint_text_chomp(char *line) {
  size_t length = lint_text_length(line);
  while (length > 0 && (line[length - 1] == '\n' || line[length - 1] == '\r')) {
    line[--length] = '\0';
  }
}

static bool lint_is_identifier_char(char value) {
  return (value >= 'a' && value <= 'z') || (value >= 'A' && value <= 'Z') ||
         (value >= '0' && value <= '9') || value == '_';
}

/* Returns the index after a quoted literal that starts at `index`. */
static size_t skip_literal(const char *line, size_t index) {
  char quote = line[index++];
  while (line[index] != '\0' && line[index] != quote) {
    index += line[index] == '\\' && line[index + 1] != '\0' ? 2 : 1;
  }
  return line[index] == '\0' ? index : index + 1;
}

void lint_scan_words(const char *line, LintWordFn on_word, void *context) {
  size_t index = 0;
  while (line[index] != '\0') {
    char value = line[index];
    if (value == '"' || value == '\'') {
      index = skip_literal(line, index);
    } else if (value == '/' && (line[index + 1] == '/' || line[index + 1] == '*')) {
      return;
    } else if (lint_is_identifier_char(value)) {
      size_t start = index;
      while (lint_is_identifier_char(line[index])) index++;
      size_t after = index;
      while (line[after] == ' ') after++;
      on_word(context, line + start, index - start, line[after] == '(');
    } else {
      index++;
    }
  }
}
