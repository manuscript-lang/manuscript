/* lsp/lsp_semantic.c: semantic tokens. Every token of the text is classified from its lexeme; names the checker
 * resolved take the kind of what they denote. Text that does not lex falls back to the forgiving scanner. */
#include "lsp/lsp_semantic.h"

#include <stdlib.h>
#include <string.h>

#include "lsp/lsp_internal.h"
#include "compiler/syntax/lex.h"

enum { KIND_KEYWORD, KIND_VARIABLE, KIND_NUMBER, KIND_STRING, KIND_COMMENT, KIND_FUNCTION, KIND_TYPE, KIND_PROPERTY,
       KIND_PARAMETER, KIND_ENUM_MEMBER, KIND_TYPE_PARAMETER };

typedef enum Lex { LEX_NAME, LEX_NUMBER, LEX_STRING, LEX_COMMENT, LEX_KEYWORD, LEX_SKIP } Lex;

typedef struct SemanticToken {
  Lex kind;
  bool previous_fn, previous_type;
  bool receiver; /* the receiver type of `fn Type.method` or `fn Type[T].method` */
  bool bound;    /* a capitalized name inside the brackets of such a receiver: a bound on its parameter */
  size_t start, end;
} SemanticToken;

MS_LIST_DEFINE(SemanticList, semantic_list, SemanticToken)

typedef struct Resolved {
  size_t offset;
  uint8_t kind;
} Resolved;

MS_LIST_DEFINE(ResolvedList, resolved_list, Resolved)

static bool is_keyword_text(MsSpan text) {
  for (int kind = 0; kind < MS_T_COUNT; kind++) {
    const char *name = ms_tok_str((MsTok)kind);
    if (name[0] < 'a' || name[0] > 'z') continue;
    if (ms_span_is_text(text, name)) return true;
  }
  return false;
}

static MsSpan lexeme(MsSpan source, const SemanticToken *token) {
  return ms_span_of(source.ptr + token->start, token->end - token->start);
}

/* `opaque` is contextual: a keyword only in front of `type` or `enum`. */
static void mark_opaque(MsSpan source, SemanticList *tokens) {
  for (size_t i = 1; i < tokens->len; i++) {
    SemanticToken *previous = &tokens->ptr[i - 1];
    if (previous->kind == LEX_NAME && ms_span_is_text(lexeme(source, previous), "opaque") &&
        tokens->ptr[i].kind == LEX_KEYWORD &&
        (ms_span_is_text(lexeme(source, &tokens->ptr[i]), "type") || ms_span_is_text(lexeme(source, &tokens->ptr[i]), "enum"))) {
      previous->kind = LEX_KEYWORD;
    }
  }
}

static bool word_is(MsSpan source, const SemanticList *tokens, size_t at, const char *word) {
  return at < tokens->len && ms_span_is_text(lexeme(source, &tokens->ptr[at]), word);
}

/* Whether the name at `i` follows `fn`, optionally with `var` or `move` between. */
static bool receiver_position(MsSpan source, const SemanticList *tokens, size_t i) {
  if (i >= 1 && word_is(source, tokens, i - 1, "fn")) return true;
  return i >= 2 && (word_is(source, tokens, i - 1, "var") || word_is(source, tokens, i - 1, "move")) &&
         word_is(source, tokens, i - 2, "fn");
}

/* Marks the receiver name of `fn [var|move] Type[...].method`: a type, not the function. */
static void mark_receivers(MsSpan source, SemanticList *tokens) {
  for (size_t i = 0; i < tokens->len; i++) {
    if (tokens->ptr[i].kind != LEX_NAME || !receiver_position(source, tokens, i)) continue;
    size_t next = i + 1;
    size_t bounds[64];
    size_t bound_count = 0;
    if (word_is(source, tokens, next, "[")) {
      size_t depth = 0;
      while (next < tokens->len) {
        const MsSpan text = lexeme(source, &tokens->ptr[next]);
        if (ms_span_is_text(text, "[")) depth++;
        else if (ms_span_is_text(text, "]")) depth--;
        else if (tokens->ptr[next].kind == LEX_NAME && text.len > 0 && text.ptr[0] >= 'A' && text.ptr[0] <= 'Z' &&
                 bound_count < 64) bounds[bound_count++] = next;
        next++;
        if (depth == 0) break;
      }
    }
    if (word_is(source, tokens, next, ".")) {
      tokens->ptr[i].receiver = true;
      for (size_t b = 0; b < bound_count; b++) tokens->ptr[bounds[b]].bound = true;
    }
  }
}

