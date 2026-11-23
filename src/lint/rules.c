/* Owns the per-file rules of ms_lint (see lint.h). */
#include <stdio.h>

#include "lint/lint.h"
#include "lint/text.h"

enum { LINE_LENGTH = 4096, SIZE_HARD_LIMIT = 1000 };

typedef struct BannedCall {
  const char *name;
  const char *replacement;
} BannedCall;

/* Raw libc string calls (plan section 7.1 rule 3). Only src/base/cstr.c may call them. */
static const BannedCall BANNED[] = {
    {"strlen", "MsString length"},          {"strcmp", "ms_cstr_equal or MsString equality"},
    {"strncmp", "MsString prefix test"},    {"strcpy", "MsStrBuild"},
    {"strcat", "MsStrBuild"},               {"strstr", "base search"},
    {"strchr", "base search"},              {"memcmp", "MsBytes equality"},
    {"atoi", "base fmt parse"},             {"atol", "base fmt parse"},
    {"atof", "base fmt parse"},             {"sprintf", "MsStrBuild"},
};

void lint_report(Lint *lint, const char *path, size_t line, const char *rule, const char *message) {
  (void)printf("%s:%zu: %s: %s\n", path, line, rule, message);
  lint->violations++;
}

typedef struct WordContext {
  Lint *lint;
  const char *path;
  size_t line;
} WordContext;

static void on_word(void *opaque, const char *start, size_t length, bool followed_by_call) {
  WordContext *context = opaque;
  if (!followed_by_call) return;
  for (size_t index = 0; index < sizeof BANNED / sizeof BANNED[0]; index++) {
    const char *name = BANNED[index].name;
    if (lint_text_length(name) != length || !lint_text_starts_with(start, name)) continue;
    char message[128];
    (void)snprintf(message, sizeof message, "%s is banned here; use %s", name, BANNED[index].replacement);
    lint_report(context->lint, context->path, context->line, "banned-call", message);
    context->lint->banned_calls++;
  }
}

/* The layer whose directory is the longest prefix of `directory`, or NULL. */
static const LintLayer *layer_of(const Lint *lint, const char *directory) {
  const LintLayer *best = NULL;
  size_t best_length = 0;
  for (size_t index = 0; index < lint->layer_count; index++) {
    const char *name = lint->layers[index].directory;
    size_t length = lint_text_length(name);
    bool matches = lint_text_starts_with(directory, name) &&
                   (directory[length] == '/' || directory[length] == '\0');
    if (matches && length >= best_length) {
      best = &lint->layers[index];
      best_length = length;
    }
  }
  return best;
}

/* True when `target` lies inside `layer` itself or inside one of its allowed layers. */
static bool include_allowed(const Lint *lint, const LintLayer *layer, const char *target) {
  const LintLayer *home = layer_of(lint, target);
  if (home == NULL) return true;
  if (home == layer) return true;
  for (size_t index = 0; index < layer->allowed_count; index++) {
    const char *name = layer->allowed[index];
    size_t length = lint_text_length(name);
    if (lint_text_starts_with(target, name) && (target[length] == '/' || target[length] == '\0')) {
      return true;
    }
  }
  return false;
}

static void check_include(Lint *lint, const char *path, size_t line_number, const char *line) {
  const char *directive = "#include \"";
  if (!lint_text_starts_with(line, directive)) return;
  const char *target = line + lint_text_length(directive);
  const LintLayer *layer = layer_of(lint, path + 4);  /* Skip "src/". */
  if (layer == NULL || include_allowed(lint, layer, target)) return;
  lint_report(lint, path, line_number, "layering", "include points up or sideways; see src/layers.txt");
  lint->layering++;
}

static bool in_block_comment_line(const char *line) {
  size_t index = 0;
  while (line[index] == ' ') index++;
  return line[index] == '*' || (line[index] == '/' && line[index + 1] == '*');
}

static void check_source(Lint *lint, const char *path, FILE *file) {
  bool exempt = lint_text_equal(path, "src/base/cstr.c") || lint_text_equal(path, "src/lint/text.c");
  char line[LINE_LENGTH];
  size_t line_number = 0;
  while (fgets(line, sizeof line, file) != NULL) {
    line_number++;
    lint_text_chomp(line);
    check_include(lint, path, line_number, line);
    if (!in_block_comment_line(line) && !lint_text_equal(path, "src/cli/pipeline.h") && lint_text_contains(line, "/program\"")) {
      lint_report(lint, path, line_number, "temp-program",
                  "name a temporary program with MS_TEMP_PROGRAM (program.exe on Windows), not a literal");
    }
    if (exempt || in_block_comment_line(line)) continue;
    WordContext context = {lint, path, line_number};
    lint_scan_words(line, on_word, &context);
  }
  if (line_number > SIZE_HARD_LIMIT) {
    lint_report(lint, path, line_number, "file-size", "file is over 1000 lines; split by responsibility");
  }
}

void lint_check_file(Lint *lint, const char *path) {
  if (!lint_text_starts_with(path, "src/")) return;
  if (!lint_text_ends_with(path, ".c") && !lint_text_ends_with(path, ".h")) return;
  if (lint_text_starts_with(path, "src/third_party/")) return;
  char full[LINT_PATH_LENGTH];
  (void)snprintf(full, sizeof full, "%s/%s", lint->root, path);
  FILE *file = fopen(full, "r");
  if (file == NULL) {
    lint_report(lint, path, 0, "io", "cannot open file");
    return;
  }
  check_source(lint, path, file);
  (void)fclose(file);
}
