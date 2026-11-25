/* lsp/lsp_signature.c: the call around the cursor found from the forgiving token scan, its callee resolved by the checker
 * over the document with the unfinished call closed, its parameters read from the callee's type. */
#include "lsp/lsp_signature.h"

#include <stdlib.h>

#include "compiler/syntax/walk.h"
#include "tooling/doc_comment.h"

typedef struct Open {
  uint8_t ch;
  size_t at;
  bool callee; /* a `(` that directly follows a name: a call */
  size_t callee_start, callee_end;
  size_t name_end; /* where the callee's last name ends: the occurrence to resolve */
} Open;

MS_LIST_DEFINE(OpenList, open_list, Open)

static bool is_char(MsSpan source, const LspEditorToken *token, uint8_t ch) {
  return token->kind == LSP_TOKEN_CHAR && source.ptr[token->start] == ch;
}

static bool token_is(MsSpan source, const LspEditorToken *token, const char *text) {
  return token->kind == LSP_TOKEN_NAME && ms_span_is_text(ms_span_of(source.ptr + token->start, token->end - token->start), text);
}

/* Words that may precede `(` without it being a call. */
static bool is_keyword(MsSpan source, const LspEditorToken *token) {
  static const char *const WORDS[] = {"if", "while", "for", "match", "return", "fn", "and", "or", "not", "in", "is", "as", "else", "try", "await", "move", "var"};
  for (size_t i = 0; i < sizeof WORDS / sizeof WORDS[0]; i++) {
    if (token_is(source, token, WORDS[i])) return true;
  }
  return false;
}

/* A word that begins a declaration at the start of a line ends any call before it. */
static bool starts_declaration(MsSpan source, const LspEditorToken *token) {
  static const char *const WORDS[] = {"fn", "export", "type", "enum", "test", "import"};
  if (token->kind != LSP_TOKEN_NAME || (token->start > 0 && source.ptr[token->start - 1] != '\n')) return false;
  for (size_t i = 0; i < sizeof WORDS / sizeof WORDS[0]; i++) {
    if (token_is(source, token, WORDS[i])) return true;
  }
  return false;
}

/* The token index of the bracket matching the closer at `close`, or `close` when it has none. */
static size_t matching_opener(MsSpan source, const LspTokenList *tokens, size_t close) {
  size_t depth = 0;
  for (size_t i = close + 1; i > 0; i--) {
    const LspEditorToken *token = &tokens->ptr[i - 1];
    if (token->kind != LSP_TOKEN_CHAR) continue;
    const uint8_t ch = source.ptr[token->start];
    if (ch == ')' || ch == ']' || ch == '}') depth++;
    else if ((ch == '(' || ch == '[' || ch == '{') && --depth == 0) return i - 1;
  }
  return close;
}

/* Fills the callee of the `(` at token `at` when it directly follows a name, a name with type arguments (`first[Int](`),
 * through `.` chains whose receiver may be a parenthesised expression (`(pair).combine(`). */
static void callee_of(MsSpan source, const LspTokenList *tokens, size_t at, Open *open) {
  size_t name = at - 1;
  size_t end = tokens->ptr[at - 1].end;
  size_t after = at; /* the token that must directly follow the name */
  if (is_char(source, &tokens->ptr[name], ']') && tokens->ptr[name].end == tokens->ptr[at].start) {
    const size_t bracket = matching_opener(source, tokens, name);
    if (bracket == name || bracket == 0) return;
    after = bracket;
    name = bracket - 1;
  }
  if (tokens->ptr[name].kind != LSP_TOKEN_NAME || tokens->ptr[name].end != tokens->ptr[after].start ||
      is_keyword(source, &tokens->ptr[name])) {
    return;
  }
  open->name_end = tokens->ptr[name].end;
  size_t first = name;
  while (first >= 2 && is_char(source, &tokens->ptr[first - 1], '.') && tokens->ptr[first - 1].start == tokens->ptr[first].start - 1) {
    const LspEditorToken *before = &tokens->ptr[first - 2];
    if (before->kind == LSP_TOKEN_NAME && before->end == tokens->ptr[first - 1].start) {
      first -= 2;
    } else if (is_char(source, before, ')') && before->end == tokens->ptr[first - 1].start) {
      const size_t group = matching_opener(source, tokens, first - 2);
      if (group == first - 2) break;
      first = group;
      break;
    } else {
      break;
    }
  }
  open->callee = true;
  open->callee_start = tokens->ptr[first].start;
  open->callee_end = end;
}

