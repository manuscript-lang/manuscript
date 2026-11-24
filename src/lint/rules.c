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

enum { FUNCTION_NAME = 96 };

typedef struct WordContext {
  Lint *lint;
  const char *path;
  size_t line;
  bool at_margin;       /* the line starts a declaration: its first call-shaped word names the function */
  char *function;       /* the function the line is in, FUNCTION_NAME bytes */
  bool unwind_rule;     /* the file is under a directory where runtime C never unwinds past its caller */
  bool unwind_home;     /* the file defines the unwind itself */
} WordContext;

/* Directories whose C returns a cancelled answer to its caller and never jumps over it, so nothing a frame holds
 * is skipped. Only a program entry (msrt_*, msstd_*) ends a cancelled call. */
static const char *const NO_UNWIND[] = {"src/runtime/"};
static const char *const UNWIND_HOME[] = {"src/runtime/core/unwind.c", "src/runtime/core/fault_abi.c",
                                          "src/runtime/entry/start.c"};

static bool word_is(const char *start, size_t length, const char *name) {
  return lint_text_length(name) == length && lint_text_starts_with(start, name);
}

static void check_unwind(WordContext *context, const char *start, size_t length) {
  if (!context->unwind_rule || context->unwind_home) return;
  if (word_is(start, length, "ms_cancelled")) {
    lint_report(context->lint, context->path, context->line, "unwind",
                "runtime C does not unwind past its caller; return a cancelled answer");
    return;
  }
  const bool entry = lint_text_starts_with(context->function, "msrt_") ||
                     lint_text_starts_with(context->function, "msstd_");
  if (word_is(start, length, "ms_sched_cancel_return") && !entry) {
    lint_report(context->lint, context->path, context->line, "unwind",
                "only a program entry (msrt_*, msstd_*) ends a cancelled call");
  }
}

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
  if (context->at_margin) {
    context->at_margin = false;
    (void)snprintf(context->function, FUNCTION_NAME, "%.*s", (int)length, start);
    return;
  }
  check_unwind(context, start, length);
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
  char function[FUNCTION_NAME] = "";
  bool unwind_rule = false;
  bool unwind_home = false;
  for (size_t index = 0; index < sizeof NO_UNWIND / sizeof NO_UNWIND[0]; index++) {
    unwind_rule = unwind_rule || lint_text_starts_with(path, NO_UNWIND[index]);
  }
  for (size_t index = 0; index < sizeof UNWIND_HOME / sizeof UNWIND_HOME[0]; index++) {
    unwind_home = unwind_home || lint_text_equal(path, UNWIND_HOME[index]);
  }
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
    const bool at_margin = (line[0] >= 'a' && line[0] <= 'z') || (line[0] >= 'A' && line[0] <= 'Z') || line[0] == '_';
    WordContext context = {lint, path, line_number, at_margin, function, unwind_rule, unwind_home};
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
