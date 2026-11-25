/* lsp/lsp_symbols.c: the outline: one symbol per declaration with its fields, cases and methods as children. */
#include "lsp/lsp_internal.h"
#include "lsp/lsp_symbols.h"

#include <stdlib.h>
#include <string.h>

#include "compiler/check/program.h"
#include "compiler/syntax/ast.h"
#include "compiler/syntax/format.h"
#include "compiler/syntax/lex.h"

enum { KIND_FUNCTION = 12, KIND_CONSTANT = 14, KIND_CLASS = 5, KIND_ENUM = 10, KIND_INTERFACE = 11, KIND_METHOD = 6,
       KIND_FIELD = 8, KIND_ENUM_MEMBER = 22 };

typedef struct Outline {
  const MsCheckProgram *program;
  MsSpan source;
  LspLines lines; /* the lines of `source`: positions by binary search */
} Outline;

static void write_range(MsStrBuild *out, LspPosition start, LspPosition end) {
  ms_strbuild_printf(out, "{\"start\":{\"line\":%zu,\"character\":%zu},\"end\":{\"line\":%zu,\"character\":%zu}}", start.line,
                     start.character, end.line, end.character);
}

/* The range of `name` on the declaration's line, else an empty range at the offset. */
static void selection(const Outline *outline, MsStrBuild *out, size_t offset, MsSpan name) {
  size_t at;
  if (lsp_header(outline->source, offset, name, &at)) {
    write_range(out, lsp_lines_position(&outline->lines, at), lsp_lines_position(&outline->lines, at + name.len));
  } else {
    const LspPosition position = lsp_lines_position(&outline->lines, offset);
    write_range(out, position, position);
  }
}

/* The end of the block that precedes `next`, without trailing blank space. */
static size_t block_end(const Outline *outline, size_t next) {
  const MsSpan text = outline->source;
  if (next > text.len) next = text.len;
  if (next < text.len) {
    while (next > 0 && text.ptr[next - 1] != '\n') next--;
  }
  while (next > 0 && (text.ptr[next - 1] == ' ' || text.ptr[next - 1] == '\t' || text.ptr[next - 1] == '\r' ||
                      text.ptr[next - 1] == '\n')) {
    next--;
  }
  return next;
}

static MsSpan name_text(const Outline *outline, MsName name) {
  return ms_names_span(outline->program->names, name);
}

static void write_method(const Outline *outline, MsStrBuild *out, bool *first, const MsMethod *method, size_t end) {
  const MsSpan name = name_text(outline, method->func.name);
  const size_t offset = method->pos.offset;
  if (!*first) ms_strbuild_append_byte(out, ',');
  *first = false;
  ms_strbuild_append_text(out, "{\"name\":");
  lsp_json_string(out, name);
  ms_strbuild_printf(out, ",\"detail\":\"\",\"kind\":%d,\"range\":", KIND_METHOD);
  write_range(out, lsp_lines_position(&outline->lines, offset), lsp_lines_position(&outline->lines, end > offset ? end : offset));
  ms_strbuild_append_text(out, ",\"selectionRange\":");
  selection(outline, out, offset, name);
  ms_strbuild_append_byte(out, '}');
}

static void write_methods(const Outline *outline, MsStrBuild *out, bool *first, MsMethod *const *methods, uint32_t count,
                          size_t decl_end) {
  for (uint32_t i = 0; i < count; i++) {
    const size_t end = i + 1 < count ? block_end(outline, methods[i + 1]->pos.offset) : decl_end;
    write_method(outline, out, first, methods[i], end);
  }
}

static const MsSymbol *symbol_of(const Outline *outline, uint32_t module, const MsDecl *decl, MsName name) {
  const MsSymbolId *id = ms_scope_get(&outline->program->modules.ptr[module].scope, name);
  if (id == NULL || *id == 0) return NULL;
  const MsSymbol *symbol = &outline->program->symbols.ptr[*id];
  return symbol->decl == decl ? symbol : NULL;
}

