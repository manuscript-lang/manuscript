/* cli/search_symbol_command.c: `ms search`. */
#include "cli/search_symbol_command.h"

#include <stdio.h>

#include "base/cstr.h"
#include "base/message.h"
#include "base/utf8.h"
#include "base/sort.h"
#include "base/strbuild.h"
#include "cli/invocation_rules.h"
#include "cli/search_project.h"
#include "tooling/guide.h"
#include "tooling/search_text.h"
#include "compiler/syntax/diag_json.h"

enum { DEFAULT_LIMIT = 5, MAX_LIMIT = 10, OUTPUT_BUDGET = 3500, USES_SHOWN = 5 };

typedef MsSymbolMatch Described;
typedef MsSymbolMatches DescribedList;
#define described_list_push ms_symbol_matches_push

static MsSpan clip(MsArena *arena, MsSpan text, size_t limit) {
  if (ms_utf8_count(text.ptr, text.len) <= limit) {
    return text;
  }
  return ms_message_format(arena, "%S\xE2\x80\xA6", ms_span_of(text.ptr, ms_utf8_offset_of(text.ptr, text.len, limit - 1)), (MsSpan){0});
}

/* ---- name_rank: how well a name matches a query ---- */

static MsSpan fold(MsArena *arena, MsSpan s) {
  MsStrBuild out = ms_strbuild_new();
  for (size_t i = 0; i < s.len; i++) {
    const uint8_t c = s.ptr[i];
    if (c == '_' || c == '.' || c == ' ') {
      continue;
    }
    ms_strbuild_append_byte(&out, c >= 'A' && c <= 'Z' ? (uint8_t)(c + 32) : c);
  }
  const MsSpan text = ms_message_take_builder(arena, &out);
  return text;
}

static int loose_rank(MsArena *arena, MsSpan name, MsSpan query) {
  if (query.len == 0) {
    return -1;
  }
  size_t at = 0;
  if (ms_span_equal(name, query)) {
    return 0;
  }
  if (ms_span_starts_with(name, query)) {
    return 1;
  }
  if (ms_span_find(name, query, &at)) {
    return 2;
  }
  if (query.len >= 3 && name.len > 0 && name.ptr[0] == query.ptr[0] && ms_text_is_subsequence(query, name)) {
    return 3;
  }
  if (query.len >= 5 && (ms_text_edit_distance(arena, name, query, 2) <= 2 ||
                         (name.len > query.len && ms_text_edit_distance(arena, ms_span_of(name.ptr, query.len), query, 2) <= 2))) {
    return 4;
  }
  return -1;
}

/* 0 exact, 1 prefix, 2 substring, 3 ordered subsequence, 4 near miss; -1 means no match. */
int ms_symbol_name_rank(MsArena *arena, MsSpan name, MsSpan query) {
  const MsSpan folded = fold(arena, query);
  MsSpan own = name;
  for (size_t i = name.len; i > 0; i--) {
    if (name.ptr[i - 1] == '.') {
      own = ms_span_of(name.ptr + i, name.len - i);
      break;
    }
  }
  int best = loose_rank(arena, fold(arena, name), folded);
  const int other = loose_rank(arena, fold(arena, own), folded);
  if (other >= 0 && (best < 0 || other < best)) {
    best = other;
  }
  return best;
}

/* ---- the standard-library matches ---- */

static int64_t compare_rank(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  return (int64_t)((const Described *)(const void *)a)->rank - (int64_t)((const Described *)(const void *)b)->rank;
}

