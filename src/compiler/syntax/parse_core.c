/* Owns the parser state helpers: failures, token access, scratch lists, token descriptions and node
 * construction. */
#include "compiler/syntax/parse_internal.h"

const char PARSE_HIDDEN_ITEM[] = "for item";

static const char IS_HINT[] = "; there is no 'is' operator: write '==' to compare values, or 'match value:' "
                              "to test which alternative a "
                              "value is";

/* ---- failure ---- */

MsDiag *parse_diag(Parser *p, MsPos pos, MsSpan message) {
  *p->diag = (MsDiag){.pos = pos, .message = message};
  return p->diag;
}

Checkpoint parse_checkpoint_take(const Parser *p) {
  return (Checkpoint){
      .scratch = p->scratch->len,
      .bytes = p->bytes->len,
      .depth = p->depth,
      .inline_statement = p->inline_statement,
      .inline_return = p->inline_return,
      .block_lambda = p->block_lambda,
  };
}

/* Restores what the abandoned frames of a failed parse would have restored. A failed parse_enter() leaves its
 * own increment of depth in place. */
void parse_checkpoint_restore(Parser *p, const Checkpoint *c) {
  p->scratch->len = c->scratch;
  p->bytes->len = c->bytes;
  p->inline_statement = c->inline_statement;
  p->inline_return = c->inline_return;
  p->block_lambda = c->block_lambda;
  p->depth = c->depth + (p->enter_failed ? 1 : 0);
  p->enter_failed = false;
}

MsSpan parse_fmt_(Parser *p, const char *format, ...) {
  va_list arguments;
  va_start(arguments, format);
  MsSpan message = ms_message_vformat(p->arena, format, arguments);
  va_end(arguments);
  return message;
}

MsToken parse_peek(const Parser *p) {
  return p->tokens[p->at];
}

MsTok parse_kind(const Parser *p) {
  return (MsTok)p->tokens[p->at].kind;
}

/* Token n ahead of the current one, clamped to the final Eof. */
MsToken parse_ahead(const Parser *p, size_t n) {
  size_t index = p->at + n;
  return p->tokens[index < p->ntokens ? index : p->ntokens - 1];
}

MsToken parse_previous(const Parser *p) {
  return p->tokens[p->at - 1];
}

MsSpan parse_text(const Parser *p, MsToken t) {
  return ms_span_of(p->source.ptr + t.lo, t.hi - t.lo);
}

bool parse_text_is(const Parser *p, MsToken t, const char *word) {
  return ms_span_is_text(parse_text(p, t), word);
}

MsName parse_sym(Parser *p, MsToken t) {
  return ms_names_intern(p->names, parse_text(p, t));
}

MsName parse_intern(Parser *p, const char *text) {
  return ms_names_intern(p->names, ms_span_of_text(text));
}

bool parse_take(Parser *p, MsTok k) {
  if (parse_kind(p) == k) {
    p->at++;
    return true;
  }
  return false;
}

MsToken parse_next(Parser *p) {
  MsToken t = parse_peek(p);
  p->at++;
  return t;
}

uint32_t parse_new_id(Parser *p) {
  return p->next_id++;
}

/* ---- scratch lists ---- */

size_t parse_mark(Parser *p) {
  return p->scratch->len;
}

void parse_push(Parser *p, const void *item, size_t size) {
  __builtin_memcpy(scratch_list_extend(p->scratch, size), item, size);
}

void parse_push_ptr(Parser *p, const void *ptr) {
  parse_push(p, &ptr, sizeof ptr);
}

/* Copies the items pushed since `m` into the arena and drops them from the scratch stack. */
void *parse_finish(Parser *p, size_t m, uint32_t *len, size_t size, size_t align) {
  size_t bytes = p->scratch->len - m;
  *len = (uint32_t)(bytes / size);
  void *out = ms_arena_alloc(p->arena, bytes ? bytes : 1, align);
  if (bytes != 0) {
    __builtin_memcpy(out, p->scratch->ptr + m, bytes);
  }
  p->scratch->len = m;
  return out;
}