static MsName decl_name(const MsDecl *decl) {
  switch (decl->kind) {
  case MS_D_FN: return decl->u.fn.name;
  case MS_D_CONST: return decl->u.konst.name;
  case MS_D_TYPE: return decl->u.type.name;
  case MS_D_ENUM: return decl->u.enumeration.name;
  case MS_D_ALIAS: return decl->u.alias.name;
  case MS_D_INTERFACE: return decl->u.iface.name;
  default: return 0;
  }
}

static void write_declaration(const Outline *outline, MsStrBuild *out, uint32_t module, const MsDecl *decl, size_t end) {
  MsStrBuild name = ms_strbuild_new();
  MsStrBuild detail = ms_strbuild_new();
  int kind = KIND_FUNCTION;
  MsSpan selection_name = {0};
  const MsName declared = decl_name(decl);
  if (decl->kind != MS_D_IMPL && decl->kind != MS_D_TEST) {
    selection_name = name_text(outline, declared);
    ms_strbuild_append(&name, selection_name);
    const MsSymbol *symbol = symbol_of(outline, module, decl, declared);
    if (symbol != NULL && (decl->kind == MS_D_FN || decl->kind == MS_D_CONST) && symbol->ty != MS_TY_NONE &&
        !ms_ty_is_invalid(&outline->program->types, symbol->ty)) {
      ms_ty_show_plain(&detail, outline->program->names, &outline->program->types, symbol->ty);
    }
    if (decl->kind == MS_D_CONST) kind = KIND_CONSTANT;
  }
  switch (decl->kind) {
  case MS_D_TYPE:
  case MS_D_ALIAS: kind = KIND_CLASS; break;
  case MS_D_ENUM: kind = KIND_ENUM; break;
  case MS_D_INTERFACE: kind = KIND_INTERFACE; break;
  case MS_D_IMPL:
    kind = KIND_CLASS;
    if (decl->u.impl.contract != NULL && !decl->synthetic) {
      ms_strbuild_append(&name, name_text(outline, decl->u.impl.contract->name));
      ms_strbuild_append_text(&name, " for ");
    }
    ms_strbuild_append(&name, name_text(outline, decl->u.impl.receiver->name));
    break;
  case MS_D_TEST:
    ms_strbuild_append_text(&name, decl->u.test.bench ? "bench " : "test ");
    ms_strbuild_append(&name, decl->u.test.name);
    break;
  default: break;
  }
  ms_strbuild_append_text(out, "{\"name\":");
  lsp_json_string(out, ms_strbuild_span(&name));
  ms_strbuild_append_text(out, ",\"detail\":");
  lsp_json_string(out, ms_strbuild_span(&detail));
  ms_strbuild_printf(out, ",\"kind\":%d,\"range\":", kind);
  write_range(out, lsp_lines_position(&outline->lines, decl->pos.offset), lsp_lines_position(&outline->lines, end));
  ms_strbuild_append_text(out, ",\"selectionRange\":");
  selection(outline, out, decl->pos.offset, selection_name);
  MsStrBuild children = ms_strbuild_new();
  bool first = true;
  if (decl->kind == MS_D_TYPE) {
    for (uint32_t i = 0; i < decl->u.type.fields.len; i++) {
      const MsParam *field = decl->u.type.fields.ptr[i];
      const MsSpan field_name = name_text(outline, field->name);
      size_t line_end = field->pos.offset;
      while (line_end < outline->source.len && outline->source.ptr[line_end] != '\n') line_end++;
      if (line_end > field->pos.offset && outline->source.ptr[line_end - 1] == '\r') line_end--;
      if (!first) ms_strbuild_append_byte(&children, ',');
      first = false;
      ms_strbuild_append_text(&children, "{\"name\":");
      lsp_json_string(&children, field_name);
      ms_strbuild_printf(&children, ",\"kind\":%d,\"range\":", KIND_FIELD);
      size_t at = field->pos.offset;
      (void)lsp_header(outline->source, field->pos.offset, field_name, &at);
      write_range(&children, lsp_lines_position(&outline->lines, at), lsp_lines_position(&outline->lines, line_end));
      ms_strbuild_append_text(&children, ",\"selectionRange\":");
      selection(outline, &children, field->pos.offset, field_name);
      ms_strbuild_append_byte(&children, '}');
    }
  } else if (decl->kind == MS_D_ENUM) {
    for (uint32_t i = 0; i < decl->u.enumeration.cases.len; i++) {
      const MsCase *item = decl->u.enumeration.cases.ptr[i];
      const MsSpan case_name = name_text(outline, item->name);
      if (!first) ms_strbuild_append_byte(&children, ',');
      first = false;
      ms_strbuild_append_text(&children, "{\"name\":");
      lsp_json_string(&children, case_name);
      ms_strbuild_printf(&children, ",\"kind\":%d,\"range\":", KIND_ENUM_MEMBER);
      selection(outline, &children, item->pos.offset, case_name);
      ms_strbuild_append_text(&children, ",\"selectionRange\":");
      selection(outline, &children, item->pos.offset, case_name);
      ms_strbuild_append_byte(&children, '}');
    }
  } else if (decl->kind == MS_D_INTERFACE) {
    write_methods(outline, &children, &first, decl->u.iface.methods.ptr, decl->u.iface.methods.len, end);
  } else if (decl->kind == MS_D_IMPL) {
    write_methods(outline, &children, &first, decl->u.impl.methods.ptr, decl->u.impl.methods.len, end);
  }
  if (!first) {
    ms_strbuild_append_text(out, ",\"children\":[");
    ms_strbuild_append(out, ms_strbuild_span(&children));
    ms_strbuild_append_byte(out, ']');
  }
  ms_strbuild_append_byte(out, '}');
  ms_strbuild_free(&name);
  ms_strbuild_free(&detail);
  ms_strbuild_free(&children);
}

