/* Owns report.h. */
#include "tooling/report.h"

#include "base/sha256.h"
#include "base/message.h"
#include "compiler/check/effects_directives.h"
#include "compiler/syntax/diag_json.h"
#include "tooling/review.h"

enum { ROW_CAP = 5 };

static MsSpan text(const char *literal) {
  return ms_span_of_text(literal);
}

/* A section of a table: the first ROW_CAP rows unless `all`. */
static MsSection table(MsArena *arena, const char *title, const char *const *headers, size_t columns, const MsSpans *cells,
                       MsReviewOptions options) {
  MsSection section = {.title = text(title)};
  for (size_t i = 0; i < columns; i++) {
    ms_spans_push(arena, &section.headers, text(headers[i]));
  }
  const size_t rows = cells->len / columns;
  const size_t shown = options.all || rows <= ROW_CAP ? rows : ROW_CAP;
  for (size_t i = 0; i < shown * columns; i++) {
    ms_spans_push(arena, &section.cells, cells->ptr[i]);
  }
  section.more = rows - shown;
  return section;
}

static MsSection lines_section(const char *title, MsSpans lines) {
  return (MsSection){.title = text(title), .lines = lines};
}

static MsSection limits_section(MsArena *arena) {
  MsSpans lines = {0};
  ms_spans_push(arena, &lines, text("Static analysis of checked source; tests are not run."));
  ms_spans_push(arena, &lines,
                text("INTERNAL means no tracked contract, effect, error-flow, or resource change; runtime behavior can still "
                     "change."));
  ms_spans_push(arena, &lines, text("Use --explain <number|id> with --diff for evidence and a focused diagram."));
  return lines_section("READING THIS REPORT", lines);
}

static MsSection import_map(MsArena *arena, const MsFactModel *head) {
  MsSpans lines = {0};
  for (size_t i = 0; i < head->imports.len; i++) {
    const MsImports *imports = &head->imports.ptr[i];
    MsStrBuild paths = ms_strbuild_new();
    for (size_t p = 0; p < imports->paths.len; p++) {
      ms_strbuild_append_text(&paths, p == 0 ? "" : ", ");
      ms_strbuild_append(&paths, imports->paths.ptr[p]);
    }
    ms_spans_push(arena, &lines,
                  ms_message_format(arena, "%S imports %S", imports->file, imports->paths.len == 0 ? text("none") : ms_strbuild_span(&paths)));
    ms_strbuild_free(&paths);
  }
  return lines_section("DEPENDENCIES", lines);
}

static MsSpan number(MsArena *arena, size_t n) {
  return ms_message_format(arena, "%z", n);
}

static void push_row_line(MsArena *arena, MsSpans *lines, const char *label, size_t n) {
  ms_spans_push(arena, lines, ms_message_format(arena, "%s%z", label, n));
}

/* The digest is the SHA-256 of the ascii body, so equal digests mean equal reports. */
static void body(MsArena *arena, const MsReport *report, bool markdown, MsStrBuild *out);