/* The brackets still open at `offset`, innermost last. */
static void open_brackets(MsSpan source, const LspTokenList *tokens, size_t offset, OpenList *stack) {
  for (size_t i = 0; i < tokens->len && tokens->ptr[i].start < offset; i++) {
    const LspEditorToken *token = &tokens->ptr[i];
    if (starts_declaration(source, token)) {
      stack->len = 0;
    } else if (is_char(source, token, '(') || is_char(source, token, '[') || is_char(source, token, '{')) {
      Open open = {.ch = source.ptr[token->start], .at = token->start};
      if (open.ch == '(' && i > 0) callee_of(source, tokens, i, &open);
      open_list_push(stack, open);
    } else if ((is_char(source, token, ')') || is_char(source, token, ']') || is_char(source, token, '}')) && stack->len > 0) {
      stack->len--;
    }
  }
}

/* The written label of each argument up to the one holding `offset`: a name when written `name: value`, else empty. */
typedef struct Argument {
  MsSpan label;
} Argument;
MS_LIST_DEFINE(ArgumentList, argument_list, Argument)

static void collect_arguments(MsSpan source, const LspTokenList *tokens, size_t open, size_t offset, ArgumentList *arguments) {
  size_t depth = 0, count = 0;
  const LspEditorToken *segment[2] = {NULL, NULL};
  for (size_t i = 0; i < tokens->len; i++) {
    const LspEditorToken *token = &tokens->ptr[i];
    if (token->start <= open || token->kind == LSP_TOKEN_COMMENT) continue;
    if (token->start > offset && starts_declaration(source, token)) break;
    const bool close = depth == 0 && is_char(source, token, ')');
    if (close || (depth == 0 && is_char(source, token, ','))) {
      Argument argument = {0};
      if (count >= 2 && segment[0]->kind == LSP_TOKEN_NAME && !token_is(source, segment[0], "fn") && is_char(source, segment[1], ':')) {
        argument.label = ms_span_of(source.ptr + segment[0]->start, segment[0]->end - segment[0]->start);
      }
      argument_list_push(arguments, argument);
      if (close || token->start >= offset) return;
      count = 0;
      segment[0] = segment[1] = NULL;
      continue;
    }
    if (is_char(source, token, '(') || is_char(source, token, '[') || is_char(source, token, '{')) {
      depth++;
    } else if (is_char(source, token, ')') || is_char(source, token, ']') || is_char(source, token, '}')) {
      depth = depth > 0 ? depth - 1 : 0;
    }
    if (is_char(source, token, '\n')) continue;
    if (count < 2) segment[count] = token;
    count++;
  }
  /* An unfinished call has no closing boundary: the segment under the cursor is the last. */
  Argument argument = {0};
  if (count >= 2 && segment[0]->kind == LSP_TOKEN_NAME && !token_is(source, segment[0], "fn") && is_char(source, segment[1], ':')) {
    argument.label = ms_span_of(source.ptr + segment[0]->start, segment[0]->end - segment[0]->start);
  }
  argument_list_push(arguments, argument);
}

/* `source` with every bracket still open at the end of the cursor's line closed, and a value in an argument left empty. */
static MsString close_call(MsSpan source, const LspTokenList *tokens, size_t offset, const char *tail) {
  size_t end = offset;
  while (end < source.len && source.ptr[end] != '\n') end++;
  while (end > offset && (source.ptr[end - 1] == ' ' || source.ptr[end - 1] == '\r' || source.ptr[end - 1] == '\t')) end--;
  OpenList left = {0}; /* the brackets still open where the line is cut: the ones the text after the cursor does not close */
  open_brackets(source, tokens, end, &left);
  const OpenList *stack = &left;
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append(&text, ms_span_of(source.ptr, end));
  const LspEditorToken *last = NULL;
  for (size_t i = 0; i < tokens->len && tokens->ptr[i].start < end; i++) {
    if (tokens->ptr[i].kind != LSP_TOKEN_COMMENT) last = &tokens->ptr[i];
  }
  if (last != NULL && (is_char(source, last, ',') || is_char(source, last, ':') || is_char(source, last, '('))) {
    ms_strbuild_append_text(&text, stack->len > 0 && last->start == stack->ptr[stack->len - 1].at && is_char(source, last, '(') ? "" : " 0");
  }
  for (size_t i = stack->len; i > 0; i--) {
    const uint8_t ch = stack->ptr[i - 1].ch;
    ms_strbuild_append_byte(&text, ch == '(' ? ')' : (ch == '[' ? ']' : '}'));
  }
  open_list_free(&left);
  if (tail != NULL) ms_strbuild_append_text(&text, tail);
  ms_strbuild_append(&text, ms_span_of(source.ptr + end, source.len - end));
  return ms_strbuild_finish(&text);
}