void lsp_document_symbols(const LspDocList *docs, const LspDoc *doc, MsStrBuild *out) {
  LspAnalysis analysis;
  lsp_analyze(docs, doc, &analysis);
  ms_strbuild_append_byte(out, '[');
  const MsCheckProgram *program = &analysis.checked.program;
  for (uint32_t m = 0; analysis.resolved && m < program->user_modules; m++) {
    if (!ms_span_equal(analysis.paths[m], ms_string_span(&doc->path))) continue;
    Outline outline = {.program = program, .source = program->modules.ptr[m].source};
    lsp_lines_init(&outline.lines, outline.source);
    const MsModule *tree = program->modules.ptr[m].tree;
    bool first = true;
    for (uint32_t i = 0; i < tree->ndecls; i++) {
      const MsDecl *decl = tree->decls[i];
      if (decl->synthetic && decl->kind == MS_D_INTERFACE) continue;
      const size_t next = i + 1 < tree->ndecls ? tree->decls[i + 1]->pos.offset : outline.source.len;
      size_t end = block_end(&outline, next);
      if (end < decl->pos.offset) end = decl->pos.offset;
      if (!first) ms_strbuild_append_byte(out, ',');
      first = false;
      write_declaration(&outline, out, m, decl, end);
    }
    lsp_lines_free(&outline.lines);
  }
  ms_strbuild_append_byte(out, ']');
  lsp_analysis_release(&analysis);
}

bool lsp_format_document(const LspDoc *doc, MsStrBuild *out, MsStrBuild *error) {
  MsArena arena = ms_arena_new();
  MsStrBuild formatted = ms_strbuild_new();
  MsDiag diag;
  const MsSpan source = ms_string_span(&doc->text);
  const bool ok = ms_format(&arena, source, &formatted, &diag);
  if (!ok) {
    ms_strbuild_append(error, ms_string_span(&doc->path));
    ms_strbuild_printf(error, ":%u:%u: parse: ", diag.pos.line, diag.pos.column);
    ms_strbuild_append(error, diag.message);
  } else {
    ms_strbuild_append_text(out, "[{\"range\":");
    write_range(out, (LspPosition){0, 0}, lsp_position(source, source.len));
    ms_strbuild_append_text(out, ",\"newText\":");
    lsp_json_string(out, ms_strbuild_span(&formatted));
    ms_strbuild_append_text(out, "}]");
  }
  ms_strbuild_free(&formatted);
  ms_arena_free(&arena);
  return ok;
}

typedef struct Fold {
  size_t start, end;
} Fold;

