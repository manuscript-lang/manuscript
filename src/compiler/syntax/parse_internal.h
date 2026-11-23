/* syntax/parse_internal.h: the parser state and the functions its files share. Private to the parser. */
#ifndef MS_SYNTAX_PARSE_INTERNAL_H
#define MS_SYNTAX_PARSE_INTERNAL_H

#include <stdarg.h>

#include "base/chars.h"
#include "base/fatal.h"
#include "base/list.h"
#include "base/strbuild.h"
#include "base/utf8.h"
#include "base/message.h"
#include "compiler/syntax/parse.h"

/* Binding power of the operand of a prefix `not` or `try`. */
enum { PREFIX_OPERAND = 3 };
/* Precedence of `..`: above comparisons, below `+` and `-`. */
enum { RANGE_LEVEL = 5 };

MS_LIST_DEFINE(ScratchList, scratch_list, uint8_t)

/* What a speculative parse restores when it fails: the shared scratch stacks and the parser flags that the
 * abandoned frames had changed. Node ids and queued statements are deliberately not restored, so a
 * backtrack consumes ids exactly as the Rust parser does. */
typedef struct Checkpoint {
  size_t scratch, bytes;
  size_t depth;
  bool inline_statement, inline_return, block_lambda;
} Checkpoint;

typedef struct Parser {
  MsArena *arena;
  MsNames *names;
  MsSpan source;
  const MsToken *tokens;
  size_t ntokens;
  size_t at;
  const MsBounds *bounds;
  size_t source_origin;
  bool inline_statement, inline_return, block_lambda;
  bool ellipsis_body; /* the last function suite was `: ...` */
  size_t depth;
  MsStmt **queued;
  uint32_t nqueued;
  uint32_t next_id;
  uint32_t speculative;
  bool enter_failed; /* the last unwind came from a failed parse_enter(), which leaves depth raised */
  uint64_t *type_brackets;
  ScratchList *scratch, *bytes; /* shared with nested parsers */
  MsDiag *diag;
} Parser;

/* The name of the hidden loop variable of `for item`. */
extern const char PARSE_HIDDEN_ITEM[];

typedef struct TextParts {
  MsTextPart *ptr;
  uint32_t len;
} TextParts;

typedef struct Args {
  MsArg *ptr;
  uint32_t len;
} Args;

/* ---- shared by the parser files (each is defined in the file named by its group) ---- */

