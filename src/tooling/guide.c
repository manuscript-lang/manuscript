/* Owns the snapshot half of guide.h: reads the bundled standard sources and documents each importable module. */
#include "abi/prelude.h"
#include "tooling/guide.h"

#include "base/message.h"
#include "base/sort.h"
#include "base/strbuild.h"
#include "compiler/check/program.h"
#include "compiler/project/project.h"
#include "compiler/syntax/ast.h"
#include "compiler/syntax/lex.h"
#include "compiler/syntax/parse.h"
#include "tooling/doc_comment.h"

typedef struct StdFile {
  MsSpan path; /* `@std/os/fs.ms` */
  MsSpan source;
  MsModule tree;
  MsToken *tokens;
  size_t ntokens;
  bool lexed, mixed, inherent_body;
} StdFile;

typedef struct MethodRef {
  const MsDecl *impl;
  const MsMethod *method;
  const StdFile *file;
} MethodRef;
MS_AVEC(MethodRefs, method_refs, MethodRef)

typedef struct Symbol {
  const StdFile *file; /* NULL for a primitive */
  const MsDecl *decl;  /* NULL for a primitive */
  MsSpan name;
  MethodRefs folded, implemented;
  MsApiDecl api;
  bool built;
} Symbol;
MS_AVEC(Symbols, symbols, Symbol *)

typedef struct Guide {
  MsArena *arena;
  MsNames *names;
  StdFile *files;
  size_t nfiles;
  Symbols symbols;
} Guide;

static MsSpan primitive_documentation(MsSpan id) {
  static const struct {
    const char *name, *doc;
  } DOCS[] = {
      {"Bool", "Boolean truth values true and false; conditions require this type."},
      {"Int", "Signed whole numbers with checked arithmetic; overflow and division by zero fault."},
      {"Float", "Binary floating-point values, including signed zero, infinities and NaN."},
      {"Int8", "Signed 8-bit whole numbers (-128 to 127); arithmetic faults when the result leaves the range."},
      {"Int16", "Signed 16-bit whole numbers (-32768 to 32767); arithmetic faults when the result leaves the range."},
      {"Int32", "Signed 32-bit whole numbers (-2147483648 to 2147483647); arithmetic faults when the result leaves the range."},
      {"Int64", "Signed 64-bit whole numbers; the same type as Int while Int is 64 bits wide."},
      {"UInt8", "Unsigned 8-bit whole numbers (0 to 255); arithmetic faults when the result leaves the range."},
      {"UInt16", "Unsigned 16-bit whole numbers (0 to 65535); arithmetic faults when the result leaves the range."},
      {"UInt32", "Unsigned 32-bit whole numbers (0 to 4294967295); arithmetic faults when the result leaves the range."},
      {"UInt64", "Unsigned 64-bit whole numbers (0 to 18446744073709551615); arithmetic faults when the result leaves the range."},
      {"Float32", "Binary32 floating-point values; each operation rounds to binary32, and literals need a Float32 type to adopt it."},
      {"Float64", "Binary64 floating-point values; the same type as Float."},
      {"String", "UTF-8 text addressed by byte offsets; length is bytes, scalar_length counts Unicode scalars, and chars() walks scalars."},
      {"Void", "The single value void, used when an operation returns no useful payload."},
      {"Never", "The return type of computations that cannot return a value, such as panic."},
  };
  for (size_t i = 0; i < sizeof DOCS / sizeof DOCS[0]; i++) {
    if (ms_span_is_text(id, DOCS[i].name)) {
      return ms_span_of_text(DOCS[i].doc);
    }
  }
  return ms_span_of_text("");
}

/* ---- the source files ---- */

static void classify_file(StdFile *file) {
  bool native = false;
  bool body = false;
  for (uint32_t d = 0; d < file->tree.ndecls; d++) {
    const MsDecl *decl = file->tree.decls[d];
    body = body || ms_decl_has_body(decl);
    if (decl->kind == MS_D_IMPL && decl->u.impl.contract == NULL) {
      for (uint32_t i = 0; i < decl->u.impl.methods.len; i++) {
        native = native || decl->u.impl.methods.ptr[i]->func.body.len == 0;
        file->inherent_body = file->inherent_body || decl->u.impl.methods.ptr[i]->func.body.len > 0;
      }
    }
  }
  file->mixed = native && body;
}

static void load_files(Guide *g) {
  size_t count = 0;
  const MsStdSource *sources = ms_std_sources(&count);
  g->files = MS_ARENA_NEW_ARRAY(g->arena, StdFile, count == 0 ? 1 : count);
  for (size_t i = 0; i < count; i++) {
    if (ms_span_starts_with(sources[i].name, ms_span_of_text("internal/"))) {
      continue;
    }
    StdFile *file = &g->files[g->nfiles];
    MsDiag diag = {0};
    if (!ms_parse(g->arena, g->names, sources[i].text, &file->tree, &diag)) {
      continue;
    }
    file->path = ms_message_format(g->arena, "@std/%S", sources[i].name, (MsSpan){0});
    file->source = sources[i].text;
    classify_file(file);
    g->nfiles++;
  }
}

