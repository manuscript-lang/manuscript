/* Owns editor recovery parsing: retains the declarations of a file that parse independently and reports
 * the diagnostics of those that do not. Port of crates/ms-syntax/src/partial.rs. */
#include "base/sort.h"
#include "compiler/syntax/partial_internal.h"

MS_LIST_DEFINE(LineList, line_list, MsSpan)
MS_LIST_DEFINE(OffsetList, offset_list, size_t)
MS_LIST_DEFINE(ImportBuf, import_buf, MsImport)
MS_LIST_DEFINE(DeclBuf, decl_buf, MsDecl *)
MS_LIST_DEFINE(SpanBuf, span_buf, MsSpan)
MS_LIST_DEFINE(RangeBuf, range_buf, MsOffsetRange)

/* A probe records the parse of one candidate root: where it ends, and its error. */
typedef struct Probe {
  size_t start, end;
  bool failed;
  MsDiag error;
} Probe;

MS_LIST_DEFINE(ProbeList, probe_list, Probe)

typedef struct Split {
  MsSpan source;
  LineList lines;
  bool *roots;
  bool *continuations;
  OffsetList starts;
  ProbeList probes;
  size_t attempted_start;
  size_t continuation_end;
  size_t last_start_index;
} Split;

static MsSpan slice(MsSpan source, size_t from, size_t to) {
  return ms_span_of(source.ptr + from, to - from);
}

static void split_lines(Split *split) {
  size_t start = 0;
  for (size_t i = 0; i < split->source.len; i++) {
    if (split->source.ptr[i] == '\n') {
      line_list_push(&split->lines, slice(split->source, start, i + 1));
      start = i + 1;
    }
  }
  if (start < split->source.len) {
    line_list_push(&split->lines, slice(split->source, start, split->source.len));
  }
}

/* Whether lexing `prefix` fails with an unterminated delimiter or multi-line text. */
static bool prefix_unterminated(MsSpan prefix) {
  MsArena scratch = ms_arena_new();
  MsLexed lexed;
  MsDiag diag = {0};
  bool failed = !ms_lex(&scratch, prefix, &lexed, &diag);
  bool open = failed && (ms_span_starts_with(diag.message, ms_span_of_text("unterminated delimiter")) ||
                         ms_span_starts_with(diag.message, ms_span_of_text("unterminated multi-line text")));
  ms_arena_free(&scratch);
  return open;
}

static Probe *find_probe(ProbeList *probes, size_t start) {
  for (size_t i = 0; i < probes->len; i++) {
    if (probes->ptr[i].start == start) {
      return &probes->ptr[i];
    }
  }
  return NULL;
}

static void record_probe(ProbeList *probes, Probe probe) {
  Probe *existing = find_probe(probes, probe.start);
  if (existing != NULL) {
    *existing = probe;
  } else {
    probe_list_push(probes, probe);
  }
}

static bool contains_closer(MsSpan text) {
  for (size_t i = 0; i < text.len; i++) {
    if (text.ptr[i] == ')' || text.ptr[i] == ']' || text.ptr[i] == '}') {
      return true;
    }
  }
  return false;
}

/* Probes the root opened at `last` once, up to the next possible root. A successful single-root parse proves
 * the intervening lines are continuations; failed probes keep the original splitter. */
static void probe_root(Partial *partial, Split *split, size_t index, size_t offset) {
  size_t start = split->starts.ptr[split->starts.len - 1];
  if (!partial_root_start(slice(split->source, start, split->source.len))) {
    return;
  }
  size_t end = offset;
  for (size_t next = index; next < split->lines.len; next++) {
    if (!split->continuations[next] && partial_root_start(split->lines.ptr[next])) {
      break;
    }
    end += split->lines.ptr[next].len;
  }
  size_t start_line = split->last_start_index;
  if (split->starts.len == 1) {
    start = 0; /* the first chunk owns its leading trivia */
    start_line = 0;
  }
  /* An open prefix cannot parse without a later closer. */
  if (!contains_closer(slice(split->source, offset, end))) {
    return;
  }
  MsModule parsed;
  Probe probe = {.start = start, .end = end};
  MsChunk where = {.base_offset = (uint32_t)start, .base_line = (uint32_t)start_line};
  bool ok = ms_parse_chunk(partial->arena, partial->names, slice(split->source, start, end), where, &parsed,
                           &probe.error);
  bool single = ok && partial_single_root(&parsed);
  probe.failed = !ok;
  if (!ok || single) {
    record_probe(&split->probes, probe);
  }
  if (single) {
    split->continuation_end = end;
  }
}

