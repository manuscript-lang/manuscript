/* Owns `ms help` (explain_command.h): the rule family and usual repair of diagnostic and lint codes. */
#include "cli/explain_command.h"

#include <stdio.h>

#include "base/cstr.h"
#include "base/strbuild.h"
#include "compiler/syntax/diag.h"
#include "compiler/syntax/diag_json.h"
#include "tooling/lint_rules.h"

enum { STATUS_FAILED = 1, STATUS_USAGE = 2 };

/* One code's entry: a diagnostic code has no severity, a lint code has one. */
typedef struct Entry {
  const char *code, *family, *repair, *severity;
} Entry;

static bool find_entry(const char *code, Entry *entry) {
  const MsCodeInfo *info = ms_explain(code);
  if (info != NULL) {
    *entry = (Entry){info->code, info->family, info->repair, ""};
    return true;
  }
  const MsLintRule *rule = ms_lint_rule(ms_span_of_text(code));
  if (rule == NULL) {
    return false;
  }
  *entry = (Entry){rule->code, rule->family, rule->repair, rule->severity == MS_LINT_ERROR ? "error" : "warning"};
  return true;
}

static void print_entry(const Entry *entry) {
  if (entry->severity[0] == '\0') {
    (void)printf("%s: %s\n  repair: %s\n", entry->code, entry->family, entry->repair);
  } else {
    (void)printf("%s: %s (%s)\n  repair: %s\n", entry->code, entry->family, entry->severity, entry->repair);
  }
}

static void json_member(MsStrBuild *out, const char *name, const char *value, bool last) {
  ms_strbuild_append_text(out, "      \"");
  ms_strbuild_append_text(out, name);
  ms_strbuild_append_text(out, "\": ");
  ms_json_string(out, ms_span_of_text(value));
  ms_strbuild_append_text(out, last ? "\n" : ",\n");
}

static void append_json_entry(MsStrBuild *out, const Entry *entry, bool first) {
  ms_strbuild_append_text(out, first ? "\n    {\n" : ",\n    {\n");
  json_member(out, "code", entry->code, false);
  json_member(out, "family", entry->family, false);
  if (entry->severity[0] != '\0') {
    json_member(out, "severity", entry->severity, false);
  }
  json_member(out, "repair", entry->repair, true);
  ms_strbuild_append_text(out, "    }");
}

int ms_explain_command(int argc, char **argv) {
  bool json = false;
  for (int i = 0; i < argc; i++) {
    json = json || ms_cstr_equal(argv[i], "--json");
  }
  int codes = 0;
  int status = 0;
  MsStrBuild entries = ms_strbuild_new();
  for (int i = 0; i < argc; i++) {
    if (ms_cstr_equal(argv[i], "--json")) {
      continue;
    }
    codes++;
    Entry entry;
    if (!find_entry(argv[i], &entry)) {
      (void)fprintf(stderr, "ms help: unknown diagnostic code %s\n", argv[i]);
      status = STATUS_FAILED;
    } else if (json) {
      append_json_entry(&entries, &entry, ms_strbuild_length(&entries) == 0);
    } else {
      print_entry(&entry);
    }
  }
  if (codes == 0) {
    (void)fprintf(stderr, "ms help: pass a command name or at least one diagnostic code\n");
    status = STATUS_USAGE;
  } else if (json) {
    (void)printf("{\n  \"format\": 1,\n  \"codes\": [");
    (void)fwrite(ms_strbuild_span(&entries).ptr, 1, ms_strbuild_length(&entries), stdout);
    (void)printf("%s]\n}\n", ms_strbuild_length(&entries) == 0 ? "" : "\n  ");
  }
  ms_strbuild_free(&entries);
  return status;
}