static const MsOccurrence *callee_occurrence(const LspAnalysis *analysis, const LspDoc *doc, size_t callee_end) {
  const size_t last = callee_end - 1;
  for (size_t i = 0; i < analysis->index.len; i++) {
    const MsOccurrence *entry = &analysis->index.ptr[i];
    if (last >= entry->offset && last < entry->end && ms_span_equal(analysis->paths[entry->module], ms_string_span(&doc->path))) {
      return entry;
    }
  }
  return NULL;
}

/* The parameters (or fields of a constructed type) and result of the callee's type; false when it is not callable. */
static bool callable(const MsCheckProgram *program, MsTy ty, const MsTyParam **params, size_t *count, MsTy *result) {
  const MsTyTable *types = &program->types;
  switch (ms_ty_kind(types, ty)) {
    case MS_TY_FUNCTION:
      *params = ms_ty_params(types, ty);
      *count = ms_ty_param_count(types, ty);
      *result = ms_ty_result(types, ty);
      return true;
    case MS_TY_TYPE: {
      const uint32_t def = ms_ty_row(types, ty)->def;
      if (def == 0) return false;
      const MsDef *record = ms_defs_get(&program->defs, def);
      *params = record->fields.ptr;
      *count = record->fields.len;
      *result = ty;
      return true;
    }
    default:
      return false;
  }
}

/* The declared parameters of the callee: function types keep no parameter names in their identity, so the names (and the
 * defaults) come from the declaration. NULL for a callee with no declaration in the program. */
static const MsParams *declared_params(const MsCheckProgram *program, const MsOccurrence *callee) {
  if (callee->symbol != 0 && callee->symbol < program->symbols.len) {
    const MsDecl *decl = program->symbols.ptr[callee->symbol].decl;
    if (decl != NULL && decl->kind == MS_D_FN) return &decl->u.fn.params;
  }
  /* A method's key is `method:<file>:<offset of its declaration>`. */
  if (!callee->method || !ms_span_starts_with(callee->key, ms_span_of_text("method:"))) return NULL;
  size_t colon = callee->key.len;
  while (colon > 0 && callee->key.ptr[colon - 1] != ':') colon--;
  if (colon <= 7) return NULL;
  size_t offset = 0;
  for (size_t i = colon; i < callee->key.len; i++) offset = offset * 10 + (size_t)(callee->key.ptr[i] - '0');
  const MsSpan file = ms_span_of(callee->key.ptr + 7, colon - 1 - 7);
  for (size_t i = 0; i < program->methods.len; i++) {
    const MsMethodEntry *entry = &program->methods.ptr[i];
    if (entry->source != NULL && entry->source->pos.offset == offset &&
        ms_span_equal(ms_names_span(program->names, program->modules.ptr[entry->module].file), file)) {
      return &entry->source->func.params;
    }
  }
  return NULL;
}

/* A generic function named with type arguments (`first[Int](...)`): its occurrence is typed with the generic signature, so the
 * callee is read from the checker's facts instead: the application ending at `name_end`. */
typedef struct Instantiated {
  const MsFacts *facts;
  size_t name_end;
  const MsExpr *apply;
} Instantiated;

static void find_instantiated(void *ctx, const MsExpr *e) {
  Instantiated *found = ctx;
  if (e->kind != MS_E_APPLY || e->u.apply.left->kind != MS_E_NAME) return;
  const MsExpr *name = e->u.apply.left;
  const MsRef *ref = ms_facts_ref(found->facts, name->id);
  if (ref != NULL && ref->kind == MS_REF_FUNCTION && name->pos.offset <= found->name_end && name->end.offset == found->name_end) {
    found->apply = e;
  }
}