/* ---- the shared byte stack ---- */

void parse_bytes_append(Parser *p, MsSpan text) {
  if (text.len != 0) {
    __builtin_memcpy(scratch_list_extend(p->bytes, text.len), text.ptr, text.len);
  }
}

void parse_bytes_byte(Parser *p, uint8_t byte) {
  scratch_list_push(p->bytes, byte);
}

/* The bytes pushed since `mark`; valid until the next push. */
MsSpan parse_bytes_since(const Parser *p, size_t mark) {
  return ms_span_of(p->bytes->ptr + mark, p->bytes->len - mark);
}

/* Moves the bytes pushed since `mark` into the arena and drops them from the stack. */
MsSpan parse_bytes_take(Parser *p, size_t mark) {
  MsSpan text = ms_arena_copy(p->arena, parse_bytes_since(p, mark));
  p->bytes->len = mark;
  return text;
}

/* The name `prefix` followed by the decimal `number`. */
MsName parse_numbered_name(Parser *p, const char *prefix, uint32_t number) {
  return ms_names_intern(p->names, ms_message_format(p->arena, "%s%u", prefix, number));
}

/* ---- describing tokens ---- */

MsSpan parse_describe(Parser *p, MsToken t) {
  MsSpan s = parse_text(p, t);
  switch (t.kind) {
  case MS_T_Newline:
    return ms_span_of_text("end of line");
  case MS_T_Indent:
    return ms_span_of_text("an unexpected indented block");
  case MS_T_Dedent:
    return ms_span_of_text("the end of the block");
  case MS_T_Eof:
    return ms_span_of_text("end of file");
  case MS_T_Name:
    return parse_fmt(p, "name '%S'", s);
  case MS_T_Number:
    return parse_fmt(p, "number %S", s);
  case MS_T_String:
    return parse_fmt(p, "text %S", s);
  default:
    return parse_fmt(p, "'%s'", ms_tok_str((MsTok)t.kind));
  }
}

static MsSpan describe_kind(Parser *p, MsTok k) {
  switch (k) {
  case MS_T_Newline:
    return ms_span_of_text("end of line");
  case MS_T_Indent:
    return ms_span_of_text("an indented block");
  case MS_T_Dedent:
    return ms_span_of_text("the end of the block");
  case MS_T_Eof:
    return ms_span_of_text("end of file");
  case MS_T_Name:
    return ms_span_of_text("a name");
  case MS_T_Number:
    return ms_span_of_text("a number");
  case MS_T_String:
    return ms_span_of_text("text in double quotes");
  default:
    return parse_fmt(p, "'%s'", ms_tok_str(k));
  }
}

static bool kind_is(const char *kind, const char *spelling) {
  return ms_span_is_text(ms_span_of_text(kind), spelling);
}

/* The hint for a name expected where `found` stands. */
static MsSpan need_name_hint(Parser *p, MsToken found) {
  MsSpan found_text = parse_text(p, found);
  MsTok fk = (MsTok)found.kind;
  if (fk == MS_T_SelfKw) {
    return ms_span_of_text("; 'self' is reserved: a method's receiver is implicit, so leave it out of the "
                           "parameter list and write self.field in the body");
  }
  if (fk == MS_T_LParen) {
    return ms_span_of_text("; give it a name, e.g. fn add(a: Int, b: Int) Int:");
  }
  if (ms_span_is_text(found_text, "_")) {
    return ms_span_of_text("; '_' is a reserved word and cannot be used as a name: loops, parameters and "
                           "bindings need a real name such as item, unused or ignored");
  }
  const char *fs = ms_tok_str(fk);
  if (ms_span_is_text(found_text, fs) && found_text.len > 0 &&
      ((found_text.ptr[0] >= 'a' && found_text.ptr[0] <= 'z') ||
       (found_text.ptr[0] >= 'A' && found_text.ptr[0] <= 'Z'))) {
    return parse_fmt(p, "; '%S' is a reserved word and cannot be used as a name", found_text);
  }
  return ms_span_of_text("");
}

