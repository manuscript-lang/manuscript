/* Owns reading src/layers.txt into the Lint layer table. */
#include <stdio.h>

#include "lint/lint.h"
#include "lint/text.h"

enum { LINE_LENGTH = 1024 };

static size_t word_end(const char *line, size_t start) {
  size_t end = start;
  while (line[end] != '\0' && line[end] != ' ' && line[end] != ':') end++;
  return end;
}

static void copy_word(char *destination, const char *line, size_t start, size_t end) {
  size_t length = end - start;
  if (length >= LINT_NAME_LENGTH) length = LINT_NAME_LENGTH - 1;
  for (size_t index = 0; index < length; index++) destination[index] = line[start + index];
  destination[length] = '\0';
}

static void parse_layer(Lint *lint, const char *line) {
  if (lint->layer_count >= LINT_MAX_LAYERS) return;
  LintLayer *layer = &lint->layers[lint->layer_count++];
  size_t end = word_end(line, 0);
  copy_word(layer->directory, line, 0, end);
  layer->allowed_count = 0;
  size_t index = end;
  while (line[index] == ':' || line[index] == ' ') index++;
  while (line[index] != '\0' && layer->allowed_count < LINT_MAX_ALLOWED) {
    end = word_end(line, index);
    copy_word(layer->allowed[layer->allowed_count++], line, index, end);
    index = end;
    while (line[index] == ' ') index++;
  }
}

bool lint_load_layers(Lint *lint) {
  char path[LINT_PATH_LENGTH];
  (void)snprintf(path, sizeof path, "%s/src/layers.txt", lint->root);
  FILE *file = fopen(path, "r");
  if (file == NULL) return false;
  char line[LINE_LENGTH];
  while (fgets(line, sizeof line, file) != NULL) {
    lint_text_chomp(line);
    if (line[0] == '#' || line[0] == '\0') continue;
    parse_layer(lint, line);
  }
  (void)fclose(file);
  return true;
}