/* parse_core.c */
void *parse_zalloc(MsArena *a, size_t n, size_t align);
MsDiag *parse_diag(Parser *p, MsPos pos, MsSpan message);
Checkpoint parse_checkpoint_take(const Parser *p);
void parse_checkpoint_restore(Parser *p, const Checkpoint *c);
MsSpan parse_fmt_(Parser *p, const char *format, ...);
#define parse_fmt(p, ...) parse_fmt_((p), MS_FMT_ARGS(__VA_ARGS__))
MsToken parse_peek(const Parser *p);
MsTok parse_kind(const Parser *p);
MsToken parse_ahead(const Parser *p, size_t n);
MsToken parse_previous(const Parser *p);
MsSpan parse_text(const Parser *p, MsToken t);
bool parse_text_is(const Parser *p, MsToken t, const char *w);
MsName parse_sym(Parser *p, MsToken t);
MsName parse_intern(Parser *p, const char *s);
bool parse_take(Parser *p, MsTok k);
MsToken parse_next(Parser *p);
uint32_t parse_new_id(Parser *p);
size_t parse_mark(Parser *p);
void parse_push(Parser *p, const void *item, size_t size);
void parse_push_ptr(Parser *p, const void *ptr);
void *parse_finish(Parser *p, size_t m, uint32_t *len, size_t size, size_t align);
MsSpan parse_describe(Parser *p, MsToken t);
void parse_fail(Parser *p, MsToken t, MsSpan message);
void parse_fail_fix_range(Parser *p, MsToken first, MsToken last, MsSpan message, MsSpan replacement);
void parse_fail_fix(Parser *p, MsToken t, MsSpan message, MsSpan replacement);
void parse_fail_word_operator(Parser *p, MsToken first, MsToken last, MsSpan message, const char *word);
void parse_and_and(Parser *p, MsToken first);
MS_NODISCARD bool parse_need_token(Parser *p, MsTok k, MsToken *out);
MS_NODISCARD bool parse_need(Parser *p, MsTok k);
MS_NODISCARD bool parse_need_from(Parser *p);
bool parse_legacy_case_prefix(const Parser *p, MsToken *out);
void parse_newlines(Parser *p);
MS_NODISCARD bool parse_link(Parser *p, size_t *links);
MS_NODISCARD bool parse_enter(Parser *p);
MS_NODISCARD bool parse_end(Parser *p);
MS_NODISCARD bool parse_push_typ(Parser *p);
MS_NODISCARD bool parse_push_named_type(Parser *p);
MS_NODISCARD bool parse_push_pattern(Parser *p);
MS_NODISCARD bool parse_push_expression(Parser *p, int min);
MS_NODISCARD bool parse_push_binding(Parser *p, bool is_mutable, const MsPos *group, MsPos pos);
MsExpr *parse_mk(Parser *p, MsPos pos, MsExprKind k);
MsExpr *parse_mk_name(Parser *p, MsPos pos, MsName name);
MsExpr *parse_mk_member(Parser *p, MsPos pos, MsExpr *left, MsName name);
MsExpr *parse_mk_call(Parser *p, MsPos pos, MsExpr *callee, MsArg *args, uint32_t nargs);
MsTypeRef *parse_mk_named_type(Parser *p, MsPos pos, MsName name, MsTypeRefs args);
MsParam *parse_mk_param(Parser *p, MsPos pos, MsName name, MsTypeRef *ty, MsExpr *def, bool is_mutable,
                        bool moving);

void parse_bytes_append(Parser *p, MsSpan text);
void parse_bytes_byte(Parser *p, uint8_t byte);
MsSpan parse_bytes_since(const Parser *p, size_t mark);
MsSpan parse_bytes_take(Parser *p, size_t mark);
MsName parse_numbered_name(Parser *p, const char *prefix, uint32_t number);

/* parse_tables.c */
uint64_t *parse_compute_type_brackets(MsArena *a, const MsToken *tokens, size_t n);
bool parse_type_bracket(const Parser *p, size_t at);
bool parse_binary_op(MsTok k, MsBinaryOp *op);
bool parse_arith_op(MsTok k, MsBinaryOp *op);
bool parse_starts_type(MsTok k);
bool parse_foreign_declaration(Parser *p, MsToken t, MsSpan *message, const char **replacement);

/* parse_type.c */
bool parse_take_move(Parser *p, const MsTok *nexts, size_t count);
MS_NODISCARD bool parse_named_type(Parser *p, MsTypeRef **out);
MS_NODISCARD bool parse_type_args(Parser *p, MsTypeRefs *out);
MS_NODISCARD bool parse_move_type(Parser *p, MsTypeRef **out, bool *moves);
MS_NODISCARD bool parse_result_type(Parser *p, MsTypeRef **out, bool *moves);
MS_NODISCARD bool parse_typ(Parser *p, MsTypeRef **out);
MsExpr *parse_implicit_none(Parser *p, const MsTypeRef *t);
MS_NODISCARD bool parse_type_params(Parser *p, MsTypeParams *out);
MS_NODISCARD bool parse_need_name_colon(Parser *p, MsToken name);
MS_NODISCARD bool parse_parameters(Parser *p, bool defaults, bool inferred, MsParams *out);

/* parse_decl_item.c */
MS_NODISCARD bool parse_suite(Parser *p, MsStmts *out);
MS_NODISCARD bool parse_method_signature(Parser *p, MsToken name, bool generics, bool body, bool mutating,
                                         MsPos var_at, MsMethod **out);