/* The expected-token hint; `kind` is the expected kind's spelling. */
static MsSpan need_hint(Parser *p, const char *kd, MsToken found) {
  MsSpan found_text = parse_text(p, found);
  MsTok fk = (MsTok)found.kind;
  if (kind_is(kd, ":")) {
    if (fk == MS_T_Name && ms_span_is_text(found_text, "is")) {
      return ms_span_of_text(IS_HINT);
    }
    return ms_span_of_text("; block headers (fn, if, else, for, while, match, type, enum, interface, test) end "
                           "with ':' before their indented body");
  }
  if (kind_is(kd, ")"))
    return ms_span_of_text("; close the parenthesis, separating items with commas");
  if (kind_is(kd, "]")) {
    if (fk == MS_T_For) {
      return ms_span_of_text("; there are no comprehensions: build the list with map and filter, e.g. "
                             "items.filter(fn x: x > 0).map(fn x: x * 2)");
    }
    return ms_span_of_text("; close the bracket, separating items with commas");
  }
  if (kind_is(kd, "}"))
    return ms_span_of_text("; close the brace, separating items with commas");
  if (kind_is(kd, "(")) {
    if (fk == MS_T_Lt) {
      return ms_span_of_text("; type parameters use square brackets, e.g. fn identity[T](value: T) T:");
    }
    return ms_span_of_text("; a call or parameter list starts with '('");
  }
  if (kind_is(kd, "from")) {
    if (fk == MS_T_Comma) {
      return ms_span_of_text("; to import several names, write import a, b from \"path.ms\", or import (a "
                             "from \"a.ms\", b from \"b.ms\") for several modules");
    }
    return ms_span_of_text("; imports read: import name from \"path.ms\"");
  }
  if (kind_is(kd, "in"))
    return ms_span_of_text("; loops read: for item in items:");
  if (kind_is(kd, "=") && fk == MS_T_Newline) {
    return ms_span_of_text("; every binding needs an initial value, e.g. var count: Int = 0");
  }
  if (kind_is(kd, ":=") && fk == MS_T_Newline) {
    return ms_span_of_text("; a binding needs a value: write name := value, or name: Type := value; closure "
                           "parameters with a type go in parentheses, as in fn(n: Int): n + 1");
  }
  if (kind_is(kd, "NAME")) {
    return need_name_hint(p, found);
  }
  if (kind_is(kd, "NEWLINE"))
    return ms_span_of_text("; end the statement with a line break");
  if (kind_is(kd, "INDENT"))
    return ms_span_of_text("; indent the block body by four spaces under its header");
  return ms_span_of_text("");
}

/* ---- failures ---- */

void parse_fail(Parser *p, MsToken t, MsSpan message) {
  MsDiag *d = parse_diag(p, t.pos, message);
  if (t.end.line > 0) {
    d->has_end = true;
    d->end = t.end;
  }
}

/* Fails on `first` with a replacement of the range first.pos..last.end. */
void parse_fail_fix_range(Parser *p, MsToken first, MsToken last, MsSpan message, MsSpan replacement) {
  MsDiag *d = parse_diag(p, first.pos, message);
  if (last.end.line > 0) {
    d->has_end = true;
    d->end = last.end;
    d->has_fix = true;
    d->fix_pos = first.pos;
    d->fix_end = last.end;
    d->replacement = replacement;
  }
}

void parse_fail_fix(Parser *p, MsToken t, MsSpan message, MsSpan replacement) {
  parse_fail_fix_range(p, t, t, message, replacement);
}

/* A symbolic operator can touch either operand; its word replacement needs separation wherever it
 * would otherwise join an identifier or number. */