static const MsToken *tokens_of(Guide *g, StdFile *file, size_t *count) {
  if (!file->lexed) {
    MsLexed lexed = {0};
    MsDiag diag = {0};
    file->lexed = true;
    if (ms_lex(g->arena, file->source, &lexed, &diag)) {
      file->tokens = lexed.tokens;
      file->ntokens = lexed.ntokens;
    }
  }
  *count = file->ntokens;
  return file->tokens;
}

/* ---- rendering written declarations ---- */

static MsSpan name_text(const Guide *g, MsName name) {
  return ms_names_span(g->names, name);
}

static void type_text(const Guide *g, MsStrBuild *out, const MsTypeRef *t);

static void type_list(const Guide *g, MsStrBuild *out, const MsTypeRefs *list) {
  for (uint32_t i = 0; i < list->len; i++) {
    if (i > 0) {
      ms_strbuild_append_text(out, ", ");
    }
    type_text(g, out, list->ptr[i]);
  }
}

static void type_text(const Guide *g, MsStrBuild *out, const MsTypeRef *t) {
  if (t == NULL) {
    ms_strbuild_append_text(out, "Void");
    return;
  }
  if (t->kind == MS_TYPE_FN) {
    ms_strbuild_append_text(out, "fn(");
    for (uint32_t i = 0; i < t->params.len; i++) {
      const MsParam *p = t->params.ptr[i];
      ms_strbuild_append_text(out, i > 0 ? ", " : "");
      ms_strbuild_append_text(out, p->moving ? "move " : "");
      ms_strbuild_append_text(out, p->is_mutable ? "var " : "");
      if (p->ty != NULL) {
        type_text(g, out, p->ty);
      }
    }
    ms_strbuild_append_text(out, ") ");
    type_text(g, out, t->result);
    return;
  }
  const MsSpan name = name_text(g, t->name);
  if (ms_span_is_text(name, "Optional") && t->args.len == 1) {
    const bool fn = t->args.ptr[0]->kind == MS_TYPE_FN;
    ms_strbuild_append_text(out, fn ? "(" : "");
    type_text(g, out, t->args.ptr[0]);
    ms_strbuild_append_text(out, fn ? ")?" : "?");
    return;
  }
  ms_strbuild_append(out, name);
  if (t->args.len > 0) {
    ms_strbuild_append_byte(out, '[');
    type_list(g, out, &t->args);
    ms_strbuild_append_byte(out, ']');
  }
}

static void type_parameters(const Guide *g, MsStrBuild *out, const MsTypeParams *params) {
  if (params->len == 0) {
    return;
  }
  ms_strbuild_append_byte(out, '[');
  for (uint32_t i = 0; i < params->len; i++) {
    const MsTypeParam *p = params->ptr[i];
    ms_strbuild_append_text(out, i > 0 ? ", " : "");
    ms_strbuild_append(out, name_text(g, p->name));
    for (uint32_t b = 0; b < p->bounds.len; b++) {
      ms_strbuild_append_text(out, b == 0 ? ": " : " & ");
      type_text(g, out, p->bounds.ptr[b]);
    }
    if (p->def != NULL) {
      ms_strbuild_append_text(out, " = ");
      type_text(g, out, p->def);
    }
  }
  ms_strbuild_append_byte(out, ']');
}

static void type_arguments(const Guide *g, MsStrBuild *out, const MsTypeParams *params) {
  if (params->len == 0) {
    return;
  }
  ms_strbuild_append_byte(out, '[');
  for (uint32_t i = 0; i < params->len; i++) {
    ms_strbuild_append_text(out, i > 0 ? ", " : "");
    ms_strbuild_append(out, name_text(g, params->ptr[i]->name));
  }
  ms_strbuild_append_byte(out, ']');
}

static bool is_blank(uint8_t c) {
  return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}

static MsSpan trim_span(MsSpan s) {
  size_t from = 0;
  while (from < s.len && is_blank(s.ptr[from])) {
    from++;
  }
  size_t to = s.len;
  while (to > from && is_blank(s.ptr[to - 1])) {
    to--;
  }
  return ms_span_of(s.ptr + from, to - from);
}