/* Decides where each chunk starts: a candidate line starts one unless it continues an unterminated one. */
static void find_starts(Partial *partial, Split *split) {
  size_t offset = 0;
  for (size_t index = 0; index < split->lines.len; index++) {
    MsSpan line = split->lines.ptr[index];
    if (offset < split->continuation_end || split->continuations[index] ||
        !partial_is_candidate_line(line)) {
      offset += line.len;
      continue;
    }
    if (!partial_is_declaration_line(line) && split->starts.len != 0) {
      size_t last = split->starts.ptr[split->starts.len - 1];
      /* A fresh declaration synchronizes even after an unmatched opener. Other column-zero lines can still
       * belong to a continued header, import, or expression. */
      if (prefix_unterminated(slice(split->source, last, offset))) {
        if (split->attempted_start != last) {
          split->attempted_start = last;
          probe_root(partial, split, index, offset);
        }
        offset += line.len;
        continue;
      }
    }
    offset_list_push(&split->starts, offset);
    split->last_start_index = index;
    offset += line.len;
  }
}

static size_t count_newlines(MsSpan text) {
  size_t count = 0;
  for (size_t i = 0; i < text.len; i++) {
    count += text.ptr[i] == '\n';
  }
  return count;
}

static int64_t compare_issues(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const MsDiag *x = (const void *)a;
  const MsDiag *y = (const void *)b;
  return x->pos.offset < y->pos.offset ? -1 : x->pos.offset > y->pos.offset;
}

typedef struct Result {
  ImportBuf imports;
  DeclBuf decls;
  SpanBuf omitted;
  RangeBuf recovered;
  uint32_t node_count;
  DiagList diags;
} Result;

/* Parses the chunk again in the merged node-id range so the retained tree needs no rewriting. */
static void keep_chunk(Partial *partial, Result *result, MsSpan text, MsChunk where) {
  where.first_id = result->node_count;
  MsModule parsed;
  MsDiag error = {0};
  if (!ms_parse_chunk(partial->arena, partial->names, text, where, &parsed, &error)) {
    return;
  }
  result->node_count = parsed.node_count;
  for (uint32_t i = 0; i < parsed.nimports; i++) {
    import_buf_push(&result->imports, parsed.imports[i]);
  }
  for (uint32_t i = 0; i < parsed.ndecls; i++) {
    decl_buf_push(&result->decls, parsed.decls[i]);
  }
}

/* The error of one chunk, or false when it parses. */
static bool chunk_error(Partial *partial, Split *split, size_t start, size_t end, uint32_t line, MsDiag *error) {
  Probe *probe = find_probe(&split->probes, start);
  if (probe != NULL && probe->end == end) {
    *error = probe->error;
    bool failed = probe->failed;
    probe->start = (size_t)-1; /* a probe is used once */
    return failed;
  }
  MsModule parsed;
  MsChunk where = {.base_offset = (uint32_t)start, .base_line = line};
  return !ms_parse_chunk(partial->arena, partial->names, slice(split->source, start, end), where, &parsed,
                         error);
}

