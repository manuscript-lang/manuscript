/* Owns ms_inspect_document (inspect.h): the document `ms inspect` prints. Port of `Inspection::to_json` and its
 * collection in crates/ms-tooling/src/inspect.rs. The `build_id` is the digest of the compact document without it. */
#include "base/sha256.h"
#include "base/sort.h"
#include "compiler/syntax/diag_json.h"
#include "tooling/inspect.h"

/* ---- a JSON writer that lays the same document out compactly (for the digest) or in the CLI's pretty form ---- */

enum { MAX_DEPTH = 8 };

typedef struct Json {
  MsStrBuild *out;
  bool pretty;
  size_t depth;
  bool first[MAX_DEPTH]; /* whether the container at each depth has no member yet */
} Json;

static void newline(Json *j) {
  if (!j->pretty) {
    return;
  }
  ms_strbuild_append_byte(j->out, '\n');
  for (size_t i = 0; i < j->depth; i++) {
    ms_strbuild_append_text(j->out, "  ");
  }
}

static void open(Json *j, char bracket) {
  ms_strbuild_append_byte(j->out, (uint8_t)bracket);
  j->first[++j->depth] = true;
}

static void close(Json *j, char bracket) {
  const bool empty = j->first[j->depth];
  j->depth--;
  if (!empty) {
    newline(j);
  }
  ms_strbuild_append_byte(j->out, (uint8_t)bracket);
}

/* Starts the next member or element. */
static void member(Json *j) {
  ms_strbuild_append_text(j->out, j->first[j->depth] ? "" : ",");
  j->first[j->depth] = false;
  newline(j);
}

static void key(Json *j, const char *name) {
  member(j);
  ms_json_string(j->out, ms_span_of_text(name));
  ms_strbuild_append_text(j->out, j->pretty ? ": " : ":");
}

static void text_member(Json *j, const char *name, MsSpan text) {
  key(j, name);
  ms_json_string(j->out, text);
}

static void number_member(Json *j, const char *name, size_t value) {
  key(j, name);
  ms_strbuild_append_u64(j->out, value);
}

static void strings_member(Json *j, const char *name, const MsSpanList *list) {
  key(j, name);
  open(j, '[');
  for (size_t i = 0; i < list->len; i++) {
    member(j);
    ms_json_string(j->out, list->ptr[i]);
  }
  close(j, ']');
}

/* ---- the document ---- */

typedef struct Doc {
  MsArena *arena;
  const MsCheckProgram *program;
  MsInspection inspection;
} Doc;

typedef struct Span {
  MsSpan file;
  MsPos pos;
  size_t end;
} Span;

static MsSpan source_of(const Doc *d, uint32_t module) {
  return d->program->modules.ptr[module].source;
}

static MsSpan file_of(const Doc *d, uint32_t module) {
  return ms_names_span(d->program->names, d->program->modules.ptr[module].file);
}

/* The offset of the first line break at or after `start`, or the end of the text. */
static size_t line_end(MsSpan source, size_t start) {
  size_t at = start < source.len ? start : source.len;
  while (at < source.len && source.ptr[at] != '\n' && source.ptr[at] != '\r') {
    at++;
  }
  return at > start ? at : start;
}

static void span_member(Json *j, const char *name, MsSpan file, MsSpan source, MsPos pos) {
  key(j, name);
  open(j, '{');
  text_member(j, "file", file);
  number_member(j, "start", pos.offset);
  number_member(j, "end", line_end(source, pos.offset));
  number_member(j, "line", pos.line);
  number_member(j, "column", pos.column);
  close(j, '}');
}

/* The module with the file name `file`, or the first one. */
static uint32_t module_of(const Doc *d, MsSpan file) {
  for (uint32_t m = 0; m < d->program->modules.len; m++) {
    if (ms_span_equal(file_of(d, m), file)) {
      return m;
    }
  }
  return 0;
}

typedef struct Local {
  MsSpan checker_id, name, ty;
  uint32_t module;
  MsPos pos;
} Local;

static int64_t compare_locals(uint8_t *env, const uint8_t *left, const uint8_t *right) {
  (void)env;
  const MsSpan a = ((const Local *)(const void *)left)->checker_id;
  const MsSpan b = ((const Local *)(const void *)right)->checker_id;
  const size_t common = a.len < b.len ? a.len : b.len;
  const int order = common == 0 ? 0 : __builtin_memcmp(a.ptr, b.ptr, common);
  return order != 0 ? order : (int64_t)a.len - (int64_t)b.len;
}

static Local *collect_locals(Doc *d, size_t *count) {
  const MsLocalRecordList *records = &d->program->bindings;
  Local *locals = MS_ARENA_NEW_ARRAY(d->arena, Local, records->len + 1);
  for (size_t i = 0; i < records->len; i++) {
    const MsLocalRecord *r = &records->ptr[i];
    MsStrBuild ty = ms_strbuild_new();
    ms_ty_show(&ty, d->program->names, &d->program->types, r->ty);
    const MsSpan name = ms_names_span(d->program->names, r->name);
    const MsSpan file = file_of(d, r->module);
    const bool std = r->module >= d->program->user_modules;
    locals[i] = (Local){.name = name, .ty = ms_arena_copy(d->arena, ms_strbuild_span(&ty)), .module = r->module, .pos = r->pos,
                        .checker_id = std ? ms_message_format(d->arena, "standard_%S_local%z_%S", file, i, name)
                                          : ms_message_format(d->arena, "local%z_%S", i, name)};
    ms_strbuild_free(&ty);
  }
  ms_sort((uint8_t *)locals, records->len, sizeof(Local), compare_locals, NULL);
  *count = records->len;
  return locals;
}