/* A default written as more than a name keeps its source spelling, up to the delimiter that ends the parameter. */
static void default_text(Guide *g, StdFile *file, MsStrBuild *out, const MsParam *p) {
  if (p->def != NULL && p->def->kind == MS_E_NAME) {
    ms_strbuild_append(out, name_text(g, p->def->u.sym));
    return;
  }
  size_t count = 0;
  const MsToken *tokens = file == NULL ? NULL : tokens_of(g, file, &count);
  if (tokens == NULL) {
    ms_strbuild_append_text(out, "...");
    return;
  }
  size_t first = 0;
  while (first < count && tokens[first].pos.offset < p->pos.offset) {
    first++;
  }
  for (size_t i = first; i < count; i++) {
    if (tokens[i].kind != MS_T_Assign) {
      continue;
    }
    if (i + 1 >= count) {
      break;
    }
    const size_t start = tokens[i + 1].pos.offset;
    size_t depth = 0;
    for (size_t j = i + 1; j < count; j++) {
      const uint8_t kind = tokens[j].kind;
      const size_t at = tokens[j].pos.offset;
      if (kind == MS_T_LParen || kind == MS_T_LBracket || kind == MS_T_LBrace) {
        depth++;
      } else if (kind == MS_T_RParen || kind == MS_T_RBracket || kind == MS_T_RBrace) {
        if (depth == 0) {
          ms_strbuild_append(out, trim_span(ms_span_of(file->source.ptr + start, at - start)));
          return;
        }
        depth--;
      } else if ((kind == MS_T_Comma || kind == MS_T_Newline) && depth == 0) {
        ms_strbuild_append(out, trim_span(ms_span_of(file->source.ptr + start, at - start)));
        return;
      }
    }
    break;
  }
  ms_strbuild_append_text(out, "...");
}

static void parameters(Guide *g, StdFile *file, MsStrBuild *out, const MsParams *params) {
  ms_strbuild_append_byte(out, '(');
  for (uint32_t i = 0; i < params->len; i++) {
    const MsParam *p = params->ptr[i];
    ms_strbuild_append_text(out, i > 0 ? ", " : "");
    ms_strbuild_append_text(out, p->moving ? "move " : "");
    ms_strbuild_append_text(out, p->is_mutable ? "var " : "");
    ms_strbuild_append(out, name_text(g, p->name));
    ms_strbuild_append_text(out, ": ");
    if (p->ty != NULL) {
      type_text(g, out, p->ty);
    }
    if (p->def != NULL) {
      ms_strbuild_append_text(out, " = ");
      default_text(g, file, out, p);
    }
  }
  ms_strbuild_append_byte(out, ')');
}

static MsSpan keep(Guide *g, MsStrBuild *out) {
  const MsSpan text = ms_arena_copy(g->arena, ms_strbuild_span(out));
  ms_strbuild_free(out);
  return text;
}

/* `fn name[T](params) Result:`, with `var fn` or `move fn` for a method that changes or consumes its receiver. */
static void fn_declaration(Guide *g, StdFile *file, MsStrBuild *out, MsSpan name, const MsFunc *f, bool mutating,
                           bool consuming) {
  ms_strbuild_append_text(out, mutating ? "var fn " : consuming ? "move fn " : "fn ");
  ms_strbuild_append(out, name);
  type_parameters(g, out, &f->type_params);
  parameters(g, file, out, &f->params);
  ms_strbuild_append_byte(out, ' ');
  type_text(g, out, f->result);
  ms_strbuild_append_text(out, ":\n");
}

/* `fn var Receiver.name(...)` when it changes `self`. */
static void receiver_declaration(Guide *g, StdFile *file, MsStrBuild *out, MsSpan receiver, MsSpan name, const MsFunc *f,
                                 bool mutating, bool consuming) {
  ms_strbuild_append_text(out, "fn ");
  ms_strbuild_append_text(out, mutating ? "var " : consuming ? "move " : "");
  ms_strbuild_append(out, receiver);
  ms_strbuild_append_byte(out, '.');
  ms_strbuild_append(out, name);
  type_parameters(g, out, &f->type_params);
  parameters(g, file, out, &f->params);
  ms_strbuild_append_byte(out, ' ');
  type_text(g, out, f->result);
  ms_strbuild_append_text(out, ":\n");
}

/* ---- symbols ---- */

static bool declared_name(const Guide *g, const MsDecl *decl, MsSpan *name) {
  MsName n = 0;
  switch ((MsDeclKind)decl->kind) {
  case MS_D_FN: n = decl->u.fn.name; break;
  case MS_D_CONST: n = decl->u.konst.name; break;
  case MS_D_TYPE: n = decl->u.type.name; break;
  case MS_D_ENUM: n = decl->u.enumeration.name; break;
  case MS_D_ALIAS: n = decl->u.alias.name; break;
  case MS_D_INTERFACE: n = decl->u.iface.name; break;
  case MS_D_IMPL:
  case MS_D_TEST: return false;
  }
  *name = name_text(g, n);
  return true;
}