MsReport ms_project_report(MsArena *arena, const MsFactModel *head, MsReviewOptions options) {
  MsReport r = {.mode = text("project"), .input = text("project (no diff)")};
  size_t exported = 0;
  size_t tests = 0;
  size_t scopes = 0;
  MsSpans files = {0};
  for (size_t i = 0; i < head->entities.len; i++) {
    const MsFact *f = &head->entities.ptr[i];
    exported += f->exported ? 1 : 0;
    tests += ms_span_is_text(f->kind, "test") ? 1 : 0;
    scopes += f->scopes > 0 ? 1 : 0;
    if (!ms_spans_contains(&files, f->file)) {
      ms_spans_push(arena, &files, f->file);
    }
  }
  for (size_t i = 0; i < head->imports.len; i++) {
    if (!ms_spans_contains(&files, head->imports.ptr[i].file)) {
      ms_spans_push(arena, &files, head->imports.ptr[i].file);
    }
  }
  r.result = ms_message_format(arena, "%z modules, %z entities", files.len, head->entities.len);
  MsSpans summary = {0};
  push_row_line(arena, &summary, "modules               ", files.len);
  push_row_line(arena, &summary, "entities              ", head->entities.len);
  push_row_line(arena, &summary, "exported              ", exported);
  push_row_line(arena, &summary, "tests                 ", tests);
  push_row_line(arena, &summary, "resource scopes       ", scopes);
  MsSpans surface = {0};
  MsSpans entries = {0};
  MsSpans resources = {0};
  MsSpans error_types = {0}; /* in first-seen order; sorted below */
  size_t *error_counts = MS_ARENA_NEW_ARRAY(arena, size_t, head->entities.len + 1);
  for (size_t i = 0; i < head->entities.len; i++) {
    const MsFact *f = &head->entities.ptr[i];
    const MsSpan at = ms_message_format(arena, "%S:%z", f->file, f->line);
    if (f->exported) {
      ms_spans_push(arena, &surface, f->name);
      ms_spans_push(arena, &surface, f->kind);
      ms_spans_push(arena, &surface, f->ty);
      ms_spans_push(arena, &surface, at);
    }
    if ((ms_span_is_text(f->name, "main") && f->exported) || ms_span_is_text(f->kind, "test")) {
      ms_spans_push(arena, &entries, f->name);
      ms_spans_push(arena, &entries, f->kind);
      ms_spans_push(arena, &entries, ms_effects_joined(arena, &f->effects));
      ms_spans_push(arena, &entries, at);
    }
    if (f->scopes > 0) {
      ms_spans_push(arena, &resources, f->name);
      ms_spans_push(arena, &resources, number(arena, f->scopes));
      ms_spans_push(arena, &resources, at);
    }
    if (f->error.len > 0) {
      size_t at_index = error_types.len;
      for (size_t k = 0; k < error_types.len; k++) {
        if (ms_span_equal(error_types.ptr[k], f->error)) {
          at_index = k;
        }
      }
      if (at_index == error_types.len) {
        ms_spans_push(arena, &error_types, f->error);
      }
      error_counts[at_index]++;
    }
  }
  /* BTreeMap order: by error text, bytewise */
  MsSpans errors = {0};
  for (size_t placed = 0; placed < error_types.len; placed++) {
    size_t best = error_types.len;
    for (size_t k = 0; k < error_types.len; k++) {
      if (error_types.ptr[k].len == 0 && error_counts[k] == 0) {
        continue;
      }
      if (best == error_types.len || ms_span_compare(error_types.ptr[k], error_types.ptr[best]) < 0) {
        best = k;
      }
    }
    ms_spans_push(arena, &errors, error_types.ptr[best]);
    ms_spans_push(arena, &errors, number(arena, error_counts[best]));
    error_types.ptr[best] = (MsSpan){0};
    error_counts[best] = 0;
  }
  static const char *const SURFACE[] = {"ENTITY", "KIND", "TYPE", "WHERE"};
  static const char *const ENTRIES[] = {"ENTITY", "KIND", "EFFECTS", "WHERE"};
  static const char *const ERRORS[] = {"TYPE", "FUNCTIONS"};
  static const char *const RESOURCES[] = {"ENTITY", "WITH", "WHERE"};
  ms_sections_push(arena, &r.sections, lines_section("SUMMARY", summary));
  ms_sections_push(arena, &r.sections, table(arena, "PUBLIC SURFACE", SURFACE, 4, &surface, options));
  ms_sections_push(arena, &r.sections, table(arena, "ENTRY POINTS", ENTRIES, 4, &entries, options));
  ms_sections_push(arena, &r.sections, table(arena, "ERROR TYPES", ERRORS, 2, &errors, options));
  ms_sections_push(arena, &r.sections, table(arena, "RESOURCES", RESOURCES, 3, &resources, options));
  ms_sections_push(arena, &r.sections, import_map(arena, head));
  ms_sections_push(arena, &r.sections, limits_section(arena));
  MsStrBuild ascii = ms_strbuild_new();
  body(arena, &r, false, &ascii);
  uint8_t hex[MS_SHA256_HEX_LEN];
  ms_sha256_hex(ms_strbuild_span(&ascii), hex);
  r.digest = ms_message_format(arena, "sha256:%S", ms_span_of(hex, MS_SHA256_HEX_LEN));
  ms_strbuild_free(&ascii);
  return r;
}

/* ---- diff reports ---- */

/* Whether an effect row of the finding (`permits: + std.fs.*`, `reaches: + std.net.connect`) lists `effect`, or a
 * listed name matches `effect` read as a pattern. */
static bool names_effect(const MsFinding *finding, MsSpan effect) {
  for (size_t c = 0; c < finding->changes.len; c++) {
    MsSpan change = finding->changes.ptr[c];
    if (ms_span_starts_with(change, text("permits: + "))) {
      change = ms_span_of(change.ptr + 11, change.len - 11);
    } else if (ms_span_starts_with(change, text("reaches: + "))) {
      change = ms_span_of(change.ptr + 11, change.len - 11);
    } else {
      continue;
    }
    size_t start = 0;
    for (size_t i = 0; i <= change.len; i++) {
      if (i == change.len || (change.ptr[i] == ',' && i + 1 < change.len && change.ptr[i + 1] == ' ')) {
        const MsSpan name = ms_span_of(change.ptr + start, i - start);
        if (ms_span_equal(name, effect) || ms_effect_matches(effect, name)) {
          return true;
        }
        start = i + 2;
      }
    }
  }
  return false;
}

static MsSection capped_lines(MsArena *arena, const char *title, const MsSpans *lines, MsReviewOptions options) {
  MsSection section = {.title = text(title)};
  const size_t shown = options.all || lines->len <= ROW_CAP ? lines->len : ROW_CAP;
  for (size_t i = 0; i < shown; i++) {
    ms_spans_push(arena, &section.lines, lines->ptr[i]);
  }
  section.more = lines->len - shown;
  return section;
}

static bool is_internal(const MsFinding *f);
static void json_finding(MsStrBuild *out, const MsFinding *f, size_t number, size_t depth, bool with_number);

static bool starts_any(MsSpan change, const char *const *prefixes, size_t count) {
  for (size_t i = 0; i < count; i++) {
    if (ms_span_starts_with(change, text(prefixes[i]))) {
      return true;
    }
  }
  return false;
}