typedef struct SourceRow {
  MsSpan file;
  uint32_t module;
} SourceRow;

static int64_t compare_sources(uint8_t *env, const uint8_t *left, const uint8_t *right) {
  (void)env;
  const MsSpan a = ((const SourceRow *)(const void *)left)->file;
  const MsSpan b = ((const SourceRow *)(const void *)right)->file;
  const size_t common = a.len < b.len ? a.len : b.len;
  const int order = common == 0 ? 0 : __builtin_memcmp(a.ptr, b.ptr, common);
  return order != 0 ? order : (int64_t)a.len - (int64_t)b.len;
}

static void write_document(Doc *d, Json *j, MsSpan build_id, const Local *locals, size_t local_count,
                           const SourceRow *sources, size_t source_count) {
  const MsInspection *in = &d->inspection;
  open(j, '{');
  key(j, "locals");
  open(j, '[');
  for (size_t i = 0; i < local_count; i++) {
    member(j);
    open(j, '{');
    text_member(j, "checker_id", locals[i].checker_id);
    text_member(j, "name", locals[i].name);
    text_member(j, "type", locals[i].ty);
    span_member(j, "span", file_of(d, locals[i].module), source_of(d, locals[i].module), locals[i].pos);
    close(j, '}');
  }
  close(j, ']');
  number_member(j, "format", 2);
  text_member(j, "build_id", build_id);
  key(j, "sources");
  open(j, '[');
  for (size_t i = 0; i < source_count; i++) {
    uint8_t digest[MS_SHA256_HEX_LEN];
    ms_sha256_hex(source_of(d, sources[i].module), digest);
    member(j);
    open(j, '{');
    text_member(j, "file", sources[i].file);
    text_member(j, "sha256", ms_span_of(digest, MS_SHA256_HEX_LEN));
    close(j, '}');
  }
  close(j, ']');
  key(j, "entities");
  open(j, '[');
  for (size_t i = 0; i < in->entities.len; i++) {
    const MsEntity *e = &in->entities.ptr[i];
    member(j);
    open(j, '{');
    text_member(j, "id", e->id);
    if (e->checker_id.len > 0) {
      text_member(j, "checker_id", e->checker_id);
    }
    text_member(j, "kind", e->kind);
    text_member(j, "name", e->name);
    if (e->ty.len > 0) {
      text_member(j, "type", e->ty);
    }
    span_member(j, "span", e->file, source_of(d, module_of(d, e->file)), e->pos);
    key(j, "exported");
    ms_strbuild_append_text(j->out, e->exported ? "true" : "false");
    if (e->effects.len > 0) {
      strings_member(j, "effects", &e->effects);
      strings_member(j, "reach", &e->effects);
    }
    if (e->permits.len > 0) {
      strings_member(j, "permits", &e->permits);
    }
    close(j, '}');
  }
  close(j, ']');
  key(j, "calls");
  open(j, '[');
  for (size_t i = 0; i < in->calls.len; i++) {
    const MsCallSite *s = &in->calls.ptr[i];
    member(j);
    open(j, '{');
    text_member(j, "id", s->id);
    text_member(j, "owner", s->owner);
    text_member(j, "target", s->target);
    text_member(j, "kind", s->kind);
    span_member(j, "span", s->file, source_of(d, module_of(d, s->file)), s->pos);
    close(j, '}');
  }
  close(j, ']');
  key(j, "statements");
  open(j, '[');
  for (size_t i = 0; i < in->statements.len; i++) {
    const MsStatementSite *s = &in->statements.ptr[i];
    member(j);
    open(j, '{');
    text_member(j, "file", file_of(d, s->module));
    number_member(j, "start", s->pos.offset);
    number_member(j, "end", line_end(source_of(d, s->module), s->pos.offset));
    number_member(j, "line", s->pos.line);
    number_member(j, "column", s->pos.column);
    close(j, '}');
  }
  close(j, ']');
  close(j, '}');
}

void ms_inspect_document(MsArena *arena, const MsCheckProgram *program, MsStrBuild *out) {
  Doc d = {.arena = arena, .program = program};
  ms_inspect_collect(arena, program, true, &d.inspection);
  size_t local_count = 0;
  const Local *locals = collect_locals(&d, &local_count);
  SourceRow *sources = MS_ARENA_NEW_ARRAY(arena, SourceRow, program->modules.len + 1);
  for (uint32_t m = 0; m < program->modules.len; m++) {
    sources[m] = (SourceRow){.file = file_of(&d, m), .module = m};
  }
  ms_sort((uint8_t *)sources, program->modules.len, sizeof(SourceRow), compare_sources, NULL);
  MsStrBuild compact = ms_strbuild_new();
  Json digest = {.out = &compact};
  write_document(&d, &digest, ms_span_of_text(""), locals, local_count, sources, program->modules.len);
  uint8_t build_id[MS_SHA256_HEX_LEN];
  ms_sha256_hex(ms_strbuild_span(&compact), build_id);
  ms_strbuild_free(&compact);
  Json pretty = {.out = out, .pretty = true};
  write_document(&d, &pretty, ms_span_of(build_id, MS_SHA256_HEX_LEN), locals, local_count, sources, program->modules.len);
  ms_strbuild_append_byte(out, '\n');
  ms_inspection_free(&d.inspection);
}
