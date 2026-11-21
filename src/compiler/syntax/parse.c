/* Owns the parser entry point: imports, the module loop and the exported API. */
#include "compiler/syntax/parse_internal.h"

MS_LIST_DEFINE(ImportList, import_list, MsImport)
MS_LIST_DEFINE(DeclList, decl_list, MsDecl *)

/* ---- module ---- */

MS_NODISCARD static bool import_path(Parser *p, MsSpan *out) {
  MsToken token = {0};
  if (!parse_need_token(p, MS_T_String, &token))
    return false;
  if (!parse_single_line(p, token, "import paths"))
    return false;
  TextParts parts = {0};
  if (!parse_text_parts_of(p, token, &parts))
    return false;
  MsSpan result;
  if (!parse_plain_text(parts, &result)) {
    parse_fail(p, token,
               ms_span_of_text("import paths cannot interpolate; write the path as plain text without {…}"));
    return false;
  }
  *out = result;
  return true;
}

MS_NODISCARD static bool import_names(Parser *p, bool wrapped, uint32_t *count, MsToken **out) {
  size_t m = parse_mark(p);
  for (;;) {
    MsToken n = {0};
    if (!parse_need_token(p, MS_T_Name, &n))
      return false;
    parse_push(p, &n, sizeof n);
    if (parse_kind(p) == MS_T_Name && parse_text_is(p, parse_peek(p), "as")) {
      parse_fail(
          p, parse_peek(p),
          ms_span_of_text("imports cannot be renamed with 'as'; import the name as the module declares it"));
      return false;
    }
    if (!parse_take(p, MS_T_Comma) || (wrapped && parse_kind(p) == MS_T_RParen)) {
      break;
    }
  }
  *out = parse_finish(p, m, count, sizeof(MsToken), _Alignof(MsToken));
  return true;
}

static void push_imports(Parser *p, ImportList *imports, MsPos pos, const MsToken *names, uint32_t n,
                         MsSpan path) {
  MsPos clause = names[0].pos;
  for (uint32_t i = 0; i < n; i++) {
    MsImport im;
    im.id = parse_new_id(p);
    im.pos = pos;
    im.clause = clause;
    im.name_pos = names[i].pos;
    im.name = parse_sym(p, names[i]);
    im.path = path;
    import_list_push(imports, im);
  }
}

/* The rest of an import after `import`: `a, b from "path"`, `(a, b) from "path"`, or a group of
 * clauses `(a, b from "path", c from "other")`. */
MS_NODISCARD static bool import_statement(Parser *p, ImportList *imports) {
  MsPos pos = parse_previous(p).pos;
  if (parse_kind(p) == MS_T_Star) {
    parse_fail(p, parse_peek(p),
               ms_span_of_text("namespace and wildcard imports are unsupported; import individual exports "
                               "with 'import Name, OtherName from \"./module.ms\"'"));
    return false;
  }
  if (parse_kind(p) == MS_T_LBrace) {
    parse_fail(p, parse_peek(p),
               ms_span_of_text("imports take no braces; write 'import a, b from \"path.ms\"', or 'import (a, "
                               "b) from \"path.ms\"' to wrap across lines"));
    return false;
  }
  bool wrapped = parse_take(p, MS_T_LParen);
  for (;;) {
    uint32_t n;
    MsToken *names = NULL;
    if (!import_names(p, wrapped, &n, &names))
      return false;
    if (wrapped && parse_kind(p) == MS_T_RParen) {
      if (!parse_need(p, MS_T_RParen))
        return false;
      if (!parse_need_from(p))
        return false;
      MsSpan path = {0};
      if (!import_path(p, &path))
        return false;
      push_imports(p, imports, pos, names, n, path);
      break;
    }
    if (!parse_need_from(p))
      return false;
    MsSpan path = {0};
    if (!import_path(p, &path))
      return false;
    push_imports(p, imports, pos, names, n, path);
    if (!wrapped) {
      break;
    }
    if (!parse_take(p, MS_T_Comma) || parse_kind(p) == MS_T_RParen) {
      if (!parse_need(p, MS_T_RParen))
        return false;
      break;
    }
  }
  if (!parse_end(p))
    return false;
  return true;
}