static bool is_type_decl(const MsDecl *decl) {
  return decl->kind == MS_D_TYPE || decl->kind == MS_D_ENUM || decl->kind == MS_D_INTERFACE || decl->kind == MS_D_ALIAS;
}

static Symbol *find_symbol(const Guide *g, const StdFile *file, MsSpan name, bool types_only) {
  for (size_t i = 0; i < g->symbols.len; i++) {
    Symbol *s = g->symbols.ptr[i];
    if (s->file == file && ms_span_equal(s->name, name) && (!types_only || s->decl == NULL || is_type_decl(s->decl))) {
      return s;
    }
  }
  return NULL;
}

static StdFile *find_file(const Guide *g, MsSpan path) {
  for (size_t i = 0; i < g->nfiles; i++) {
    if (ms_span_equal(g->files[i].path, path)) {
      return &g->files[i];
    }
  }
  return NULL;
}

/* The type a receiver names: declared in the file, imported by it, a primitive, or a prelude type. */
static Symbol *resolve_receiver(const Guide *g, const StdFile *file, MsSpan name) {
  Symbol *own = find_symbol(g, file, name, true);
  if (own != NULL) {
    return own;
  }
  for (uint32_t i = 0; i < file->tree.nimports; i++) {
    if (ms_span_equal(name_text(g, file->tree.imports[i].name), name)) {
      const StdFile *target = find_file(g, file->tree.imports[i].path);
      Symbol *found = target == NULL ? NULL : find_symbol(g, target, name, true);
      if (found != NULL) {
        return found;
      }
    }
  }
  Symbol *primitive = find_symbol(g, NULL, name, true);
  if (primitive != NULL) {
    return primitive;
  }
  for (size_t i = 0; i < MS_PRELUDE_TYPE_COUNT; i++) {
    if (ms_span_is_text(name, MS_PRELUDE_TYPES[i])) {
      for (size_t f = 0; f < g->nfiles; f++) {
        Symbol *found = find_symbol(g, &g->files[f], name, true);
        if (found != NULL && found->decl->is_exported) {
          return found;
        }
      }
    }
  }
  return NULL;
}

static void collect_symbols(Guide *g) {
  for (size_t p = 0; p < MS_PRIMITIVE_TYPE_COUNT; p++) {
    Symbol *s = MS_ARENA_NEW(g->arena, Symbol);
    s->name = ms_span_of_text(MS_PRIMITIVE_TYPES[p]);
    symbols_push(g->arena, &g->symbols, s);
  }
  for (size_t f = 0; f < g->nfiles; f++) {
    const StdFile *file = &g->files[f];
    for (uint32_t d = 0; d < file->tree.ndecls; d++) {
      MsSpan name = {0};
      if (!declared_name(g, file->tree.decls[d], &name)) {
        continue;
      }
      Symbol *s = MS_ARENA_NEW(g->arena, Symbol);
      s->file = file;
      s->decl = file->tree.decls[d];
      s->name = name;
      symbols_push(g->arena, &g->symbols, s);
    }
  }
}

/* Files the methods of each `impl`: a bodiless inherent method is part of its type's declaration, any other is an
 * implementation of the type it names. */
static void collect_methods(Guide *g) {
  for (size_t f = 0; f < g->nfiles; f++) {
    const StdFile *file = &g->files[f];
    for (uint32_t d = 0; d < file->tree.ndecls; d++) {
      const MsDecl *decl = file->tree.decls[d];
      if (decl->kind != MS_D_IMPL) {
        continue;
      }
      Symbol *receiver = resolve_receiver(g, file, name_text(g, decl->u.impl.receiver->name));
      if (receiver == NULL) {
        continue;
      }
      for (uint32_t m = 0; m < decl->u.impl.methods.len; m++) {
        const MsMethod *method = decl->u.impl.methods.ptr[m];
        const bool inherent = decl->u.impl.contract == NULL;
        const bool bodiless = method->func.body.len == 0;
        const bool folds = inherent && receiver->file == file &&
                           (file->mixed ? bodiless : !file->inherent_body);
        method_refs_push(g->arena, folds ? &receiver->folded : &receiver->implemented,
                         (MethodRef){.impl = decl, .method = method, .file = file});
      }
    }
  }
}

/* ---- documenting one symbol ---- */

static int64_t compare_members(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const MsApiMember *x = (const MsApiMember *)(const void *)a;
  const MsApiMember *y = (const MsApiMember *)(const void *)b;
  const MsSpan xs[] = {x->kind, x->name, x->contract};
  const MsSpan ys[] = {y->kind, y->name, y->contract};
  for (size_t i = 0; i < 3; i++) {
    const size_t n = xs[i].len < ys[i].len ? xs[i].len : ys[i].len;
    for (size_t k = 0; k < n; k++) {
      if (xs[i].ptr[k] != ys[i].ptr[k]) {
        return (int64_t)xs[i].ptr[k] - (int64_t)ys[i].ptr[k];
      }
    }
    if (xs[i].len != ys[i].len) {
      return xs[i].len < ys[i].len ? -1 : 1;
    }
  }
  return 0;
}