static bool instantiated_callee(const LspAnalysis *analysis, const LspDoc *doc, size_t name_end, MsOccurrence *out) {
  const MsCheckProgram *program = &analysis->checked.program;
  for (uint32_t m = 0; m < program->user_modules; m++) {
      if (!ms_span_equal(analysis->paths[m], ms_string_span(&doc->path))) continue;
    Instantiated found = {&program->modules.ptr[m].facts, name_end, NULL};
    const MsVisitor visitor = {.ctx = &found, .expr = find_instantiated};
    const MsModule *tree = program->modules.ptr[m].tree;
    for (uint32_t i = 0; i < tree->ndecls; i++) ms_walk_decl(&visitor, tree->decls[i]);
    if (found.apply == NULL) return false;
    const MsRef *ref = ms_facts_ref(found.facts, found.apply->u.apply.left->id);
    *out = (MsOccurrence){.module = m, .offset = (uint32_t)found.apply->u.apply.left->pos.offset, .end = (uint32_t)name_end,
                          .ty = ms_facts_type(found.facts, found.apply->id)};
    for (size_t s = 1; s < program->symbols.len; s++) {
      const MsSymbol *symbol = &program->symbols.ptr[s];
      if (symbol->module == ref->decl.module && symbol->decl != NULL && symbol->decl->id == ref->decl.node) out->symbol = (MsSymbolId)s;
    }
    return true;
  }
  return false;
}