static void parse_chunks(Partial *partial, Split *split, Result *result) {
  size_t previous = 0;
  uint32_t line_offset = 0;
  for (size_t i = 0; i + 1 < split->starts.len; i++) {
    size_t start = split->starts.ptr[i];
    size_t end = split->starts.ptr[i + 1];
    line_offset += (uint32_t)count_newlines(slice(split->source, previous, start));
    previous = start;
    MsSpan chunk = slice(split->source, start, end);
    MsChunk where = {.base_offset = (uint32_t)start, .base_line = line_offset};
    MsSpan text = chunk;
    MsDiag error = {0};
    if (chunk_error(partial, split, start, end, line_offset, &error)) {
      DiagList issues = {0};
      if (!partial_recover_statements(partial, chunk, where, &error, &text, &issues)) {
        MsSpan name;
        if (partial_declared_name(chunk, &name)) {
          span_buf_push(&result->omitted, name);
        }
        diag_list_push(&result->diags, error);
        diag_list_free(&issues);
        continue;
      }
      if (issues.len != 0) {
        ms_sort((uint8_t *)issues.ptr, issues.len, sizeof(MsDiag), compare_issues, NULL);
      }
      for (size_t k = 0; k < issues.len; k++) {
        diag_list_push(&result->diags, issues.ptr[k]);
      }
      diag_list_free(&issues);
      range_buf_push(&result->recovered, (MsOffsetRange){(uint32_t)start, (uint32_t)end});
    }
    keep_chunk(partial, result, text, where);
  }
}

static void *copy_buf(MsArena *arena, const void *items, size_t count, size_t size, size_t alignment) {
  void *copy = ms_arena_alloc(arena, count == 0 ? size : count * size, alignment);
  if (count != 0) {
    __builtin_memcpy(copy, items, count * size);
  }
  return copy;
}

static void export_module(MsArena *arena, const Result *result, MsModule *module) {
  *module = (MsModule){.node_count = result->node_count};
  module->nimports = (uint32_t)result->imports.len;
  module->imports = copy_buf(arena, result->imports.ptr, result->imports.len, sizeof(MsImport), _Alignof(MsImport));
  module->ndecls = (uint32_t)result->decls.len;
  module->decls = copy_buf(arena, result->decls.ptr, result->decls.len, sizeof(MsDecl *), _Alignof(MsDecl *));
  module->nomitted = (uint32_t)result->omitted.len;
  module->omitted = copy_buf(arena, result->omitted.ptr, result->omitted.len, sizeof(MsSpan), _Alignof(MsSpan));
  module->nrecovered = (uint32_t)result->recovered.len;
  module->recovered = copy_buf(arena, result->recovered.ptr, result->recovered.len, sizeof(MsOffsetRange),
                               _Alignof(MsOffsetRange));
}

static void free_result(Result *result) {
  import_buf_free(&result->imports);
  decl_buf_free(&result->decls);
  span_buf_free(&result->omitted);
  range_buf_free(&result->recovered);
  diag_list_free(&result->diags);
}

static void free_split(Split *split) {
  line_list_free(&split->lines);
  offset_list_free(&split->starts);
  probe_list_free(&split->probes);
}

bool ms_parse_partial(MsArena *arena, MsNames *names, MsSpan source, MsModule *module, MsDiag **diags,
                      size_t *ndiags) {
  Partial partial = {.arena = arena, .names = names};
  MsDiag first = {0};
  *diags = NULL;
  *ndiags = 0;
  if (ms_parse(arena, names, source, module, &first)) {
    return true;
  }
  Split split = {.source = source, .attempted_start = (size_t)-1};
  Result result = {0};
  split_lines(&split);
  split.roots = MS_ARENA_NEW_ARRAY(arena, bool, split.lines.len + 1);
  for (size_t i = 0; i < split.lines.len; i++) {
    split.roots[i] = partial_is_declaration_line(split.lines.ptr[i]);
  }
  size_t nlines = 0;
  split.continuations = ms_lex_continuations(arena, source, split.roots, split.lines.len, &nlines);
  find_starts(&partial, &split);
  if (split.starts.len == 0) {
    diag_list_push(&result.diags, first);
  } else {
    split.starts.ptr[0] = 0;
    offset_list_push(&split.starts, source.len);
    parse_chunks(&partial, &split, &result);
  }
  export_module(arena, &result, module);
  *diags = copy_buf(arena, result.diags.ptr, result.diags.len, sizeof(MsDiag), _Alignof(MsDiag));
  *ndiags = result.diags.len;
  free_result(&result);
  free_split(&split);
  return false;
}