static void sort_members(MsApiMembers *members) {
  if (members->len > 1) {
    ms_sort((uint8_t *)members->ptr, members->len, sizeof(MsApiMember), compare_members, NULL);
  }
}

static MsSpan comment_at(Guide *g, const StdFile *file, uint32_t offset) {
  return ms_leading_comment(g->arena, file->source, offset);
}

/* `name[U, K: Hashable]`: an operation's own type parameters follow its name. */
static MsSpan operation_name(Guide *g, const MsMethod *method) {
  MsStrBuild out = ms_strbuild_new();
  ms_strbuild_append(&out, name_text(g, method->func.name));
  const MsTypeParams *params = &method->func.type_params;
  if (params->len > 0) {
    ms_strbuild_append_byte(&out, '[');
    for (uint32_t i = 0; i < params->len; i++) {
      ms_strbuild_append_text(&out, i > 0 ? ", " : "");
      ms_strbuild_append(&out, name_text(g, params->ptr[i]->name));
      for (uint32_t b = 0; b < params->ptr[i]->bounds.len; b++) {
        ms_strbuild_append_text(&out, b == 0 ? ": " : " & ");
        type_text(g, &out, params->ptr[i]->bounds.ptr[b]);
      }
    }
    ms_strbuild_append_byte(&out, ']');
  }
  return keep(g, &out);
}

static MsSpan field_signature(Guide *g, StdFile *file, const MsParam *field, bool with_default) {
  MsStrBuild out = ms_strbuild_new();
  ms_strbuild_append(&out, name_text(g, field->name));
  ms_strbuild_append_text(&out, ": ");
  if (field->ty != NULL) {
    type_text(g, &out, field->ty);
  }
  if (with_default && field->def != NULL) {
    ms_strbuild_append_text(&out, " = ");
    default_text(g, file, &out, field);
  }
  return keep(g, &out);
}

static void add_member(Guide *g, MsApiMembers *members, MsApiMember member) {
  (void)g;
  ms_api_members_push(g->arena, members, member);
}

static MsSpan strip_colon(MsSpan s) {
  return s.len > 0 && s.ptr[s.len - 1] == ':' ? ms_span_of(s.ptr, s.len - 1) : s;
}

/* Member of a method written inside the declaration (an interface operation or a folded inherent method). */
static void method_member(Guide *g, Symbol *symbol, MsApiMembers *members, const MsMethod *method, StdFile *file,
                          bool interface) {
  MsStrBuild sig = ms_strbuild_new();
  fn_declaration(g, file, &sig, name_text(g, method->func.name), &method->func, method->mutating, method->consuming);
  MsSpan signature = trim_span(ms_strbuild_span(&sig));
  if (interface) {
    signature = strip_colon(signature);
  }
  signature = ms_arena_copy(g->arena, signature);
  ms_strbuild_free(&sig);
  add_member(g, members, (MsApiMember){.name = operation_name(g, method), .kind = ms_span_of_text("operation"),
                                       .signature = signature, .doc = comment_at(g, file, method->pos.offset)});
  (void)symbol;
}

static bool symbol_opaque(const Symbol *s) {
  if (s->decl == NULL) {
    return false;
  }
  return (s->decl->kind == MS_D_TYPE && s->decl->u.type.opaque) || (s->decl->kind == MS_D_ENUM && s->decl->u.enumeration.opaque);
}

/* Whether the receiver is the declaration's own type: its arguments are the declared type variables, in order. A
 * primitive has none. */
static bool receiver_is_declaration(const Symbol *symbol, const MsTypeRef *receiver) {
  const MsTypeParams params = symbol->decl == NULL ? (MsTypeParams){0} : ms_check_decl_type_params(symbol->decl);
  if (receiver->args.len != params.len) {
    return false;
  }
  for (uint32_t i = 0; i < params.len; i++) {
    const MsTypeRef *arg = receiver->args.ptr[i];
    if (arg->kind != MS_TYPE_NAMED || arg->args.len != 0 || arg->name != params.ptr[i]->name) {
      return false;
    }
  }
  return true;
}