static DescribedList library_matches(MsArena *arena, const MsGuide *guide, MsSpan query, size_t words, size_t limit, size_t project) {
  const MsGuideMatches concept = ms_guide_search(arena, guide, query, 50);
  DescribedList library = {0};
  for (size_t i = 0; i < concept.len; i++) {
    const MsGuideMatch *m = &concept.ptr[i];
    const int path = ms_symbol_name_rank(arena, m->path, query);
    const int own = ms_symbol_name_rank(arena, m->name, query);
    const int rank = own >= 0 && (path < 0 || own < path) ? own : path;
    if (rank < 0) {
      continue;
    }
    MsStrBuild effects = ms_strbuild_new();
    if (ms_span_is_text(m->kind, "fn") && m->effects.len > 0) {
      ms_strbuild_append_text(&effects, "effects: ");
      for (size_t e = 0; e < m->effects.len; e++) {
        ms_strbuild_append_text(&effects, e > 0 ? ", " : "");
        ms_strbuild_append(&effects, m->effects.ptr[e]);
      }
    }
    described_list_push(arena, &library,
                        (Described){.name = m->path, .kind = m->kind, .definition = ms_message_format(arena, "std:%S", m->module, (MsSpan){0}),
                                    .type = ms_text_one_spaced(arena, m->signature), .doc = m->doc,
                                    .effects = ms_arena_copy(arena, ms_strbuild_span(&effects)), .rank = (size_t)rank});
    ms_strbuild_free(&effects);
  }
  if (words > 1 || (library.len == 0 && project == 0)) {
    /* Words rather than a name: top up with the meaning-based ranking. */
    const size_t named = library.len;
    for (size_t i = 0; i < concept.len; i++) {
      bool seen = false;
      for (size_t k = 0; k < named && !seen; k++) {
        seen = ms_span_equal(library.ptr[k].name, concept.ptr[i].path);
      }
      if (seen) {
        continue;
      }
      const MsGuideMatch *m = &concept.ptr[i];
      MsStrBuild effects = ms_strbuild_new();
      if (ms_span_is_text(m->kind, "fn") && m->effects.len > 0) {
        ms_strbuild_append_text(&effects, "effects: ");
        for (size_t e = 0; e < m->effects.len; e++) {
          ms_strbuild_append_text(&effects, e > 0 ? ", " : "");
          ms_strbuild_append(&effects, m->effects.ptr[e]);
        }
      }
      described_list_push(arena, &library,
                          (Described){.name = m->path, .kind = m->kind, .definition = ms_message_format(arena, "std:%S", m->module, (MsSpan){0}),
                                      .type = ms_text_one_spaced(arena, m->signature), .doc = m->doc,
                                      .effects = ms_arena_copy(arena, ms_strbuild_span(&effects)), .rank = 5});
      ms_strbuild_free(&effects);
    }
  }
  if (library.len > 1) {
    ms_sort((uint8_t *)library.ptr, library.len, sizeof(Described), compare_rank, NULL);
  }
  if (library.len > limit) {
    library.len = limit;
  }
  return library;
}

static void print_uses(MsArena *arena, MsStrBuild *out, const MsSpans *uses) {
  ms_strbuild_append(out, ms_message_format(arena, "  used (%z)", uses->len));
  for (size_t i = 0; i < uses->len && i < USES_SHOWN; i++) {
    ms_strbuild_append_text(out, i == 0 ? ": " : ", ");
    ms_strbuild_append(out, uses->ptr[i]);
  }
  ms_strbuild_append_text(out, uses->len > USES_SHOWN ? ", ...\n" : "\n");
}