MS_NODISCARD static bool parse_module(Parser *p, ImportList *imports, DeclList *decls) {
  while (parse_kind(p) != MS_T_Eof) {
    parse_newlines(p);
    if (parse_kind(p) == MS_T_Eof) {
      break;
    }
    if (parse_take(p, MS_T_Import)) {
      if (!import_statement(p, imports))
        return false;
      continue;
    }
    if (parse_kind(p) == MS_T_Name && parse_text_is(p, parse_peek(p), "from") &&
        parse_ahead(p, 1).kind == MS_T_String) {
      parse_fail(p, parse_peek(p), ms_span_of_text("imports read: import name, other from \"path.ms\""));
      return false;
    }
    MsToken export_tok = parse_peek(p);
    bool exported = parse_take(p, MS_T_Export);
    MsDecl *d = NULL;
    if (!parse_declaration(p, &d))
      return false;
    if (exported && (d->kind == MS_D_IMPL || d->kind == MS_D_TEST)) {
      parse_fail(
          p, export_tok,
          ms_span_of_text("only types, interfaces, and named functions can be exported; remove 'export' "
                          "before this method, impl, test, or bench (a method is exported with its type)"));
      return false;
    }
    d->is_exported = exported;
    decl_list_push(decls, d);
  }
  return true;
}

/* Copies a scratch list into the arena; the result is never NULL. */
static void *copy_out(MsArena *arena, const void *items, size_t count, size_t size, size_t alignment) {
  size_t bytes = 0;
  if (!ms_size_mul(count, size, &bytes)) {
    ms_fatal(MS_FATAL_OVERFLOW, "module size overflows");
  }
  void *copy = ms_arena_alloc(arena, bytes ? bytes : 1, alignment);
  if (bytes != 0) {
    __builtin_memcpy(copy, items, bytes);
  }
  return copy;
}

bool ms_parse(MsArena *arena, MsNames *names, MsSpan source, MsModule *out, MsDiag *diag) {
  return ms_parse_chunk(arena, names, source, (MsChunk){0}, out, diag);
}

bool ms_parse_chunk(MsArena *arena, MsNames *names, MsSpan source, MsChunk chunk, MsModule *out,
                    MsDiag *diag) {
  *out = (MsModule){0};
  MsLexed lexed;
  if (!ms_lex_at(arena, source, chunk.base_offset, chunk.base_line, &lexed, diag)) {
    return false;
  }
  ScratchList scratch = {0};
  ScratchList bytes = {0};
  ImportList imports = {0};
  DeclList decls = {0};
  Parser p = {.arena = arena,
              .names = names,
              .source = lexed.source,
              .tokens = lexed.tokens,
              .ntokens = lexed.ntokens,
              .bounds = &lexed.bounds,
              .type_brackets = parse_compute_type_brackets(arena, lexed.tokens, lexed.ntokens),
              .scratch = &scratch,
              .bytes = &bytes,
              .next_id = chunk.first_id,
              .diag = diag};
  bool ok = parse_module(&p, &imports, &decls);
  if (ok) {
    out->nimports = (uint32_t)imports.len;
    out->imports = copy_out(arena, imports.ptr, imports.len, sizeof(MsImport), _Alignof(MsImport));
    out->ndecls = (uint32_t)decls.len;
    out->decls = copy_out(arena, decls.ptr, decls.len, sizeof(MsDecl *), _Alignof(MsDecl *));
    out->node_count = p.next_id;
  }
  scratch_list_free(&scratch);
  scratch_list_free(&bytes);
  import_list_free(&imports);
  decl_list_free(&decls);
  return ok;
}
