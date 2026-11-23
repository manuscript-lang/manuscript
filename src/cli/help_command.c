/* Owns the help and version commands of help_command.h. */
#include "cli/help_command.h"

#include <stdio.h>

#include "base/cstr.h"
#include "cli/help_text.h"
#include "cli/invocation.h"

enum { STATUS_USAGE = 2, SUGGEST_LIMIT = 3, DISTANCE_MAX = 64 };

static void print_text(FILE *stream, const char *text) {
  (void)fputs(text, stream);
}

const char *ms_help_page(MsSpan command) {
  for (size_t i = 1; i < MS_HELP_PAGE_COUNT; i++) {
    if (ms_span_is_text(command, MS_HELP_PAGES[i].name)) {
      return MS_HELP_PAGES[i].text;
    }
  }
  return NULL;
}

void ms_help_print_top(void) {
  print_text(stdout, MS_HELP_PAGES[0].text);
}

/* Levenshtein distance; names past DISTANCE_MAX bytes are far. */
static size_t edit_distance(MsSpan a, MsSpan b) {
  if (a.len > DISTANCE_MAX || b.len > DISTANCE_MAX) {
    return DISTANCE_MAX;
  }
  size_t previous[DISTANCE_MAX + 1];
  size_t current[DISTANCE_MAX + 1];
  for (size_t j = 0; j <= b.len; j++) {
    previous[j] = j;
  }
  for (size_t i = 1; i <= a.len; i++) {
    current[0] = i;
    for (size_t j = 1; j <= b.len; j++) {
      size_t best = previous[j] + 1;
      best = current[j - 1] + 1 < best ? current[j - 1] + 1 : best;
      const size_t diagonal = previous[j - 1] + (a.ptr[i - 1] != b.ptr[j - 1]);
      current[j] = diagonal < best ? diagonal : best;
    }
    for (size_t j = 0; j <= b.len; j++) {
      previous[j] = current[j];
    }
  }
  return previous[b.len];
}

static bool ends_with(MsSpan text, const char *suffix) {
  const size_t length = ms_span_of_text(suffix).len;
  return text.len >= length && ms_span_equal(ms_span_of(text.ptr + text.len - length, length), ms_span_of_text(suffix));
}

static bool looks_like_path(MsSpan name) {
  for (size_t i = 0; i < name.len; i++) {
    if (name.ptr[i] == '/' || name.ptr[i] == '\\') {
      return true;
    }
  }
  return ends_with(name, ".ms") || ends_with(name, ".toml");
}

void ms_help_unknown_command(MsSpan name) {
  (void)fprintf(stderr, "unknown command: %.*s\n", (int)name.len, (const char *)name.ptr);
  const char *best = NULL;
  size_t best_distance = SUGGEST_LIMIT;
  for (size_t i = 1; i < MS_HELP_PAGE_COUNT; i++) {
    const size_t distance = edit_distance(name, ms_span_of_text(MS_HELP_PAGES[i].name));
    if (distance < best_distance) {
      best = MS_HELP_PAGES[i].name;
      best_distance = distance;
    }
  }
  if (best != NULL) {
    (void)fprintf(stderr, "Did you mean 'ms %s'?\n", best);
  } else if (looks_like_path(name)) {
    (void)fprintf(stderr, "'%.*s' looks like a path; commands come first, e.g. 'ms run %.*s' or 'ms check %.*s'.\n",
                  (int)name.len, (const char *)name.ptr, (int)name.len, (const char *)name.ptr, (int)name.len,
                  (const char *)name.ptr);
  }
  print_text(stderr, "Commands: ");
  for (size_t i = 1; i < MS_HELP_PAGE_COUNT; i++) {
    print_text(stderr, i > 1 ? ", " : "");
    print_text(stderr, MS_HELP_PAGES[i].name);
  }
  print_text(stderr, ". Run 'ms --help' for details.\n");
}

bool ms_help_requested(int argc, char **argv) {
  for (int i = 0; i < argc; i++) {
    const MsSpan arg = ms_span_of_text(argv[i]);
    if (ms_span_is_text(arg, "--")) {
      return false;
    }
    if (ms_span_is_text(arg, "-h") || ms_span_is_text(arg, "--help")) {
      return true;
    }
    const bool takes_value = ms_invocation_takes_value(arg) || ms_span_is_text(arg, "--limit") ||
                             ms_span_is_text(arg, "--explain") || ms_span_is_text(arg, "--effect");
    i += takes_value;
  }
  return false;
}

int ms_help_command(int argc, char **argv) {
  if (argc == 0) {
    ms_help_print_top();
    return 0;
  }
  if (argc == 1) {
    const char *page = ms_help_page(ms_span_of_text(argv[0]));
    if (page != NULL) {
      print_text(stdout, page);
      return 0;
    }
    ms_help_unknown_command(ms_span_of_text(argv[0]));
    return STATUS_USAGE;
  }
  print_text(stderr, "usage: ms help [command]\nRun 'ms --help' to list commands.\n");
  return STATUS_USAGE;
}

int ms_version_command(const char *name, int argc, char **argv) {
  if (ms_cstr_equal(name, "version") && argc == 1 && (ms_cstr_equal(argv[0], "--help") || ms_cstr_equal(argv[0], "-h"))) {
    print_text(stdout, ms_help_page(ms_span_of_text("version")));
    return 0;
  }
  if (argc > 0) {
    (void)fprintf(stderr, "ms %s takes no arguments; use ms version or ms --version\n", name);
    return STATUS_USAGE;
  }
  (void)printf("Manuscript %s\n", MS_VERSION);
  return 0;
}