static void print_text(MsArena *arena, const DescribedList *described, size_t project_total) {
  MsStrBuild out = ms_strbuild_new();
  for (size_t i = 0; i < described->len; i++) {
    const Described *m = &described->ptr[i];
    ms_strbuild_append(&out, ms_message_format(arena, "%S  %S  %S\n", m->name, m->kind, m->definition));
    const MsSpan self = ms_message_format(arena, "%S %S", m->name, m->name);
    if (m->type.len > 0 && !ms_span_equal(m->type, self)) {
      ms_strbuild_append(&out, ms_message_format(arena, "  %S\n", clip(arena, m->type, 200), (MsSpan){0}));
    }
    if (m->doc.len > 0) {
      ms_strbuild_append(&out, ms_message_format(arena, "  // %S\n", clip(arena, ms_text_one_spaced(arena, m->doc), 160), (MsSpan){0}));
    }
    if (m->effects.len > 0) {
      ms_strbuild_append(&out, ms_message_format(arena, "  %S\n", m->effects, (MsSpan){0}));
    }
    if (m->project) {
      print_uses(arena, &out, &m->uses);
    } else {
      ms_strbuild_append(&out, ms_message_format(arena, "  details: ms search %S\n", m->name, (MsSpan){0}));
    }
  }
  size_t shown = 0;
  for (size_t i = 0; i < described->len; i++) {
    shown += described->ptr[i].project ? 1 : 0;
  }
  if (project_total > shown) {
    ms_strbuild_append(&out, ms_message_format(arena, "+%z more project matches; use a longer name or --limit\n", (project_total - shown)));
  }
  MsSpan text = ms_strbuild_span(&out);
  if (text.len > OUTPUT_BUDGET) {
    size_t cut = OUTPUT_BUDGET;
    while (cut > 0 && (text.ptr[cut] & 0xC0) == 0x80) {
      cut--;
    }
    (void)fwrite(text.ptr, 1, cut, stdout);
    (void)fputs("\n[... output cut; use a longer name ...]\n", stdout);
  } else {
    (void)fwrite(text.ptr, 1, text.len, stdout);
  }
  ms_strbuild_free(&out);
}

static void print_json(MsArena *scratch, MsSpan query, const DescribedList *described, size_t project_total) {
  MsStrBuild out = ms_strbuild_new();
  ms_strbuild_append_text(&out, "{\n  \"format\": 1,\n  \"query\": ");
  ms_json_string(&out, query);
  ms_strbuild_append(&out, ms_message_format(scratch, ",\n  \"project_total\": %z,\n  \"matches\": ", project_total));
  if (described->len == 0) {
    ms_strbuild_append_text(&out, "[]");
  } else {
    ms_strbuild_append_text(&out, "[\n");
    for (size_t i = 0; i < described->len; i++) {
      const Described *m = &described->ptr[i];
      ms_strbuild_append_text(&out, "    {\n      \"name\": ");
      ms_json_string(&out, m->name);
      ms_strbuild_append_text(&out, ",\n      \"kind\": ");
      ms_json_string(&out, m->kind);
      ms_strbuild_append_text(&out, ",\n      \"definition\": ");
      ms_json_string(&out, m->definition);
      if (m->type.len > 0) {
        ms_strbuild_append_text(&out, ",\n      \"type\": ");
        ms_json_string(&out, m->type);
      }
      if (m->doc.len > 0) {
        ms_strbuild_append_text(&out, ",\n      \"doc\": ");
        ms_json_string(&out, m->doc);
      }
      if (m->effects.len > 0) {
        ms_strbuild_append_text(&out, ",\n      \"effects\": ");
        ms_json_string(&out, m->effects);
      }
      if (m->project) {
        ms_strbuild_append_text(&out, ",\n      \"uses\": ");
        if (m->uses.len == 0) {
          ms_strbuild_append_text(&out, "[]");
        } else {
          ms_strbuild_append_text(&out, "[\n");
          for (size_t u = 0; u < m->uses.len; u++) {
            ms_strbuild_append_text(&out, "        ");
            ms_json_string(&out, m->uses.ptr[u]);
            ms_strbuild_append_text(&out, u + 1 < m->uses.len ? ",\n" : "\n");
          }
          ms_strbuild_append_text(&out, "      ]");
        }
      }
      ms_strbuild_append_text(&out, m->project ? ",\n      \"origin\": \"project\"\n    }" : ",\n      \"origin\": \"std\"\n    }");
      ms_strbuild_append_text(&out, i + 1 < described->len ? ",\n" : "\n");
    }
    ms_strbuild_append_text(&out, "  ]");
  }
  ms_strbuild_append_text(&out, "\n}\n");
  (void)fwrite(out.bytes.ptr, 1, out.bytes.len, stdout);
  ms_strbuild_free(&out);
}