void parse_fail_word_operator(Parser *p, MsToken first, MsToken last, MsSpan message, const char *word) {
  MsStrBuild builder = ms_strbuild_new();
  if (first.lo > 0 && ms_ascii_is_ident(p->source.ptr[first.lo - 1])) {
    ms_strbuild_append_byte(&builder, ' ');
  }
  ms_strbuild_append_text(&builder, word);
  if (last.hi < p->source.len && ms_ascii_is_ident(p->source.ptr[last.hi])) {
    ms_strbuild_append_byte(&builder, ' ');
  }
  MsSpan replacement = ms_message_from_builder(p->arena, &builder);
  ms_strbuild_free(&builder);
  parse_fail_fix_range(p, first, last, message, replacement);
}

void parse_and_and(Parser *p, MsToken first) {
  MsToken n = parse_ahead(p, 1);
  MsToken last = (n.kind == MS_T_Amp && n.pos.offset == first.end.offset) ? n : first;
  parse_fail_word_operator(p, first, last,
                           ms_span_of_text("'&&' is not an operator; write 'and' for logical and"), "and");
}

MS_NODISCARD bool parse_need_token(Parser *p, MsTok k, MsToken *out) {
  MsToken t = parse_peek(p);
  if (t.kind == k) {
    p->at++;
    *out = t;
    return true;
  }
  if (p->speculative > 0) {
    return false;
  }
  if (k == MS_T_Colon && t.kind == MS_T_LBrace) {
    MsDiag *d = parse_diag(
        p, t.pos,
        ms_span_of_text("expected ':', found '{'; blocks are not braced: end the header with ':', indent the "
                        "body four spaces on the following lines, and remove the closing '}'"));
    /* The colon attaches to the header, so the edit also takes the spaces before the brace. */
    MsPos start = t.pos;
    if (p->at > 0) {
      MsPos e = p->tokens[p->at - 1].end;
      if (e.line == t.pos.line) {
        start = e;
      }
    }
    d->has_end = true;
    d->end = t.end;
    d->has_fix = true;
    d->fix_pos = start;
    d->fix_end = t.end;
    d->replacement = ms_span_of_text(":");
    return false;
  }
  MsSpan hint = need_hint(p, ms_tok_str(k), t);
  MsSpan dk = describe_kind(p, k);
  MsSpan dt = parse_describe(p, t);
  parse_fail(p, t, parse_fmt(p, "expected %S, found %S%S", dk, dt, hint));
  return false;
}

MS_NODISCARD bool parse_need(Parser *p, MsTok k) {
  MsToken ignored = {0};
  return parse_need_token(p, k, &ignored);
}

/* Consumes the contextual word `from` that ends an import's names. */
MS_NODISCARD bool parse_need_from(Parser *p) {
  MsToken t = parse_peek(p);
  if (t.kind == MS_T_Name && parse_text_is(p, t, "from")) {
    p->at++;
    return true;
  }
  MsSpan dt = parse_describe(p, t);
  MsSpan hint = need_hint(p, "from", t);
  parse_fail(p, t, parse_fmt(p, "expected 'from', found %S%S", dt, hint));
  return false;
}

/* A legacy `case` prefix, including the spaces before a following name on the same line. */
bool parse_legacy_case_prefix(const Parser *p, MsToken *out) {
  MsToken prefix = parse_peek(p);
  MsToken nx = parse_ahead(p, 1);
  if (prefix.kind != MS_T_Name || !parse_text_is(p, prefix, "case") || nx.kind != MS_T_Name ||
      prefix.pos.line != nx.pos.line) {
    return false;
  }
  prefix.end = nx.pos;
  prefix.hi = nx.lo;
  *out = prefix;
  return true;
}

void parse_newlines(Parser *p) {
  while (parse_take(p, MS_T_Newline)) {
  }
}

MS_NODISCARD bool parse_link(Parser *p, size_t *links) {
  (*links)++;
  if (*links > MS_MAX_CHAIN) {
    parse_fail(p, parse_peek(p),
               parse_fmt(p, "expression chain exceeds %u operators or accesses; split it into named parts",
                         MS_MAX_CHAIN));
    return false;
  }
  return true;
}