static MsSpan receiver_context(Guide *g, const Symbol *symbol, const MethodRef *m) {
  const MsDecl *impl = m->impl;
  MsStrBuild bounds = ms_strbuild_new();
  size_t count = 0;
  for (uint32_t i = 0; i < impl->u.impl.bounds.len; i++) {
    const MsTypeParam *p = impl->u.impl.bounds.ptr[i];
    if (p->bounds.len == 0) {
      continue;
    }
    ms_strbuild_append_text(&bounds, count++ > 0 ? ", " : "");
    ms_strbuild_append(&bounds, name_text(g, p->name));
    for (uint32_t b = 0; b < p->bounds.len; b++) {
      ms_strbuild_append_text(&bounds, b == 0 ? ": " : " & ");
      type_text(g, &bounds, p->bounds.ptr[b]);
    }
  }
  if (count == 0 && receiver_is_declaration(symbol, impl->u.impl.receiver)) {
    ms_strbuild_free(&bounds);
    return ms_span_of_text("");
  }
  MsStrBuild out = ms_strbuild_new();
  ms_strbuild_append_text(&out, "// Receiver: ");
  type_text(g, &out, impl->u.impl.receiver);
  if (count > 0) {
    ms_strbuild_append_text(&out, "; ");
    ms_strbuild_append(&out, ms_strbuild_span(&bounds));
  }
  ms_strbuild_append_byte(&out, '\n');
  ms_strbuild_free(&bounds);
  return keep(g, &out);
}

static void implementation_members(Guide *g, Symbol *symbol, MsApiMembers *members) {
  for (size_t i = 0; i < symbol->implemented.len; i++) {
    const MethodRef *m = &symbol->implemented.ptr[i];
    StdFile *file = (StdFile *)(uintptr_t)m->file;
    const MsDecl *impl = m->impl;
    MsSpan contract = ms_span_of_text("");
    if (impl->u.impl.contract != NULL) {
      MsStrBuild text = ms_strbuild_new();
      type_text(g, &text, impl->u.impl.contract);
      contract = keep(g, &text);
    }
    const MsSpan context = receiver_context(g, symbol, m);
    MsStrBuild sig = ms_strbuild_new();
    ms_strbuild_append(&sig, context);
    fn_declaration(g, file, &sig, name_text(g, m->method->func.name), &m->method->func, m->method->mutating,
                   m->method->consuming);
    const MsSpan signature = ms_arena_copy(g->arena, trim_span(ms_strbuild_span(&sig)));
    ms_strbuild_free(&sig);
    add_member(g, members, (MsApiMember){.name = name_text(g, m->method->func.name), .kind = ms_span_of_text("operation"),
                                         .signature = signature, .doc = comment_at(g, file, m->method->pos.offset),
                                         .contract = contract});
  }
}

static const char *kind_of(const Symbol *s) {
  if (s->decl == NULL) {
    return "type";
  }
  switch ((MsDeclKind)s->decl->kind) {
  case MS_D_FN: return "fn";
  case MS_D_CONST: return "constant";
  case MS_D_TYPE: {
    const bool native = s->decl->u.type.external || ms_span_is_text(s->name, "List");
    return native ? "native" : "type";
  }
  case MS_D_ENUM: return "alternative";
  case MS_D_INTERFACE: return "interface";
  case MS_D_ALIAS: return "alias";
  case MS_D_IMPL:
  case MS_D_TEST: break;
  }
  return "type";
}