/* Entities whose reasons include the tier's prefixes, including those ranked into other tiers. */
static MsSection tier_section(MsArena *arena, const char *title, const char *const *prefixes, size_t count,
                              const MsFindings *findings, MsReviewOptions options) {
  MsSpans lines = {0};
  for (size_t f = 0; f < findings->len; f++) {
    const MsFinding *finding = &findings->ptr[f];
    for (size_t c = 0; c < finding->changes.len; c++) {
      for (size_t p = 0; p < count; p++) {
        if (ms_span_starts_with(finding->changes.ptr[c], text(prefixes[p]))) {
          ms_spans_push(arena, &lines, ms_message_format(arena, "%S %S", finding->entity, finding->changes.ptr[c]));
        }
      }
    }
  }
  return capped_lines(arena, title, &lines, options);
}

static const MsImports *imports_of(const MsFactModel *model, MsSpan file) {
  for (size_t i = 0; i < model->imports.len; i++) {
    if (ms_span_equal(model->imports.ptr[i].file, file)) {
      return &model->imports.ptr[i];
    }
  }
  return NULL;
}

static MsSection import_section(MsArena *arena, const MsFactModel *base, const MsFactModel *head) {
  MsSpans lines = {0};
  MsSpans names = {0};
  for (size_t i = 0; i < base->imports.len; i++) {
    ms_spans_push(arena, &names, base->imports.ptr[i].file);
  }
  for (size_t i = 0; i < head->imports.len; i++) {
    if (!ms_spans_contains(&names, head->imports.ptr[i].file)) {
      ms_spans_push(arena, &names, head->imports.ptr[i].file);
    }
  }
  /* sorted by file */
  for (size_t i = 1; i < names.len; i++) {
    for (size_t j = i; j > 0 && ms_span_compare(names.ptr[j - 1], names.ptr[j]) > 0; j--) {
      const MsSpan t = names.ptr[j];
      names.ptr[j] = names.ptr[j - 1];
      names.ptr[j - 1] = t;
    }
  }
  for (size_t n = 0; n < names.len; n++) {
    const MsImports *old = imports_of(base, names.ptr[n]);
    const MsImports *now = imports_of(head, names.ptr[n]);
    if (now != NULL) {
      for (size_t p = 0; p < now->paths.len; p++) {
        if (old == NULL || !ms_spans_contains(&old->paths, now->paths.ptr[p])) {
          ms_spans_push(arena, &lines, ms_message_format(arena, "+ %S imports %S", names.ptr[n], now->paths.ptr[p]));
        }
      }
    }
    if (old != NULL) {
      for (size_t p = 0; p < old->paths.len; p++) {
        if (now == NULL || !ms_spans_contains(&now->paths, old->paths.ptr[p])) {
          ms_spans_push(arena, &lines, ms_message_format(arena, "- %S imports %S", names.ptr[n], old->paths.ptr[p]));
        }
      }
    }
  }
  return lines_section("DEPENDENCIES", lines);
}

static MsSection internal_section(MsArena *arena, const MsFindings *findings, MsReviewOptions options) {
  MsSpans lines = {0};
  for (size_t i = 0; i < findings->len; i++) {
    const MsFinding *f = &findings->ptr[i];
    if (ms_span_is_text(f->tier, "INTERNAL")) {
      ms_spans_push(arena, &lines, ms_message_format(arena, "%S (%S)", f->entity, ms_spans_joined(arena, &f->changes, "; ")));
    }
  }
  for (size_t i = 1; i < lines.len; i++) {
    for (size_t j = i; j > 0 && ms_span_compare(lines.ptr[j - 1], lines.ptr[j]) > 0; j--) {
      const MsSpan t = lines.ptr[j];
      lines.ptr[j] = lines.ptr[j - 1];
      lines.ptr[j - 1] = t;
    }
  }
  return capped_lines(arena, "INTERNAL", &lines, options);
}

