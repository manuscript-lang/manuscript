/* cli/doc_command.c: `ms dev doc`. The standard library's documentation snapshot (tooling/guide.h) as versioned JSON:
 * every importable module with its declarations, their source excerpts, descriptions, effects and members. The
 * book, the API downloads and the description coverage are built from it by tools/docgen.ms. */
#include "cli/doc_command.h"

#include <stdio.h>

#include "base/cstr.h"
#include "base/message.h"
#include "base/strbuild.h"
#include "cli/invocation_rules.h"
#include "compiler/syntax/diag_json.h"
#include "tooling/guide.h"

enum { DOC_FORMAT = 2 };

/* `,\n<indent>"key": "value"`, left out when the value is empty and `always` is false. */
static void field(MsStrBuild *out, const char *indent, const char *key, MsSpan value, bool always) {
  if (value.len == 0 && !always) {
    return;
  }
  ms_strbuild_append_text(out, ",\n");
  ms_strbuild_append_text(out, indent);
  ms_strbuild_append_byte(out, '"');
  ms_strbuild_append_text(out, key);
  ms_strbuild_append_text(out, "\": ");
  ms_json_string(out, value);
}

static void member_json(MsStrBuild *out, const MsApiMember *m) {
  ms_strbuild_append_text(out, "          {\n            \"name\": ");
  ms_json_string(out, m->name);
  field(out, "            ", "kind", m->kind, true);
  field(out, "            ", "signature", m->signature, true);
  field(out, "            ", "doc", m->doc, true);
  field(out, "            ", "contract", m->contract, false);
  ms_strbuild_append_text(out, "\n          }");
}

static void declaration_json(MsStrBuild *out, const MsApiDecl *d) {
  ms_strbuild_append_text(out, "        {\n          \"name\": ");
  ms_json_string(out, d->name);
  field(out, "          ", "kind", d->kind, true);
  field(out, "          ", "doc", d->doc, false);
  if (d->opaque) {
    ms_strbuild_append_text(out, ",\n          \"opaque\": true");
  }
  field(out, "          ", "declaration", d->declaration, true);
  if (d->effects.len > 0) {
    ms_strbuild_append_text(out, ",\n          \"effects\": [");
    for (size_t i = 0; i < d->effects.len; i++) {
      ms_strbuild_append_text(out, i > 0 ? ", " : "");
      ms_json_string(out, d->effects.ptr[i]);
    }
    ms_strbuild_append_byte(out, ']');
  }
  if (d->members.len > 0) {
    ms_strbuild_append_text(out, ",\n          \"members\": [\n");
    for (size_t i = 0; i < d->members.len; i++) {
      member_json(out, &d->members.ptr[i]);
      ms_strbuild_append_text(out, i + 1 < d->members.len ? ",\n" : "\n");
    }
    ms_strbuild_append_text(out, "          ]");
  }
  ms_strbuild_append_text(out, "\n        }");
}

int ms_doc_command(int argc, char **argv) {
  MsArena arena = ms_arena_new();
  if (argc > 0) {
    const int status = ms_usage_error(&arena, ms_message_format(&arena, "ms dev doc takes no arguments, got %S; run 'ms help dev'",
                                                                ms_span_of_text(argv[0]), (MsSpan){0}));
    ms_arena_free(&arena);
    return status;
  }
  MsNames names;
  ms_names_init(&names);
  MsGuide guide = {0};
  ms_guide_build(&arena, &names, &guide);
  MsStrBuild out = ms_strbuild_new();
  ms_strbuild_append(&out, ms_message_format(&arena, "{\n  \"format\": %z,\n  \"modules\": [\n", (size_t)DOC_FORMAT));
  for (size_t m = 0; m < guide.count; m++) {
    const MsApiModule *module = &guide.modules[m];
    ms_strbuild_append_text(&out, "    {\n      \"path\": ");
    ms_json_string(&out, module->path);
    ms_strbuild_append_text(&out, ",\n      \"declarations\": [\n");
    for (size_t d = 0; d < module->decls.len; d++) {
      declaration_json(&out, &module->decls.ptr[d]);
      ms_strbuild_append_text(&out, d + 1 < module->decls.len ? ",\n" : "\n");
    }
    ms_strbuild_append_text(&out, m + 1 < guide.count ? "      ]\n    },\n" : "      ]\n    }\n");
  }
  ms_strbuild_append_text(&out, "  ]\n}\n");
  (void)fwrite(out.bytes.ptr, 1, out.bytes.len, stdout);
  ms_strbuild_free(&out);
  ms_names_free(&names);
  ms_arena_free(&arena);
  return 0;
}