/* `type Name:` with its fields, cases and methods, bodies left out. */
static MsSpan declaration_text(Guide *g, Symbol *s, StdFile *file, bool opaque) {
  MsStrBuild b = ms_strbuild_new();
  const MsDecl *decl = s->decl;
  if (decl == NULL) {
    ms_strbuild_append_text(&b, "type ");
    ms_strbuild_append(&b, s->name);
    ms_strbuild_append_text(&b, ":\n");
    return keep(g, &b);
  }
  if (decl->kind == MS_D_FN) {
    fn_declaration(g, file, &b, s->name, &decl->u.fn, false, false);
    return keep(g, &b);
  }
  if (decl->kind == MS_D_CONST) {
    ms_strbuild_append(&b, s->name);
    ms_strbuild_append_text(&b, ": ");
    const MsExpr *value = decl->u.konst.value;
    if (decl->u.konst.ty != NULL) {
      type_text(g, &b, decl->u.konst.ty);
    } else if (value != NULL && value->kind == MS_E_TEXT) {
      ms_strbuild_append_text(&b, "String");
    } else if (value != NULL && value->kind == MS_E_BOOL) {
      ms_strbuild_append_text(&b, "Bool");
    }
    ms_strbuild_append_byte(&b, '\n');
    return keep(g, &b);
  }
  const char *keyword = decl->kind == MS_D_ENUM ? "enum" : decl->kind == MS_D_INTERFACE ? "interface" : "type";
  MsTypeParams tps = {0};
  const MsParams *fields = NULL;
  if (decl->kind == MS_D_TYPE) {
    tps = decl->u.type.type_params;
    fields = &decl->u.type.fields;
  } else if (decl->kind == MS_D_ENUM) {
    tps = decl->u.enumeration.type_params;
  } else if (decl->kind == MS_D_INTERFACE) {
    tps = decl->u.iface.type_params;
  } else {
    tps = decl->u.alias.type_params;
  }
  ms_strbuild_append_text(&b, opaque ? "opaque " : "");
  ms_strbuild_append_text(&b, keyword);
  ms_strbuild_append_byte(&b, ' ');
  ms_strbuild_append(&b, s->name);
  type_parameters(g, &b, &tps);
  ms_strbuild_append_text(&b, ":\n");
  if (fields != NULL && !opaque) {
    for (uint32_t i = 0; i < fields->len; i++) {
      ms_strbuild_append_text(&b, "    ");
      ms_strbuild_append(&b, field_signature(g, file, fields->ptr[i], true));
      ms_strbuild_append_byte(&b, '\n');
    }
  }
  if (decl->kind == MS_D_ENUM && !opaque) {
    for (uint32_t i = 0; i < decl->u.enumeration.cases.len; i++) {
      const MsCase *c = decl->u.enumeration.cases.ptr[i];
      ms_strbuild_append_text(&b, "    ");
      ms_strbuild_append(&b, name_text(g, c->name));
      if (c->fields.len > 0) {
        parameters(g, file, &b, &c->fields);
      }
      ms_strbuild_append_byte(&b, '\n');
    }
  }
  MsStrBuild receiver = ms_strbuild_new();
  ms_strbuild_append(&receiver, s->name);
  type_arguments(g, &receiver, &tps);
  const MsSpan receiver_text = ms_strbuild_span(&receiver);
  const bool interface = decl->kind == MS_D_INTERFACE;
  const size_t methods = interface ? decl->u.iface.methods.len : s->folded.len;
  if ((decl->kind == MS_D_TYPE || decl->kind == MS_D_ENUM) && methods > 0) {
    ms_strbuild_append_byte(&b, '\n');
  }
  if (interface) {
    for (uint32_t i = 0; i < decl->u.iface.methods.len; i++) {
      const MsMethod *m = decl->u.iface.methods.ptr[i];
      MsStrBuild header = ms_strbuild_new();
      fn_declaration(g, file, &header, name_text(g, m->func.name), &m->func, m->mutating, m->consuming);
      ms_strbuild_append_text(&b, "    ");
      ms_strbuild_append(&b, strip_colon(trim_span(ms_strbuild_span(&header))));
      ms_strbuild_append_byte(&b, '\n');
      ms_strbuild_free(&header);
    }
  } else {
    for (size_t i = 0; i < s->folded.len; i++) {
      const MsMethod *m = s->folded.ptr[i].method;
      receiver_declaration(g, file, &b, receiver_text, name_text(g, m->func.name), &m->func, m->mutating, m->consuming);
    }
  }
  ms_strbuild_free(&receiver);
  return keep(g, &b);
}

static void document_symbol(Guide *g, Symbol *s) {
  if (s->built) {
    return;
  }
  s->built = true;
  StdFile *file = (StdFile *)(uintptr_t)s->file;
  MsApiDecl *d = &s->api;
  d->name = s->name;
  d->kind = ms_span_of_text(kind_of(s));
  d->opaque = symbol_opaque(s);
  if (s->decl == NULL) {
    d->doc = primitive_documentation(s->name);
  } else {
    d->doc = comment_at(g, file, s->decl->pos.offset);
    ms_declared_effects(g->arena, file->source, s->decl->pos.offset, &d->effects);
  }
  d->declaration = declaration_text(g, s, file, d->opaque);
  if (s->decl != NULL && s->decl->kind == MS_D_CONST) {
    return;
  }
  const MsDecl *decl = s->decl;
  if (decl != NULL && decl->kind == MS_D_TYPE && !d->opaque) {
    for (uint32_t i = 0; i < decl->u.type.fields.len; i++) {
      const MsParam *field = decl->u.type.fields.ptr[i];
      add_member(g, &d->members, (MsApiMember){.name = name_text(g, field->name), .kind = ms_span_of_text("field"),
                                               .signature = field_signature(g, file, field, true),
                                               .doc = comment_at(g, file, field->pos.offset)});
    }
  }
  if (decl != NULL && decl->kind == MS_D_ENUM && !d->opaque) {
    for (uint32_t i = 0; i < decl->u.enumeration.cases.len; i++) {
      const MsCase *c = decl->u.enumeration.cases.ptr[i];
      MsStrBuild sig = ms_strbuild_new();
      ms_strbuild_append(&sig, name_text(g, c->name));
      if (c->fields.len > 0) {
        parameters(g, NULL, &sig, &c->fields);
      }
      add_member(g, &d->members, (MsApiMember){.name = name_text(g, c->name), .kind = ms_span_of_text("case"),
                                               .signature = keep(g, &sig), .doc = comment_at(g, file, c->pos.offset)});
      for (uint32_t k = 0; k < c->fields.len; k++) {
        const MsParam *field = c->fields.ptr[k];
        add_member(g, &d->members,
                   (MsApiMember){.name = ms_message_format(g->arena, "%S.%S", name_text(g, c->name), name_text(g, field->name)),
                                 .kind = ms_span_of_text("field"), .signature = field_signature(g, file, field, false),
                                 .doc = comment_at(g, file, field->pos.offset)});
      }
    }
  }
  if (decl != NULL && decl->kind == MS_D_INTERFACE) {
    for (uint32_t i = 0; i < decl->u.iface.methods.len; i++) {
      method_member(g, s, &d->members, decl->u.iface.methods.ptr[i], file, true);
    }
  }
  for (size_t i = 0; i < s->folded.len; i++) {
    method_member(g, s, &d->members, s->folded.ptr[i].method, (StdFile *)(uintptr_t)s->folded.ptr[i].file, false);
  }
  implementation_members(g, s, &d->members);
  sort_members(&d->members);
}