MsReport ms_diff_report(MsArena *arena, const MsFactModel *base, const MsFactModel *head, const MsDiffInput *input,
                        MsReviewOptions options) {
  MsFindings all = ms_compare_facts(arena, base, head, input);
  MsFindings findings = {0};
  for (size_t i = 0; i < all.len; i++) {
    if (options.effect.len == 0 || names_effect(&all.ptr[i], options.effect)) {
      ms_findings_push(arena, &findings, all.ptr[i]);
    }
  }
  size_t counts[5] = {0};
  size_t attention = 0;
  const char *const tiers[] = {"CONTRACT", "EFFECT+", "ERROR", "RESOURCE", "INTERNAL"};
  for (size_t i = 0; i < findings.len; i++) {
    for (size_t t = 0; t < 5; t++) {
      counts[t] += ms_span_is_text(findings.ptr[i].tier, tiers[t]) ? 1 : 0;
    }
    attention += is_internal(&findings.ptr[i]) ? 0 : 1;
  }
  MsReport r = {.mode = text("diff"), .has_base = true, .base_checked = input->base_checked};
  r.input = ms_message_format(arena, "diff (%z files, %z source, +%z -%z)", input->files, input->sources, input->insertions,
                              input->deletions);
  if (!input->base_checked) {
    r.result = text("base did not check; semantic comparison unavailable");
  } else if (findings.len == 0) {
    r.result = text("no tracked semantic changes");
  } else {
    r.result = ms_message_format(arena, "%z need attention, %z internal", attention, counts[4]);
  }
  MsSpans summary = {0};
  push_row_line(arena, &summary, "changed entities      ", findings.len);
  push_row_line(arena, &summary, "contract              ", counts[0]);
  push_row_line(arena, &summary, "effect                ", counts[1]);
  push_row_line(arena, &summary, "error flow            ", counts[2]);
  push_row_line(arena, &summary, "resource              ", counts[3]);
  push_row_line(arena, &summary, "internal only         ", counts[4]);
  MsSpans rows = {0};
  MsSpans evidence = {0};
  size_t row = 0;
  for (size_t i = 0; i < findings.len; i++) {
    const MsFinding *f = &findings.ptr[i];
    if (is_internal(f)) {
      continue;
    }
    row++;
    ms_spans_push(arena, &rows, number(arena, row));
    ms_spans_push(arena, &rows, f->tier);
    ms_spans_push(arena, &rows, f->entity);
    ms_spans_push(arena, &rows, ms_spans_joined(arena, &f->changes, "; "));
    ms_spans_push(arena, &rows, number(arena, f->reach));
    ms_spans_push(arena, &rows, f->location);
    ms_spans_push(arena, &rows, ms_message_format(arena, "%z", (size_t)f->score));
    MsSpans detail = {0};
    ms_spans_push(arena, &detail, ms_message_format(arena, "id: %S", f->id));
    for (size_t e = 0; e < f->evidence.len; e++) {
      ms_spans_push(arena, &detail, f->evidence.ptr[e]);
    }
    ms_spans_push(arena, &detail, ms_message_format(arena, "score: %S", ms_spans_joined(arena, &f->terms, ", ")));
    ms_spans_push(arena, &evidence, number(arena, row));
    ms_spans_push(arena, &evidence, ms_spans_joined(arena, &detail, " | "));
  }
  static const char *const LOOK[] = {"#", "TIER", "ENTITY", "CHANGE", "REACH", "WHERE", "SCORE"};
  static const char *const EVIDENCE[] = {"#", "DETAIL"};
  static const char *const EFFECTS[] = {"effects:"};
  static const char *const ERRORS[] = {"error type:", "try sites:"};
  static const char *const RESOURCES[] = {"resource scopes:"};
  ms_sections_push(arena, &r.sections, lines_section("SUMMARY", summary));
  ms_sections_push(arena, &r.sections, table(arena, "LOOK HERE FIRST", LOOK, 7, &rows, options));
  MsSection ev = table(arena, "EVIDENCE", EVIDENCE, 2, &evidence, options);
  ev.more = 0;
  ms_sections_push(arena, &r.sections, ev);
  ms_sections_push(arena, &r.sections, tier_section(arena, "EFFECTS", EFFECTS, 1, &findings, options));
  ms_sections_push(arena, &r.sections, tier_section(arena, "ERROR FLOW", ERRORS, 2, &findings, options));
  ms_sections_push(arena, &r.sections, tier_section(arena, "RESOURCES", RESOURCES, 1, &findings, options));
  ms_sections_push(arena, &r.sections, import_section(arena, base, head));
  ms_sections_push(arena, &r.sections, internal_section(arena, &findings, options));
  ms_sections_push(arena, &r.sections, limits_section(arena));
  r.findings = findings;
  MsStrBuild ascii = ms_strbuild_new();
  body(arena, &r, false, &ascii);
  uint8_t hex[MS_SHA256_HEX_LEN];
  ms_sha256_hex(ms_strbuild_span(&ascii), hex);
  r.digest = ms_message_format(arena, "sha256:%S", ms_span_of(hex, MS_SHA256_HEX_LEN));
  ms_strbuild_free(&ascii);
  (void)starts_any;
  return r;
}

/* ---- explain ---- */

static bool parse_integer(MsSpan s, int64_t *out) {
  size_t at = 0;
  bool negative = false;
  if (s.len > 0 && (s.ptr[0] == '-' || s.ptr[0] == '+')) {
    negative = s.ptr[0] == '-';
    at = 1;
  }
  if (at >= s.len || s.len - at > 17) {
    return false;
  }
  int64_t value = 0;
  for (; at < s.len; at++) {
    if (s.ptr[at] < '0' || s.ptr[at] > '9') {
      return false;
    }
    value = value * 10 + (s.ptr[at] - '0');
  }
  *out = negative ? -value : value;
  return true;
}