int ms_search_symbol_command(int argc, char **argv) {
  MsArena arena = ms_arena_new();
  MsSpans names = {0};
  size_t limit = DEFAULT_LIMIT;
  bool json = false;
  int status = 0;
  for (int i = 0; i < argc && status == 0; i++) {
    MsSpan arg = ms_span_of_text(argv[i]);
    MsSpan inline_value = {0};
    bool has_inline = false;
    size_t at = 0;
    if (ms_span_starts_with_text(arg, "--limit=") && ms_span_find(arg, ms_span_of_text("="), &at)) {
      inline_value = ms_span_of(arg.ptr + at + 1, arg.len - at - 1);
      arg = ms_span_of_text("--limit");
      has_inline = true;
    }
    if (ms_span_is_text(arg, "--json")) {
      json = true;
    } else if (ms_span_is_text(arg, "--limit")) {
      MsSpan value = inline_value;
      if (!has_inline) {
        i++;
        value = i < argc ? ms_span_of_text(argv[i]) : (MsSpan){0};
      }
      int64_t n = 0;
      if (value.len == 0 || !ms_invocation_parse_int(value, &n) || n < 1) {
        status = ms_usage_error(&arena, ms_span_of_text("ms search: --limit needs a positive number, e.g. ms search Config --limit 3"));
      } else {
        limit = (size_t)n < MAX_LIMIT ? (size_t)n : MAX_LIMIT;
      }
    } else if (arg.len > 0 && arg.ptr[0] == '-') {
      status = ms_usage_error(&arena, ms_message_format(&arena, "unknown option %S for ms search; run 'ms help search' for its options", arg, (MsSpan){0}));
    } else {
      ms_spans_push(&arena, &names, arg);
    }
  }
  if (status != 0) {
    ms_arena_free(&arena);
    return status;
  }
  MsNames interned;
  ms_names_init(&interned);
  MsGuide guide = {0};
  ms_guide_build(&arena, &interned, &guide);
  bool blank = true;
  MsStrBuild joined = ms_strbuild_new();
  MsStrBuild concatenated = ms_strbuild_new();
  size_t words = names.len;
  for (size_t i = 0; i < names.len; i++) {
    MsSpan t = names.ptr[i];
    for (size_t k = 0; k < t.len; k++) {
      blank = blank && ms_text_is_blank(t.ptr[k]);
    }
    ms_strbuild_append_text(&joined, i > 0 ? " " : "");
    ms_strbuild_append(&joined, t);
    ms_strbuild_append(&concatenated, t);
  }
  const MsSpan project_query = ms_arena_copy(&arena, ms_strbuild_span(&concatenated));
  ms_strbuild_free(&concatenated);
  const MsSpan query = ms_arena_copy(&arena, ms_strbuild_span(&joined));
  ms_strbuild_free(&joined);
  if (blank) {
    const MsSpan index = ms_guide_index(&arena, &guide);
    (void)fwrite(index.ptr, 1, index.len, stdout);
  } else {
    MsSpan page = {0};
    MsSpan error = {0};
    size_t project_total = 0;
    DescribedList described = ms_search_project(&arena, project_query, limit, &project_total);
    bool exact = false;
    for (size_t i = 0; i < described.len; i++) {
      exact = exact || described.ptr[i].rank == 0;
    }
    if (words == 1 && !json && !exact && ms_guide_page(&arena, &guide, query, &page, &error)) {
      (void)fwrite(page.ptr, 1, page.len, stdout);
    } else {
      const DescribedList library = library_matches(&arena, &guide, query, words, limit - described.len, described.len);
      for (size_t i = 0; i < library.len; i++) {
        described_list_push(&arena, &described, library.ptr[i]);
      }
      if (json) {
        print_json(&arena, query, &described, project_total);
      } else if (described.len == 0) {
        (void)printf("No project or standard-library symbol like \"%.*s\". Try a shorter name.\n", (int)query.len,
                     (const char *)query.ptr);
      } else {
        print_text(&arena, &described, project_total);
      }
    }
  }
  ms_names_free(&interned);
  ms_arena_free(&arena);
  return 0;
}