static void signature_for(LspAnalysis *analysis, const LspDocList *docs, MsSpan source, const Open *call, const ArgumentList *arguments,
                          const MsOccurrence *callee, MsStrBuild *out) {
  (void)docs;
  const MsCheckProgram *program = &analysis->checked.program;
  const MsTyParam *params;
  size_t count;
  MsTy result;
  if (!callable(program, callee->ty, &params, &count, &result)) {
    ms_strbuild_append_text(out, "null");
    return;
  }
  const MsParams *ast = ms_ty_kind(&program->types, callee->ty) == MS_TY_FUNCTION ? declared_params(program, callee) : NULL;
  if (ast != NULL && ast->len != count) ast = NULL;
  /* A constructed type's fields keep their defaults in the declaration. */
  const MsParams *defaults = ast;
  if (ms_ty_kind(&program->types, callee->ty) == MS_TY_TYPE) {
    const MsSymbolId owner = ms_defs_get(&program->defs, ms_ty_row(&program->types, callee->ty)->def)->symbol;
    const MsDecl *decl = owner != 0 ? program->symbols.ptr[owner].decl : NULL;
    if (decl != NULL && decl->kind == MS_D_TYPE && decl->u.type.fields.len == count) defaults = &decl->u.type.fields;
  }
  MsStrBuild label = ms_strbuild_new();
  MsStrBuild parameters = ms_strbuild_new();
  ms_strbuild_append(&label, ms_span_of(source.ptr + call->callee_start, call->callee_end - call->callee_start));
  ms_strbuild_append_byte(&label, '(');
  for (size_t i = 0; i < count; i++) {
    MsStrBuild one = ms_strbuild_new();
    if (params[i].flags & MS_PARAM_VAR) ms_strbuild_append_text(&one, "var ");
    if (ast != NULL || ms_ty_kind(&program->types, callee->ty) != MS_TY_FUNCTION) {
      ms_strbuild_append(&one, ms_names_span(program->names, ast != NULL ? ast->ptr[i]->name : params[i].name));
      ms_strbuild_append_text(&one, " ");
    }
    ms_ty_show_plain(&one, program->names, &program->types, params[i].ty);
    if (defaults != NULL && defaults->ptr[i]->def != NULL) ms_strbuild_append_text(&one, " = ...");
    if (i > 0) ms_strbuild_append_text(&label, ", ");
    ms_strbuild_append(&label, ms_strbuild_span(&one));
    if (i > 0) ms_strbuild_append_byte(&parameters, ',');
    ms_strbuild_append_text(&parameters, "{\"label\":");
    lsp_json_string(&parameters, ms_strbuild_span(&one));
    ms_strbuild_append_byte(&parameters, '}');
    ms_strbuild_free(&one);
  }
  ms_strbuild_append_text(&label, ") ");
  if (result != MS_TY_NONE) ms_ty_show_plain(&label, program->names, &program->types, result);
  /* The active parameter: a written label picks its slot, an unlabeled argument the first slot not yet taken. */
  size_t active = 0;
  bool *used = count == 0 ? NULL : calloc(count, sizeof *used);
  for (size_t i = 0; i < arguments->len; i++) {
    size_t slot = count;
    if (arguments->ptr[i].label.len > 0) {
      for (size_t p = 0; p < count; p++) {
        const MsName name = ast != NULL ? ast->ptr[p]->name : params[p].name;
        if (ms_span_equal(ms_names_span(program->names, name), arguments->ptr[i].label)) {
          slot = p;
          break;
        }
      }
    } else {
      for (size_t p = 0; p < count; p++) {
        if (!used[p]) {
          slot = p;
          break;
        }
      }
    }
    if (slot < count) {
      active = slot;
      used[slot] = true;
    }
  }
  free(used);
  ms_strbuild_append_text(out, "{\"signatures\":[{\"label\":");
  lsp_json_string(out, ms_strbuild_span(&label));
  ms_strbuild_append_text(out, ",\"parameters\":[");
  ms_strbuild_append(out, ms_strbuild_span(&parameters));
  ms_strbuild_append_text(out, "],\"documentation\":");
  /* The declaration's documentation, when its source is in the graph. */
  bool documented = false;
  for (size_t i = 0; i < analysis->index.len && !documented; i++) {
    const MsOccurrence *entry = &analysis->index.ptr[i];
    if (!entry->declaration || !ms_span_equal(entry->key, callee->key)) continue;
    const MsSpan text = program->modules.ptr[entry->module].source;
    size_t line = 1;
    for (size_t at = 0; at < entry->offset; at++) line += text.ptr[at] == '\n';
    const MsSpan comment = ms_declaration_comment(analysis->arena, text, entry->offset, (uint32_t)line);
    if (comment.len > 0) {
      ms_strbuild_append_text(out, "{\"kind\":\"markdown\",\"value\":");
      lsp_json_string(out, comment);
      ms_strbuild_append_byte(out, '}');
      documented = true;
    }
  }
  if (!documented && callee->symbol != 0 && callee->key.len == 0) {
    const MsSymbol *symbol = &program->symbols.ptr[callee->symbol];
    const MsSpan text = program->modules.ptr[symbol->module].source;
    size_t line = 1;
    for (size_t at = 0; at < symbol->decl->pos.offset; at++) line += text.ptr[at] == '\n';
    const MsSpan comment = ms_declaration_comment(analysis->arena, text, symbol->decl->pos.offset, (uint32_t)line);
    if (comment.len > 0) {
      ms_strbuild_append_text(out, "{\"kind\":\"markdown\",\"value\":");
      lsp_json_string(out, comment);
      ms_strbuild_append_byte(out, '}');
      documented = true;
    }
  }
  if (!documented) ms_strbuild_append_text(out, "null");
  ms_strbuild_printf(out, "}],\"activeSignature\":0,\"activeParameter\":%zu}", active);
  ms_strbuild_free(&label);
  ms_strbuild_free(&parameters);
}

/* Where the interpolation holding `offset` starts (just after its `{`) when `token` is an f-string, else SIZE_MAX. An
 * unfinished literal reaches the end of the text. */
static size_t interpolation_start(MsSpan source, const LspEditorToken *token, size_t offset, const char **tail) {
  if (tail != NULL) *tail = NULL;
  const size_t length = token->end - token->start;
  if (length < 2 || source.ptr[token->start] != 'f') return SIZE_MAX;
  const bool triple = length >= 4 && source.ptr[token->start + 2] == '"' && source.ptr[token->start + 3] == '"';
  const size_t open = triple ? 4 : 2;
  const bool closed = triple ? length >= 7 && source.ptr[token->end - 1] == '"' && source.ptr[token->end - 2] == '"' && source.ptr[token->end - 3] == '"'
                             : length >= 3 && source.ptr[token->end - 1] == '"';
  if (tail != NULL && !closed) *tail = triple ? "}\n\"\"\"" : "}\"";
  if (offset <= token->start + open - 1 || offset > token->end || (offset == token->end && closed)) return SIZE_MAX;
  size_t depth = 0, from = SIZE_MAX;
  for (size_t at = token->start + open; at < offset && at < token->end;) {
    const uint8_t ch = source.ptr[at];
    if (depth == 0) {
      if (ch == '\\') at += 2;
      else if (ch == '{') {
        depth = 1;
        from = at + 1;
        at++;
      } else at++;
    } else {
      if (ch == '{') depth++;
      else if (ch == '}' && --depth == 0) from = SIZE_MAX;
      at++;
    }
  }
  return depth > 0 ? from : SIZE_MAX;
}