/* The finding a selector names, and its LOOK HERE FIRST number (0 for an internal one). */
static const MsFinding *select_finding(MsArena *arena, const MsFindings *findings, MsSpan selector, size_t *number,
                                       MsSpan *error) {
  size_t attention = 0;
  for (size_t i = 0; i < findings->len; i++) {
    attention += is_internal(&findings->ptr[i]) ? 0 : 1;
  }
  int64_t n = 0;
  if (parse_integer(selector, &n)) {
    if (n < 1 || n > (int64_t)attention) {
      *error = ms_message_format(arena, "no finding %S; LOOK HERE FIRST numbers run 1 to %z", selector, attention);
      if (n < 1 || n > (int64_t)attention) {
        MsStrBuild shown = ms_strbuild_new();
        ms_strbuild_append_i64(&shown, n);
        *error = ms_message_format(arena, "no finding %S; LOOK HERE FIRST numbers run 1 to %z", ms_strbuild_span(&shown), attention);
        ms_strbuild_free(&shown);
      }
      return NULL;
    }
    size_t seen_count = 0;
    for (size_t i = 0; i < findings->len; i++) {
      if (!is_internal(&findings->ptr[i]) && ++seen_count == (size_t)n) {
        *number = (size_t)n;
        return &findings->ptr[i];
      }
    }
  }
  const MsFinding *found = NULL;
  for (size_t i = 0; i < findings->len && found == NULL; i++) {
    found = ms_span_equal(findings->ptr[i].id, selector) ? &findings->ptr[i] : NULL;
  }
  if (found == NULL) {
    size_t matches = 0;
    for (size_t i = 0; i < findings->len; i++) {
      if (ms_span_equal(findings->ptr[i].entity, selector)) {
        matches++;
        found = found == NULL ? &findings->ptr[i] : found;
      }
    }
    if (matches > 1) {
      *error = ms_message_format(arena, "finding \"%S\" is ambiguous; pass a number from LOOK HERE FIRST or a full finding id", selector);
      return NULL;
    }
    if (found == NULL) {
      *error = ms_message_format(arena, "no finding \"%S\"; pass a number from LOOK HERE FIRST or a finding id", selector);
      return NULL;
    }
  }
  size_t position = 0;
  *number = 0;
  for (size_t i = 0; i < findings->len; i++) {
    if (is_internal(&findings->ptr[i])) {
      continue;
    }
    position++;
    if (ms_span_equal(findings->ptr[i].id, found->id)) {
      *number = position;
      break;
    }
  }
  return found;
}

static bool diagram_available(const MsFinding *found, const MsFactModel *head) {
  const MsFact *f = ms_fact_find(head, found->id);
  return f != NULL && (ms_span_is_text(f->kind, "fn") || ms_span_is_text(f->kind, "method") || ms_span_is_text(f->kind, "test"));
}

bool ms_review_explain(MsArena *arena, const MsFindings *findings, const MsFactModel *head, MsSpan selector, MsStrBuild *out,
                MsSpan *error) {
  size_t number = 0;
  const MsFinding *found = select_finding(arena, findings, selector, &number, error);
  if (found == NULL) {
    return false;
  }
  if (number > 0) {
    ms_strbuild_append(out, ms_message_format(arena, "EXPLAIN #%z %S\n", number, found->entity));
  } else {
    ms_strbuild_append(out, ms_message_format(arena, "EXPLAIN %S\n", found->entity));
  }
  ms_strbuild_printf(out, "report format %d\n\n", MS_REPORT_FORMAT);
  ms_strbuild_append(out, ms_message_format(arena, "id       %S\ntier     %S\nwhere    %S\nreach    %z\nscore    ", found->id,
                                            found->tier, found->location, found->reach));
  ms_strbuild_printf(out, "%lld\n", (long long)found->score);
  ms_strbuild_append_text(out, "\nWHY\n");
  for (size_t i = 0; i < found->changes.len; i++) {
    ms_strbuild_append(out, ms_message_format(arena, "  change   %S\n", found->changes.ptr[i]));
  }
  for (size_t i = 0; i < found->terms.len; i++) {
    ms_strbuild_append(out, ms_message_format(arena, "  term     %S\n", found->terms.ptr[i]));
  }
  ms_strbuild_append_text(out, "\nEVIDENCE\n");
  if (found->evidence.len == 0) {
    ms_strbuild_append_text(out, "  none\n");
  }
  for (size_t i = 0; i < found->evidence.len; i++) {
    ms_strbuild_append(out, ms_message_format(arena, "  %S\n", found->evidence.ptr[i]));
  }
  ms_strbuild_append_text(out, "\nCALLERS\n");
  MsSpans callers = {0};
  for (size_t i = 0; i < head->entities.len; i++) {
    const MsFact *fact = &head->entities.ptr[i];
    for (size_t c = 0; c < fact->calls.len; c++) {
      if (ms_span_equal(fact->calls.ptr[c], found->id)) {
        ms_spans_push(arena, &callers, ms_message_format(arena, "%S  %S:%z", fact->name, fact->file, fact->line));
      }
    }
  }
  for (size_t i = 1; i < callers.len; i++) {
    for (size_t j = i; j > 0 && ms_span_compare(callers.ptr[j - 1], callers.ptr[j]) > 0; j--) {
      const MsSpan t = callers.ptr[j];
      callers.ptr[j] = callers.ptr[j - 1];
      callers.ptr[j - 1] = t;
    }
  }
  if (callers.len == 0) {
    ms_strbuild_append_text(out, "  none\n");
  }
  for (size_t i = 0; i < callers.len; i++) {
    ms_strbuild_append(out, ms_message_format(arena, "  %S\n", callers.ptr[i]));
  }
  if (diagram_available(found, head)) {
    MsStrBuild quoted = ms_strbuild_new();
    for (size_t i = 0; i < found->id.len; i++) {
      if (found->id.ptr[i] == '\'') {
        ms_strbuild_append_text(&quoted, "'\\''");
      } else {
        ms_strbuild_append_byte(&quoted, found->id.ptr[i]);
      }
    }
    ms_strbuild_append(out, ms_message_format(arena, "\nNEXT\n  ms map <project> --view flow --entity '%S' --diff <diff>\n",
                                              ms_strbuild_span(&quoted)));
    ms_strbuild_free(&quoted);
  } else {
    ms_strbuild_append_text(out, "\nNEXT\n  Inspect the declaration in the diff and its callers; no flow exists for this entity in the current "
                                 "tree.\n");
  }
  return true;
}