/* ---- the modules ---- */

static bool exported(const Symbol *s) {
  return s->decl != NULL && s->decl->is_exported;
}

static int64_t compare_decls(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const MsApiDecl *x = (const MsApiDecl *)(const void *)a;
  const MsApiDecl *y = (const MsApiDecl *)(const void *)b;
  const size_t n = x->name.len < y->name.len ? x->name.len : y->name.len;
  for (size_t k = 0; k < n; k++) {
    if (x->name.ptr[k] != y->name.ptr[k]) {
      return (int64_t)x->name.ptr[k] - (int64_t)y->name.ptr[k];
    }
  }
  return (int64_t)x->name.len - (int64_t)y->name.len;
}

static int64_t compare_modules(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const MsApiModule *x = (const MsApiModule *)(const void *)a;
  const MsApiModule *y = (const MsApiModule *)(const void *)b;
  const bool xp = ms_span_is_text(x->path, "prelude");
  const bool yp = ms_span_is_text(y->path, "prelude");
  if (xp != yp) {
    return xp ? -1 : 1;
  }
  const size_t n = x->path.len < y->path.len ? x->path.len : y->path.len;
  for (size_t k = 0; k < n; k++) {
    if (x->path.ptr[k] != y->path.ptr[k]) {
      return (int64_t)x->path.ptr[k] - (int64_t)y->path.ptr[k];
    }
  }
  return (int64_t)x->path.len - (int64_t)y->path.len;
}

void ms_guide_build(MsArena *arena, MsNames *names, MsGuide *out) {
  Guide g = {.arena = arena, .names = names};
  load_files(&g);
  collect_symbols(&g);
  collect_methods(&g);
  MsApiModule *modules = MS_ARENA_NEW_ARRAY(arena, MsApiModule, g.nfiles + 1);
  size_t count = 0;
  for (size_t f = 0; f < g.nfiles; f++) {
    MsApiModule *module = &modules[count];
    module->path = g.files[f].path;
    for (size_t i = 0; i < g.symbols.len; i++) {
      Symbol *s = g.symbols.ptr[i];
      if (s->file == &g.files[f] && exported(s)) {
        document_symbol(&g, s);
        ms_api_decls_push(arena, &module->decls, s->api);
      }
    }
    if (module->decls.len > 0) {
      ms_sort((uint8_t *)module->decls.ptr, module->decls.len, sizeof(MsApiDecl), compare_decls, NULL);
      count++;
    }
  }
  MsApiModule *prelude = &modules[count];
  prelude->path = ms_span_of_text("prelude");
  for (size_t p = 0; p < MS_PRIMITIVE_TYPE_COUNT; p++) {
    Symbol *s = find_symbol(&g, NULL, ms_span_of_text(MS_PRIMITIVE_TYPES[p]), true);
    document_symbol(&g, s);
    ms_api_decls_push(arena, &prelude->decls, s->api);
  }
  for (size_t p = 0; p < MS_PRELUDE_TYPE_COUNT; p++) {
    for (size_t f = 0; f < g.nfiles; f++) {
      Symbol *s = find_symbol(&g, &g.files[f], ms_span_of_text(MS_PRELUDE_TYPES[p]), true);
      if (s != NULL && exported(s)) {
        document_symbol(&g, s);
        ms_api_decls_push(arena, &prelude->decls, s->api);
        break;
      }
    }
  }
  ms_sort((uint8_t *)prelude->decls.ptr, prelude->decls.len, sizeof(MsApiDecl), compare_decls, NULL);
  count++;
  ms_sort((uint8_t *)modules, count, sizeof(MsApiModule), compare_modules, NULL);
  out->modules = modules;
  out->count = count;
}