/* Counts one level of nesting; the caller decrements depth when it is done. */
MS_NODISCARD bool parse_enter(Parser *p) {
  p->depth++;
  if (p->depth > MS_MAX_NESTING) {
    p->enter_failed = true;
    if (p->speculative > 0) {
      return false;
    }
    parse_fail(p, parse_peek(p),
               parse_fmt(p,
                         "nesting exceeds %u levels; split the expression, type, or block into named parts",
                         MS_MAX_NESTING));
    return false;
  }
  return true;
}

/* The advice after "expected end of statement" for the token `t` that followed it. */
static const char *end_hint(Parser *p, MsToken t) {
  bool prev_new = p->at > 0 && parse_text_is(p, parse_previous(p), "new");
  MsSpan prev_word = p->at > 0 ? parse_text(p, parse_previous(p)) : ms_span_of_text("");
  const char *hint;
  if (ms_span_is_text(prev_word, "def") && t.kind == MS_T_Name) {
    hint = "; there is no 'def': declare a function with 'fn name(a: Int) Int:'";
  } else if (ms_span_is_text(prev_word, "lambda")) {
    hint = "; there is no 'lambda': write an anonymous function as 'fn x: x + 1'";
  } else if (ms_span_is_text(prev_word, "elif")) {
    hint = "; there is no 'elif': write 'else if <condition>:' for a further branch";
  } else if (t.kind == MS_T_Name && parse_text_is(p, t, "is")) {
    hint = IS_HINT;
  } else if (t.kind == MS_T_Name && prev_new) {
    hint = "; there is no 'new': construct a value by calling the type, Name(field: value)";
  } else if (t.kind == MS_T_If) {
    hint = "; there is no inline conditional expression 'a if c else b': write 'if c: a else: b', or use an "
           "if statement";
  } else if (t.kind == MS_T_Question) {
    hint = "; '?' after a Result call propagates its error, and is not '?\?' or 'c ? a : b': unwrap an "
           "Optional with 'if x := v:' or give it a default with 'v.get_or(default)', chain with 'a?.b', and "
           "write a conditional as 'if c: a else: b'";
  } else if (t.kind == MS_T_Comma) {
    hint = "; commas separate items only inside (), [] or {}: put each field, case, or statement on its own "
           "line";
  } else if (t.kind == MS_T_LBrace) {
    hint = "; '{' does not open a block: end the header with ':' and indent the body (an interface method is "
           "just its signature)";
  } else {
    hint = "; put one statement per line, and join operands with an operator or a comma inside brackets";
  }
  return hint;
}

MS_NODISCARD bool parse_end(Parser *p) {
  if (p->inline_statement) {
    switch (parse_kind(p)) {
    case MS_T_Newline:
    case MS_T_Comma:
    case MS_T_RParen:
    case MS_T_RBracket:
    case MS_T_RBrace:
      return true;
    default:
      break;
    }
    MsToken t = parse_peek(p);
    MsSpan dt = parse_describe(p, t);
    const char *is = (t.kind == MS_T_Name && parse_text_is(p, t, "is")) ? IS_HINT : "";
    parse_fail(p, t,
               parse_fmt(p,
                         "expected end of inline statement, found %S; an inline body holds one simple "
                         "statement; for more statements or an `else`, put the body on indented lines and "
                         "start `else:` on its own line at the `if`'s indentation%s",
                         dt, is));
    return false;
  }
  if (parse_take(p, MS_T_Newline)) {
    parse_newlines(p);
    return true;
  }
  if (p->at > 0 && parse_previous(p).kind == MS_T_Dedent) {
    return true;
  }
  MsToken t = parse_peek(p);
  if (p->block_lambda && t.kind == MS_T_Comma) {
    parse_fail(
        p, t,
        ms_span_of_text(
            "a comma cannot end a statement in an indented function body; to separate enclosing arguments, "
            "put the comma on its own line dedented to the fn header, or group the function in parentheses"));
    return false;
  }
  if (t.kind == MS_T_Amp) {
    parse_and_and(p, t);
    return false;
  }
  if (t.kind == MS_T_Arrow || (t.kind == MS_T_Assign && parse_ahead(p, 1).kind == MS_T_Gt)) {
    parse_fail(p, t,
               ms_span_of_text("there is no arrow function; anonymous functions are written fn x: x + 1"));
    return false;
  }
  const char *hint = end_hint(p, t);
  MsSpan dt = parse_describe(p, t);
  parse_fail(p, t, parse_fmt(p, "expected end of statement, found %S%s", dt, hint));
  return false;
}