void lsp_signature_help(const LspDocList *docs, const LspDoc *doc, LspPosition position, MsStrBuild *out) {
  const MsSpan source = ms_string_span(&doc->text);
  size_t offset;
  if (!lsp_offset(source, position, false, &offset)) {
    ms_strbuild_append_text(out, "null");
    return;
  }
  const char *tail = NULL;
  LspTokenList tokens = {0};
  lsp_scan_tokens(source, &tokens);
  for (size_t i = 0; i < tokens.len; i++) {
    const LspEditorToken *token = &tokens.ptr[i];
    if (token->kind != LSP_TOKEN_STRING && token->kind != LSP_TOKEN_COMMENT) continue;
    if (!(offset > token->start && offset < token->end)) {
      if (!(token->kind == LSP_TOKEN_STRING && offset == token->end && interpolation_start(source, token, offset, NULL) != SIZE_MAX)) continue;
    }
    const size_t from = token->kind == LSP_TOKEN_STRING ? interpolation_start(source, token, offset, &tail) : SIZE_MAX;
    if (from == SIZE_MAX) {
      /* Inside a comment or a literal, there is no call to help with. */
      ms_strbuild_append_text(out, "null");
      lsp_token_list_free(&tokens);
      return;
    }
    /* Inside an interpolation the cursor is in ordinary code: scan from there. */
    lsp_token_list_free(&tokens);
    lsp_scan_tokens(ms_span_of(source.ptr + from, source.len - from), &tokens);
    for (size_t t = 0; t < tokens.len; t++) {
      tokens.ptr[t].start += from;
      tokens.ptr[t].end += from;
    }
    break;
  }
  OpenList stack = {0};
  open_brackets(source, &tokens, offset, &stack);
  const Open *call = NULL;
  for (size_t i = stack.len; i > 0 && call == NULL; i--) {
    if (stack.ptr[i - 1].ch == '(' && stack.ptr[i - 1].callee) call = &stack.ptr[i - 1];
  }
  if (call == NULL) {
    ms_strbuild_append_text(out, "null");
    goto done;
  }
  ArgumentList arguments = {0};
  collect_arguments(source, &tokens, call->at, offset, &arguments);
  /* The document as written first; when its declaration did not parse, with the call closed so that it does. */
  LspAnalysis analysis;
  lsp_analyze(docs, doc, &analysis);
  /* A generic function written with type arguments (`first[Int](`) takes its signature from the instantiation. */
  MsOccurrence instantiated;
  const MsOccurrence *callee = NULL;
  if (analysis.resolved && instantiated_callee(&analysis, doc, call->name_end, &instantiated)) callee = &instantiated;
  if (callee == NULL && analysis.resolved) callee = callee_occurrence(&analysis, doc, call->name_end);
  MsString repaired = {0};
  if (callee == NULL || ms_ty_is_invalid(&analysis.checked.program.types, callee->ty)) {
    lsp_analysis_release(&analysis);
    repaired = close_call(source, &tokens, offset, tail);
    const MsOverlayFile changed = {ms_string_span(&doc->path), ms_string_span(&repaired)};
    lsp_analyze_changed(docs, doc, &changed, 1, &analysis);
    callee = NULL;
    if (analysis.resolved && instantiated_callee(&analysis, doc, call->name_end, &instantiated)) callee = &instantiated;
    if (callee == NULL && analysis.resolved) callee = callee_occurrence(&analysis, doc, call->name_end);
  }
  if (callee == NULL) {
    ms_strbuild_append_text(out, "null");
  } else {
    signature_for(&analysis, docs, source, call, &arguments, callee, out);
  }
  lsp_analysis_release(&analysis);
  ms_string_release(&repaired);
  argument_list_free(&arguments);
done:
  open_list_free(&stack);
  lsp_token_list_free(&tokens);
}