static int compare_start(const void *left, const void *right) {
  const SemanticToken *a = left, *b = right;
  return a->start == b->start ? 0 : (a->start < b->start ? -1 : 1);
}

static void scan(MsSpan source, SemanticList *tokens) {
  MsArena arena = ms_arena_new();
  MsLexed lexed;
  MsDiag diag;
  if (ms_lex(&arena, source, &lexed, &diag)) {
    MsTok previous = MS_T_Eof;
    for (size_t i = 0; i < lexed.ntokens; i++) {
      const MsToken *t = &lexed.tokens[i];
      Lex kind;
      switch ((MsTok)t->kind) {
      case MS_T_Name: kind = LEX_NAME; break;
      case MS_T_Number: kind = LEX_NUMBER; break;
      case MS_T_String: kind = LEX_STRING; break;
      case MS_T_Comment: kind = LEX_COMMENT; break;
      case MS_T_Newline:
      case MS_T_Indent:
      case MS_T_Dedent:
      case MS_T_Eof: kind = LEX_SKIP; break;
      default: {
        const char first = ms_tok_str((MsTok)t->kind)[0];
        kind = first >= 'a' && first <= 'z' ? LEX_KEYWORD : LEX_SKIP;
      }
      }
      const bool zero_width = t->end.offset <= t->pos.offset;
      const MsTok before = previous;
      previous = (MsTok)t->kind;
      /* Indent, Dedent and Eof take no source text and share their offset with the next token; qsort leaves
       * equal keys in any order, and where one landed between `fn` and its receiver the receiver lost its kind. */
      if (zero_width) continue;
      semantic_list_push(tokens, (SemanticToken){.kind = kind,
                                                 .previous_fn = before == MS_T_Fn,
                                                 .previous_type = before == MS_T_Type || before == MS_T_Enum,
                                                 .start = t->pos.offset,
                                                 .end = t->end.offset});
    }
    /* The strict lexer drops comments, as the oracle's does: only the forgiving scan below colours them. */
    qsort(tokens->ptr, tokens->len, sizeof(SemanticToken), compare_start);
  } else {
    /* The text does not lex: fall back to the forgiving scanner. */
    LspTokenList scanned = {0};
    lsp_scan_tokens(source, &scanned);
    MsSpan previous = {0};
    for (size_t i = 0; i < scanned.len; i++) {
      const LspEditorToken *t = &scanned.ptr[i];
      const MsSpan text = ms_span_of(source.ptr + t->start, t->end - t->start);
      Lex kind = LEX_SKIP;
      if (t->kind == LSP_TOKEN_NAME) {
        kind = is_keyword_text(text) ? LEX_KEYWORD : (text.ptr[0] >= '0' && text.ptr[0] <= '9' ? LEX_NUMBER : LEX_NAME);
      } else if (t->kind == LSP_TOKEN_STRING) {
        kind = LEX_STRING;
      } else if (t->kind == LSP_TOKEN_COMMENT) {
        kind = LEX_COMMENT;
      }
      semantic_list_push(tokens, (SemanticToken){.kind = kind,
                                                 .previous_fn = ms_span_is_text(previous, "fn"),
                                                 .previous_type = ms_span_is_text(previous, "type") || ms_span_is_text(previous, "enum"),
                                                 .start = t->start,
                                                 .end = t->end});
      previous = t->kind == LSP_TOKEN_NAME ? text : (MsSpan){0};
    }
    lsp_token_list_free(&scanned);
  }
  ms_arena_free(&arena);
  mark_opaque(source, tokens);
  mark_receivers(source, tokens);
}

static bool key_starts(MsSpan key, const char *prefix) {
  return ms_span_starts_with(key, ms_span_of_text(prefix));
}

static uint8_t kind_of(const MsCheckProgram *program, const MsOccurrence *entry) {
  if (key_starts(entry->key, "field:")) return KIND_PROPERTY;
  if (key_starts(entry->key, "parameter:")) return KIND_PARAMETER;
  if (key_starts(entry->key, "case:")) return KIND_ENUM_MEMBER;
  /* A bare standard constructor (`null`, `ok`) is keyed as a native; only its type tells it from a native function. */
  if (key_starts(entry->key, "native:") && entry->ty != MS_TY_NONE && ms_ty_kind(&program->types, entry->ty) != MS_TY_FUNCTION) {
    return KIND_ENUM_MEMBER;
  }
  if (key_starts(entry->key, "binding:typeparam:")) return KIND_TYPE_PARAMETER;
  const MsSymbol *symbol = entry->symbol != 0 ? &program->symbols.ptr[entry->symbol] : NULL;
  if (symbol != NULL && symbol->kind == MS_SYMBOL_TYPE) return KIND_TYPE;
  const bool constant = symbol != NULL && symbol->decl != NULL && symbol->decl->kind == MS_D_CONST;
  if (entry->ty != MS_TY_NONE && ms_ty_kind(&program->types, entry->ty) == MS_TY_FUNCTION && !constant) return KIND_FUNCTION;
  return KIND_VARIABLE;
}