MS_NODISCARD bool parse_single_line(Parser *p, MsToken token, const char *what);
bool parse_plain_text(TextParts parts, MsSpan *out);
MsDecl *parse_new_decl(Parser *p, MsPos pos, MsDeclKind k);
MS_NODISCARD bool parse_test_block(Parser *p, bool bench, MsDecl *d);
bool parse_constant_fix(Parser *p, MsToken word, MsToken *first, MsToken *last, MsSpan *replacement);
bool parse_receiver_method_ahead(const Parser *p);
MS_NODISCARD bool parse_constant_value(Parser *p, MsPos *init_pos, MsExpr **out);
MS_NODISCARD bool parse_need_immutable_bind(Parser *p);
MS_NODISCARD bool parse_alias_declaration(Parser *p, MsToken token, MsName name, MsTypeParams tps,
                                          MsDecl **out);
MS_NODISCARD bool parse_empty_declaration(Parser *p, MsToken token, MsName name, MsTypeParams tps,
                                          MsDecl **out);
MS_NODISCARD bool parse_declaration_member(Parser *p, MsToken token, MsName name, MsTypeParams tps);
MS_NODISCARD bool parse_finish_declaration(Parser *p, MsToken token, MsName name, MsTypeParams tps,
                                           void **items, uint32_t count, MsDecl **out);
MS_NODISCARD bool parse_declaration_body_start(Parser *p, MsToken token);

/* parse_decl.c */
MS_NODISCARD bool parse_declaration(Parser *p, MsDecl **out);

/* parse_bind.c */
MS_NODISCARD bool parse_pattern(Parser *p, MsPattern **out);
MsStmt *parse_finish_stmt(Parser *p, const MsStmt *st);
MsStmt *parse_destructure(Parser *p, MsPattern *pat, MsName hidden);
bool parse_binding_ahead(const Parser *p);
MS_NODISCARD bool parse_binding(Parser *p, bool is_mutable, const MsPos *group, MsPos pos, MsStmt **out);
MS_NODISCARD bool parse_binding_group(Parser *p, MsToken keyword, MsStmts *out);
MS_NODISCARD bool parse_statements(Parser *p, bool allow_value);
MsTypeRefs parse_copy_types(Parser *p, MsTypeRefs types);
MsExpr *parse_clone_chain(Parser *p, const MsExpr *e);
MsExpr *parse_index_set(Parser *p, MsPos pos, MsExpr *left, MsExpr *index, MsExpr *value, bool reread);
MS_NODISCARD bool parse_assign_target(Parser *p, MsToken start, MsExpr *e, MsStmt *st);
bool parse_compound_assignment(const Parser *p);
MS_NODISCARD bool parse_compound(Parser *p, MsToken start, MsExpr *e, MsStmt *st);

/* parse_stmt.c */
MS_NODISCARD bool parse_statement(Parser *p, bool allow_value, MsStmt **out);
MS_NODISCARD bool parse_statement_suite(Parser *p, bool is_expression, bool fn_body, MsStmts *out);

/* parse_expr.c */
MsExpr *parse_mk_unary(Parser *p, MsPos pos, MsUnaryOp op, MsExpr *operand);
MS_NODISCARD bool parse_expression(Parser *p, int min, MsExpr **out);
MS_NODISCARD bool parse_if_expression(Parser *p, MsToken t, MsExpr **out);
MS_NODISCARD bool parse_match_arms(Parser *p, MsToken header, MsExpr *m);

/* parse_text.c */
MsSpan parse_dedent(Parser *p, MsSpan content, size_t indent);
MS_NODISCARD bool parse_text_parts_of(Parser *p, MsToken token, TextParts *out);

/* parse_primary.c */
MS_NODISCARD bool parse_bracket(Parser *p, MsExpr *left, MsExpr **out);
MS_NODISCARD bool parse_postfix(Parser *p, MsExpr *e, MsExpr **out);
MS_NODISCARD bool parse_call_arguments(Parser *p, Args *out);
MS_NODISCARD bool parse_primary(Parser *p, MsExpr **out);

#endif
