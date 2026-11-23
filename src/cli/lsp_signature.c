/* cli/lsp_signature.c: the call around the cursor found from the forgiving token scan, its callee resolved by the checker
 * over the document with the unfinished call closed, its parameters read from the callee's type. */
#include "cli/lsp_signature.h"

#include <stdlib.h>

#include "tooling/doc_comment.h"

typedef struct Open {
  uint8_t ch;
  size_t at;
  bool callee; /* a `(` that directly follows a name: a call */
  size_t callee_start, callee_end;
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

/* The brackets still open at `offset`, innermost last. */
static void open_brackets(MsSpan source, const LspTokenList *tokens, size_t offset, OpenList *stack) {
  for (size_t i = 0; i < tokens->len && tokens->ptr[i].start < offset; i++) {
    const LspEditorToken *token = &tokens->ptr[i];
    if (starts_declaration(source, token)) {
      stack->len = 0;
    } else if (is_char(source, token, '(') || is_char(source, token, '[') || is_char(source, token, '{')) {
      Open open = {.ch = source.ptr[token->start], .at = token->start};
      if (open.ch == '(' && i > 0 && tokens->ptr[i - 1].kind == LSP_TOKEN_NAME && tokens->ptr[i - 1].end == token->start &&
          !is_keyword(source, &tokens->ptr[i - 1])) {
        size_t first = i - 1;
        while (first >= 2 && is_char(source, &tokens->ptr[first - 1], '.') && tokens->ptr[first - 1].start == tokens->ptr[first].start - 1 &&
               tokens->ptr[first - 2].kind == LSP_TOKEN_NAME && tokens->ptr[first - 2].end == tokens->ptr[first - 1].start) {
          first -= 2;
        }
        open.callee = true;
        open.callee_start = tokens->ptr[first].start;
        open.callee_end = tokens->ptr[i - 1].end;
      }
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
  bool lambda = false;
  const LspEditorToken *segment[2] = {NULL, NULL};
  for (size_t i = 0; i < tokens->len; i++) {
    const LspEditorToken *token = &tokens->ptr[i];
    if (token->start <= open || token->kind == LSP_TOKEN_COMMENT) continue;
    if (token->start > offset && starts_declaration(source, token)) break;
    const bool close = depth == 0 && is_char(source, token, ')');
    if (close || (depth == 0 && is_char(source, token, ',') && !lambda)) {
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
    } else if (depth == 0 && token_is(source, token, "fn")) {
      lambda = true;
    } else if (depth == 0 && is_char(source, token, ':')) {
      lambda = false;
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
static MsString close_call(MsSpan source, const LspTokenList *tokens, size_t offset, const OpenList *stack) {
  size_t end = offset;
  while (end < source.len && source.ptr[end] != '\n') end++;
  while (end > offset && (source.ptr[end - 1] == ' ' || source.ptr[end - 1] == '\r' || source.ptr[end - 1] == '\t')) end--;
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append(&text, ms_span_of(source.ptr, end));
  const LspEditorToken *last = NULL;
  for (size_t i = 0; i < tokens->len && tokens->ptr[i].start < end; i++) {
    if (tokens->ptr[i].kind != LSP_TOKEN_COMMENT) last = &tokens->ptr[i];
  }
  if (last != NULL && (is_char(source, last, ',') || is_char(source, last, ':') || is_char(source, last, '('))) {
    ms_strbuild_append_text(&text, last->start == stack->ptr[stack->len - 1].at && is_char(source, last, '(') ? "" : " 0");
  }
  for (size_t i = stack->len; i > 0; i--) {
    const uint8_t ch = stack->ptr[i - 1].ch;
    ms_strbuild_append_byte(&text, ch == '(' ? ')' : (ch == '[' ? ']' : '}'));
  }
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
  MsStrBuild label = ms_strbuild_new();
  MsStrBuild parameters = ms_strbuild_new();
  ms_strbuild_append(&label, ms_span_of(source.ptr + call->callee_start, call->callee_end - call->callee_start));
  ms_strbuild_append_byte(&label, '(');
  for (size_t i = 0; i < count; i++) {
    MsStrBuild one = ms_strbuild_new();
    if (params[i].flags & MS_PARAM_VAR) ms_strbuild_append_text(&one, "var ");
    if (ast != NULL || ms_ty_kind(&program->types, callee->ty) != MS_TY_FUNCTION) {
      ms_strbuild_append(&one, ms_names_span(program->names, ast != NULL ? ast->ptr[i]->name : params[i].name));
      ms_strbuild_append_text(&one, ": ");
    }
    ms_ty_show(&one, program->names, &program->types, params[i].ty);
    if (ast != NULL && ast->ptr[i]->def != NULL) ms_strbuild_append_text(&one, " = ...");
    if (i > 0) ms_strbuild_append_text(&label, ", ");
    ms_strbuild_append(&label, ms_strbuild_span(&one));
    if (i > 0) ms_strbuild_append_byte(&parameters, ',');
    ms_strbuild_append_text(&parameters, "{\"label\":");
    lsp_json_string(&parameters, ms_strbuild_span(&one));
    ms_strbuild_append_byte(&parameters, '}');
    ms_strbuild_free(&one);
  }
  ms_strbuild_append_text(&label, ") ");
  if (result != MS_TY_NONE) ms_ty_show(&label, program->names, &program->types, result);
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
  if (!documented) ms_strbuild_append_text(out, "null");
  ms_strbuild_printf(out, "}],\"activeSignature\":0,\"activeParameter\":%zu}", active);
  ms_strbuild_free(&label);
  ms_strbuild_free(&parameters);
}

void lsp_signature_help(const LspDocList *docs, const LspDoc *doc, LspPosition position, MsStrBuild *out) {
  const MsSpan source = ms_string_span(&doc->text);
  size_t offset;
  if (!lsp_offset(source, position, false, &offset)) {
    ms_strbuild_append_text(out, "null");
    return;
  }
  LspTokenList tokens = {0};
  lsp_scan_tokens(source, &tokens);
  for (size_t i = 0; i < tokens.len; i++) {
    const LspEditorToken *token = &tokens.ptr[i];
    if (token->kind != LSP_TOKEN_CHAR && offset > token->start && offset < token->end) {
      /* Inside a comment or a literal, there is no call to help with. */
      if (token->kind == LSP_TOKEN_COMMENT || token->kind == LSP_TOKEN_STRING) {
        ms_strbuild_append_text(out, "null");
        lsp_token_list_free(&tokens);
        return;
      }
    }
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
  const MsOccurrence *callee = analysis.resolved ? callee_occurrence(&analysis, doc, call->callee_end) : NULL;
  MsString repaired = {0};
  if (callee == NULL || ms_ty_is_invalid(&analysis.checked.program.types, callee->ty)) {
    lsp_analysis_release(&analysis);
    repaired = close_call(source, &tokens, offset, &stack);
    const MsOverlayFile changed = {ms_string_span(&doc->path), ms_string_span(&repaired)};
    lsp_analyze_changed(docs, doc, &changed, 1, &analysis);
    callee = analysis.resolved ? callee_occurrence(&analysis, doc, call->callee_end) : NULL;
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