bool ms_review_explain_json(MsArena *arena, const MsFindings *findings, const MsFactModel *head, MsSpan selector, MsStrBuild *out,
                     MsSpan *error) {
  size_t number = 0;
  const MsFinding *found = select_finding(arena, findings, selector, &number, error);
  if (found == NULL) {
    return false;
  }
  ms_strbuild_printf(out, "{\n  \"format\": %d,\n  \"number\": ", MS_REPORT_FORMAT);
  if (number == 0) {
    ms_strbuild_append_text(out, "null");
  } else {
    ms_strbuild_printf(out, "%zu", number);
  }
  ms_strbuild_append_text(out, ",\n  \"finding\": ");
  json_finding(out, found, 0, 1, false);
  ms_strbuild_append_text(out, ",\n  \"callers\": ");
  size_t count = 0;
  for (size_t i = 0; i < head->entities.len; i++) {
    for (size_t c = 0; c < head->entities.ptr[i].calls.len; c++) {
      count += ms_span_equal(head->entities.ptr[i].calls.ptr[c], found->id) ? 1 : 0;
    }
  }
  if (count == 0) {
    ms_strbuild_append_text(out, "[]");
  } else {
    ms_strbuild_append_text(out, "[\n");
    size_t shown = 0;
    for (size_t i = 0; i < head->entities.len; i++) {
      const MsFact *f = &head->entities.ptr[i];
      bool calls = false;
      for (size_t c = 0; c < f->calls.len; c++) {
        calls = calls || ms_span_equal(f->calls.ptr[c], found->id);
      }
      if (!calls) {
        continue;
      }
      ms_strbuild_append_text(out, "    {\n      \"id\": ");
      ms_json_string(out, f->key);
      ms_strbuild_append_text(out, ",\n      \"entity\": ");
      ms_json_string(out, f->name);
      ms_strbuild_append_text(out, ",\n      \"file\": ");
      ms_json_string(out, f->file);
      ms_strbuild_printf(out, ",\n      \"line\": %zu\n    }", f->line);
      ms_strbuild_append_text(out, ++shown < count ? ",\n" : "\n");
    }
    ms_strbuild_append_text(out, "  ]");
  }
  ms_strbuild_append_text(out, ",\n  \"diagram\": ");
  if (diagram_available(found, head)) {
    ms_strbuild_append_text(out, "{\n    \"view\": \"flow\",\n    \"entity\": ");
    ms_json_string(out, found->id);
    ms_strbuild_append_text(out, "\n  }");
  } else {
    ms_strbuild_append_text(out, "null");
  }
  ms_strbuild_append_text(out, "\n}\n\n");
  return true;
}

/* ---- rendering ---- */

static void write_table(MsStrBuild *out, const MsSection *s, bool markdown) {
  const size_t columns = s->headers.len;
  const size_t rows = s->cells.len / columns;
  if (markdown) {
    ms_strbuild_append_text(out, "| ");
    for (size_t c = 0; c < columns; c++) {
      ms_strbuild_append_text(out, c == 0 ? "" : " | ");
      ms_strbuild_append(out, s->headers.ptr[c]);
    }
    ms_strbuild_append_text(out, " |\n|");
    for (size_t c = 0; c < columns; c++) {
      ms_strbuild_append_text(out, " --- |");
    }
    ms_strbuild_append_text(out, "\n");
    for (size_t r = 0; r < rows; r++) {
      ms_strbuild_append_text(out, "| ");
      for (size_t c = 0; c < columns; c++) {
        ms_strbuild_append_text(out, c == 0 ? "" : " | ");
        const MsSpan cell = s->cells.ptr[r * columns + c];
        for (size_t k = 0; k < cell.len; k++) {
          if (cell.ptr[k] == '|') {
            ms_strbuild_append_byte(out, '\\');
          }
          ms_strbuild_append_byte(out, cell.ptr[k]);
        }
      }
      ms_strbuild_append_text(out, " |\n");
    }
    return;
  }
  /* Go pads by byte length, so widths count bytes. */
  size_t widths[16] = {0};
  for (size_t c = 0; c < columns && c < 16; c++) {
    widths[c] = s->headers.ptr[c].len;
    for (size_t r = 0; r < rows; r++) {
      const size_t n = s->cells.ptr[r * columns + c].len;
      widths[c] = n > widths[c] ? n : widths[c];
    }
  }
  for (size_t r = 0; r <= rows; r++) {
    ms_strbuild_append_text(out, "   ");
    for (size_t c = 0; c < columns; c++) {
      const MsSpan cell = r == 0 ? s->headers.ptr[c] : s->cells.ptr[(r - 1) * columns + c];
      ms_strbuild_append(out, cell);
      if (c + 1 < columns) {
        for (size_t k = cell.len; k < widths[c] + 2; k++) {
          ms_strbuild_append_byte(out, ' ');
        }
      }
    }
    ms_strbuild_append_text(out, "\n");
  }
}