MS_NODISCARD bool parse_push_typ(Parser *p) {
  MsTypeRef *element = NULL;
  if (!parse_typ(p, &element))
    return false;
  parse_push_ptr(p, element);
  return true;
}

MS_NODISCARD bool parse_push_named_type(Parser *p) {
  MsTypeRef *element = NULL;
  if (!parse_named_type(p, &element))
    return false;
  parse_push_ptr(p, element);
  return true;
}

MS_NODISCARD bool parse_push_pattern(Parser *p) {
  MsPattern *element = NULL;
  if (!parse_pattern(p, &element))
    return false;
  parse_push_ptr(p, element);
  return true;
}

MS_NODISCARD bool parse_push_expression(Parser *p, int min) {
  MsExpr *element = NULL;
  if (!parse_expression(p, min, &element))
    return false;
  parse_push_ptr(p, element);
  return true;
}

MS_NODISCARD bool parse_push_binding(Parser *p, bool is_mutable, const MsPos *group, MsPos pos) {
  MsStmt *element = NULL;
  if (!parse_binding(p, is_mutable, group, pos, &element))
    return false;
  parse_push_ptr(p, element);
  return true;
}
/* ---- node construction ---- */

/* An expression ending at the previous token. */
MsExpr *parse_mk(Parser *p, MsPos pos, MsExprKind k) {
  MsExpr *e = MS_ARENA_NEW(p->arena, MsExpr);
  e->id = parse_new_id(p);
  e->pos = pos;
  e->end = p->at > 0 ? parse_previous(p).end : pos;
  e->kind = (uint8_t)k;
  return e;
}

MsExpr *parse_mk_name(Parser *p, MsPos pos, MsName name) {
  MsExpr *e = parse_mk(p, pos, MS_E_NAME);
  e->u.sym = name;
  return e;
}

MsExpr *parse_mk_member(Parser *p, MsPos pos, MsExpr *left, MsName name) {
  MsExpr *e = parse_mk(p, pos, MS_E_MEMBER);
  e->u.member.left = left;
  e->u.member.name = name;
  return e;
}

MsExpr *parse_mk_call(Parser *p, MsPos pos, MsExpr *callee, MsArg *args, uint32_t nargs) {
  MsExpr *e = parse_mk(p, pos, MS_E_CALL);
  e->u.call.callee = callee;
  e->u.call.args.ptr = args;
  e->u.call.args.len = nargs;
  return e;
}

MsTypeRef *parse_mk_named_type(Parser *p, MsPos pos, MsName name, MsTypeRefs args) {
  MsTypeRef *t = MS_ARENA_NEW(p->arena, MsTypeRef);
  t->id = parse_new_id(p);
  t->pos = pos;
  t->kind = MS_TYPE_NAMED;
  t->name = name;
  t->args = args;
  return t;
}

MsParam *parse_mk_param(Parser *p, MsPos pos, MsName name, MsTypeRef *ty, MsExpr *def, bool is_mutable,
                        bool moving) {
  MsParam *m = MS_ARENA_NEW(p->arena, MsParam);
  m->id = parse_new_id(p);
  m->pos = pos;
  m->name = name;
  m->ty = ty;
  m->def = def;
  m->is_mutable = is_mutable;
  m->moving = moving;
  return m;
}