MS_LIST_DEFINE(FoldList, fold_list, Fold)
MS_LIST_DEFINE(LineStack, line_stack, size_t)

static int compare_fold(const void *left, const void *right) {
  const Fold *a = left, *b = right;
  if (a->start != b->start) return a->start < b->start ? -1 : 1;
  return a->end == b->end ? 0 : (a->end < b->end ? -1 : 1);
}

static size_t indent_columns(MsSpan line) {
  size_t columns = 0;
  for (size_t i = 0; i < line.len && (line.ptr[i] == ' ' || line.ptr[i] == '\t'); i++) columns += line.ptr[i] == '\t' ? 4 : 1;
  return columns;
}

static bool blank(MsSpan line) {
  for (size_t i = 0; i < line.len; i++) {
    if (line.ptr[i] != ' ' && line.ptr[i] != '\t' && line.ptr[i] != '\r') return false;
  }
  return true;
}

/* Source that does not lex keeps forgiving folding by indentation. */
static void fold_by_indentation(MsSpan source, FoldList *folds) {
  LineStack starts = {0}; /* line start offsets */
  size_t at = 0;
  while (at <= source.len) {
    line_stack_push(&starts, at);
    const uint8_t *newline = at < source.len ? memchr(source.ptr + at, '\n', source.len - at) : NULL;
    if (newline == NULL) break;
    at = (size_t)(newline - source.ptr) + 1;
  }
  for (size_t start = 0; start < starts.len; start++) {
    const size_t from = starts.ptr[start];
    size_t to = start + 1 < starts.len ? starts.ptr[start + 1] - 1 : source.len;
    const MsSpan line = ms_span_of(source.ptr + from, to - from);
    if (!lsp_line_opens_suite(line)) continue;
    const size_t level = indent_columns(line);
    size_t end = start;
    for (size_t next = start + 1; next < starts.len; next++) {
      const size_t next_from = starts.ptr[next];
      const size_t next_to = next + 1 < starts.len ? starts.ptr[next + 1] - 1 : source.len;
      const MsSpan content = ms_span_of(source.ptr + next_from, next_to - next_from);
      if (blank(content)) continue;
      if (indent_columns(content) <= level) break;
      end = next;
    }
    if (end > start) fold_list_push(folds, (Fold){start, end});
  }
  line_stack_free(&starts);
}

void lsp_folding_ranges(const LspDoc *doc, MsStrBuild *out) {
  MsArena arena = ms_arena_new();
  MsLexed lexed;
  MsDiag diag;
  FoldList folds = {0};
  const MsSpan source = ms_string_span(&doc->text);
  if (ms_lex(&arena, source, &lexed, &diag)) {
    /* Blocks end at their last code token before the closing brace, excluding trailing comments. */
    LineStack starts = {0};
    size_t last = 0;
    for (size_t i = 0; i < lexed.ntokens; i++) {
      const MsToken *token = &lexed.tokens[i];
      if (token->kind == MS_T_BlockOpen) {
        line_stack_push(&starts, token->pos.line - 1);
      } else if (token->kind == MS_T_BlockClose) {
        if (starts.len > 0) {
          const size_t start = starts.ptr[--starts.len];
          if (last > start) fold_list_push(&folds, (Fold){start, last});
        }
      } else if (token->kind != MS_T_Comment && token->kind != MS_T_Newline && token->kind != MS_T_Eof) {
        last = token->end.line - 1;
      }
    }
    line_stack_free(&starts);
  } else {
    fold_by_indentation(source, &folds);
  }
  if (folds.len > 1) qsort(folds.ptr, folds.len, sizeof(Fold), compare_fold);
  ms_strbuild_append_byte(out, '[');
  for (size_t i = 0; i < folds.len; i++) {
    if (i > 0) ms_strbuild_append_byte(out, ',');
    ms_strbuild_printf(out, "{\"startLine\":%zu,\"endLine\":%zu,\"kind\":\"region\"}", folds.ptr[i].start, folds.ptr[i].end);
  }
  ms_strbuild_append_byte(out, ']');
  fold_list_free(&folds);
  ms_arena_free(&arena);
}