static void write_section(MsArena *arena, MsStrBuild *out, const MsSection *s, bool markdown) {
  const char *indent = markdown ? "- " : "   ";
  if (s->cells.len == 0 && s->lines.len == 0) {
    ms_strbuild_append_text(out, indent);
    ms_strbuild_append_text(out, "none\n");
    return;
  }
  if (s->cells.len > 0) {
    write_table(out, s, markdown);
  }
  for (size_t i = 0; i < s->lines.len; i++) {
    ms_strbuild_append_text(out, indent);
    ms_strbuild_append(out, s->lines.ptr[i]);
    ms_strbuild_append_text(out, "\n");
  }
  if (s->more > 0) {
    ms_strbuild_append(out, ms_message_format(arena, "%s+%z more (use --all)\n", indent, s->more));
  }
}

static void body(MsArena *arena, const MsReport *report, bool markdown, MsStrBuild *out) {
  MsStrBuild b = ms_strbuild_new();
  if (markdown) {
    ms_strbuild_append(&b, ms_message_format(arena, "# Manuscript review report (format %z)\n\n- input: %S\n- result: %S\n",
                                             (size_t)MS_REPORT_FORMAT, report->input, report->result));
  } else {
    ms_strbuild_append(&b, ms_message_format(arena, "MANUSCRIPT REVIEW REPORT  format %z\ninput   %S\nresult  %S\n",
                                             (size_t)MS_REPORT_FORMAT, report->input, report->result));
  }
  for (size_t i = 0; i < report->sections.len; i++) {
    const MsSection *s = &report->sections.ptr[i];
    ms_strbuild_append(&b, ms_message_format(arena, markdown ? "\n## %z. %S\n\n" : "\n%z. %S\n", i + 1, s->title));
    write_section(arena, &b, s, markdown);
  }
  MsSpan done = ms_strbuild_span(&b);
  while (done.len > 0 && done.ptr[done.len - 1] == '\n') {
    done.len--;
  }
  ms_strbuild_append(out, done);
  ms_strbuild_append_text(out, "\n");
  ms_strbuild_free(&b);
}

static void json_strings(MsStrBuild *out, const MsSpan *items, size_t count, size_t depth) {
  if (count == 0) {
    ms_strbuild_append_text(out, "[]");
    return;
  }
  ms_strbuild_append_text(out, "[\n");
  for (size_t i = 0; i < count; i++) {
    ms_strbuild_append_indent(out, depth + 1);
    ms_json_string(out, items[i]);
    ms_strbuild_append_text(out, i + 1 < count ? ",\n" : "\n");
  }
  ms_strbuild_append_indent(out, depth);
  ms_strbuild_append_text(out, "]");
}

static void json_section(MsStrBuild *out, const MsSection *s) {
  ms_strbuild_append_indent(out, 2);
  ms_strbuild_append_text(out, "{\n");
  ms_strbuild_append_indent(out, 3);
  ms_strbuild_append_text(out, "\"title\": ");
  ms_json_string(out, s->title);
  if (s->headers.len > 0) {
    ms_strbuild_append_text(out, ",\n");
    ms_strbuild_append_indent(out, 3);
    ms_strbuild_append_text(out, "\"headers\": ");
    json_strings(out, s->headers.ptr, s->headers.len, 3);
  }
  if (s->cells.len > 0) {
    const size_t columns = s->headers.len;
    ms_strbuild_append_text(out, ",\n");
    ms_strbuild_append_indent(out, 3);
    ms_strbuild_append_text(out, "\"rows\": [\n");
    const size_t rows = s->cells.len / columns;
    for (size_t r = 0; r < rows; r++) {
      ms_strbuild_append_indent(out, 4);
      json_strings(out, s->cells.ptr + r * columns, columns, 4);
      ms_strbuild_append_text(out, r + 1 < rows ? ",\n" : "\n");
    }
    ms_strbuild_append_indent(out, 3);
    ms_strbuild_append_text(out, "]");
  }
  if (s->lines.len > 0) {
    ms_strbuild_append_text(out, ",\n");
    ms_strbuild_append_indent(out, 3);
    ms_strbuild_append_text(out, "\"lines\": ");
    json_strings(out, s->lines.ptr, s->lines.len, 3);
  }
  if (s->more > 0) {
    ms_strbuild_append_text(out, ",\n");
    ms_strbuild_append_indent(out, 3);
    ms_strbuild_printf(out, "\"more\": %zu", s->more);
  }
  ms_strbuild_append_text(out, "\n");
  ms_strbuild_append_indent(out, 2);
  ms_strbuild_append_text(out, "}");
}