static const Resolved *resolved_at(const ResolvedList *list, size_t offset) {
  for (size_t i = 0; i < list->len; i++) {
    if (list->ptr[i].offset == offset) return &list->ptr[i];
  }
  return NULL;
}

void lsp_semantic_tokens(const LspDocList *docs, const LspDoc *doc, MsStrBuild *out) {
  const MsSpan source = ms_string_span(&doc->text);
  SemanticList tokens = {0};
  scan(source, &tokens);
  LspAnalysis analysis;
  lsp_analyze(docs, doc, &analysis);
  ResolvedList resolved = {0};
  for (size_t i = 0; analysis.resolved && i < analysis.index.len; i++) {
    const MsOccurrence *entry = &analysis.index.ptr[i];
    if (!ms_span_equal(analysis.paths[entry->module], ms_string_span(&doc->path))) continue;
    const uint8_t kind = kind_of(&analysis.checked.program, entry);
    /* A bare constructor has an occurrence per identity (its case and its native); the case colours it. */
    bool known = false;
    for (size_t r = 0; r < resolved.len; r++) {
      if (resolved.ptr[r].offset != entry->offset) continue;
      known = true;
      if (kind == KIND_ENUM_MEMBER) resolved.ptr[r].kind = kind;
    }
    if (known) continue;
    resolved_list_push(&resolved, (Resolved){entry->offset, kind});
  }
  /* A written type is a type even when it has no declaration to index, like `Int`. */
  for (size_t i = 0; i < analysis.written.len; i++) {
    const MsWrittenType *site = &analysis.written.ptr[i];
    if (!ms_span_equal(analysis.paths[site->module], ms_string_span(&doc->path)) || resolved_at(&resolved, site->offset) != NULL) continue;
    const bool variable = ms_ty_kind(&analysis.checked.program.types, site->ty) == MS_TY_VARIABLE;
    resolved_list_push(&resolved, (Resolved){site->offset, variable ? KIND_TYPE_PARAMETER : KIND_TYPE});
  }
  ms_strbuild_append_text(out, "{\"data\":[");
  size_t line = 0, character = 0;
  bool first = true;
  for (size_t i = 0; i < tokens.len; i++) {
    const SemanticToken *token = &tokens.ptr[i];
    int64_t kind;
    switch (token->kind) {
    case LEX_NAME: kind = KIND_VARIABLE; break;
    case LEX_NUMBER: kind = KIND_NUMBER; break;
    case LEX_STRING: kind = KIND_STRING; break;
    case LEX_COMMENT: kind = KIND_COMMENT; break;
    case LEX_KEYWORD: kind = KIND_KEYWORD; break;
    default: continue;
    }
    if (token->kind == LEX_NAME) {
      const Resolved *found = resolved_at(&resolved, token->start);
      if (found != NULL) kind = found->kind;
      if (token->previous_fn) kind = KIND_FUNCTION;
      if (token->previous_type || token->receiver || (token->bound && kind == KIND_VARIABLE)) kind = KIND_TYPE;
    }
    /* A token that spans lines is reported one line at a time. */
    size_t at = token->start;
    while (at < token->end) {
      size_t stop = at;
      while (stop < token->end && source.ptr[stop] != '\n') stop++;
      size_t body = stop;
      if (body > at && source.ptr[body - 1] == '\r') body--;
      const LspPosition start = lsp_position(source, at), end = lsp_position(source, body);
      if (end.character > start.character) {
        const int64_t length = (int64_t)(end.character - start.character);
        int64_t delta = (int64_t)start.character;
        if (start.line == line) delta -= (int64_t)character;
        if (!first) ms_strbuild_append_byte(out, ',');
        first = false;
        ms_strbuild_printf(out, "%lld,%lld,%lld,%lld,0", (long long)((int64_t)start.line - (int64_t)line), (long long)delta,
                           (long long)length, (long long)kind);
        line = start.line;
        character = start.character;
      }
      at = stop + 1;
    }
  }
  ms_strbuild_append_text(out, "]}");
  resolved_list_free(&resolved);
  semantic_list_free(&tokens);
  lsp_analysis_release(&analysis);
}