static void json_strings_or_null(MsStrBuild *out, const MsSpans *list, size_t depth) {
  if (list->len == 0) {
    ms_strbuild_append_text(out, "null");
  } else {
    json_strings(out, list->ptr, list->len, depth);
  }
}

static bool is_internal(const MsFinding *f) {
  return ms_span_is_text(f->tier, "INTERNAL");
}

/* A finding as an object whose braces sit at `depth` levels; `number` 0 reads null. */
static void json_finding(MsStrBuild *out, const MsFinding *f, size_t number, size_t depth, bool with_number) {
  ms_strbuild_append_text(out, "{\n");
  const struct {
    const char *key;
    MsSpan value;
  } head[] = {{"id", f->id}, {"tier", f->tier}, {"entity", f->entity}, {"where", f->location}};
  for (size_t i = 0; i < 4; i++) {
    ms_strbuild_append_indent(out, depth + 1);
    ms_strbuild_printf(out, "\"%s\": ", head[i].key);
    ms_json_string(out, head[i].value);
    ms_strbuild_append_text(out, ",\n");
  }
  ms_strbuild_append_indent(out, depth + 1);
  ms_strbuild_append_text(out, "\"changes\": ");
  json_strings_or_null(out, &f->changes, depth + 1);
  ms_strbuild_append_text(out, ",\n");
  ms_strbuild_append_indent(out, depth + 1);
  ms_strbuild_printf(out, "\"reach\": %zu,\n", f->reach);
  ms_strbuild_append_indent(out, depth + 1);
  ms_strbuild_printf(out, "\"score\": %lld,\n", (long long)f->score);
  ms_strbuild_append_indent(out, depth + 1);
  ms_strbuild_append_text(out, "\"terms\": ");
  json_strings_or_null(out, &f->terms, depth + 1);
  if (f->evidence.len > 0) {
    ms_strbuild_append_text(out, ",\n");
    ms_strbuild_append_indent(out, depth + 1);
    ms_strbuild_append_text(out, "\"evidence\": ");
    json_strings(out, f->evidence.ptr, f->evidence.len, depth + 1);
  }
  if (with_number) {
    ms_strbuild_append_text(out, ",\n");
    ms_strbuild_append_indent(out, depth + 1);
    if (number == 0) {
      ms_strbuild_append_text(out, "\"number\": null");
    } else {
      ms_strbuild_printf(out, "\"number\": %zu", number);
    }
  }
  ms_strbuild_append_text(out, "\n");
  ms_strbuild_append_indent(out, depth);
  ms_strbuild_append_text(out, "}");
}

static void json_findings(MsStrBuild *out, const MsReport *report) {
  if (report->findings.len == 0) {
    ms_strbuild_append_text(out, "[]");
    return;
  }
  ms_strbuild_append_text(out, "[\n");
  size_t rank = 0;
  for (size_t i = 0; i < report->findings.len; i++) {
    const MsFinding *f = &report->findings.ptr[i];
    const size_t number = is_internal(f) ? 0 : ++rank;
    ms_strbuild_append_indent(out, 2);
    json_finding(out, f, number, 2, true);
    ms_strbuild_append_text(out, i + 1 < report->findings.len ? ",\n" : "\n");
  }
  ms_strbuild_append_indent(out, 1);
  ms_strbuild_append_text(out, "]");
}

static void render_json(const MsReport *report, MsStrBuild *out) {
  ms_strbuild_printf(out, "{\n  \"format\": %d,\n  \"mode\": ", MS_REPORT_FORMAT);
  ms_json_string(out, report->mode);
  ms_strbuild_append_text(out, ",\n  \"input\": ");
  ms_json_string(out, report->input);
  ms_strbuild_append_text(out, ",\n  \"result\": ");
  ms_json_string(out, report->result);
  ms_strbuild_append_text(out, ",\n  \"base_checked\": ");
  ms_strbuild_append_text(out, !report->has_base ? "null" : report->base_checked ? "true" : "false");
  ms_strbuild_append_text(out, ",\n  \"sections\": [\n");
  for (size_t i = 0; i < report->sections.len; i++) {
    json_section(out, &report->sections.ptr[i]);
    ms_strbuild_append_text(out, i + 1 < report->sections.len ? ",\n" : "\n");
  }
  ms_strbuild_append_text(out, "  ],\n  \"findings\": ");
  json_findings(out, report);
  ms_strbuild_append_text(out, ",\n  \"digest\": ");
  ms_json_string(out, report->digest);
  ms_strbuild_append_text(out, "\n}\n");
}

void ms_report_render(MsArena *arena, const MsReport *report, MsSpan format, MsStrBuild *out) {
  if (ms_span_is_text(format, "json")) {
    render_json(report, out);
    return;
  }
  body(arena, report, ms_span_is_text(format, "markdown"), out);
  ms_strbuild_append(out, ms_message_format(arena, "\ndigest %S\n", report->digest));
}
