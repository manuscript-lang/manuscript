/* The untyped syntax tree. Mirrors crates/ms-syntax/src/ast.rs: the same shapes, positions and
 * node ids (dense per module, allocated in the same order). Nodes live in the parse arena and are
 * referenced by pointer; lists are (pointer, length) pairs of node pointers. */
#ifndef MS_SYNTAX_AST_H
#define MS_SYNTAX_AST_H

#include "compiler/syntax/pos.h"

typedef struct MsTypeRef MsTypeRef;
typedef struct MsExpr MsExpr;
typedef struct MsStmt MsStmt;
typedef struct MsParam MsParam;
typedef struct MsPattern MsPattern;

typedef struct {
  MsTypeRef **ptr;
  uint32_t len;
} MsTypeRefs;

typedef struct MsTypeParam {
  uint32_t id;
  MsPos pos;
  MsName name;
  MsTypeRefs bounds;
  MsTypeRef *def; /* default type argument, or NULL */
} MsTypeParam;

typedef struct {
  MsParam **ptr;
  uint32_t len;
} MsParams;
typedef struct {
  MsStmt **ptr;
  uint32_t len;
} MsStmts;
typedef struct {
  MsExpr **ptr;
  uint32_t len;
} MsExprs;
typedef struct {
  MsPattern **ptr;
  uint32_t len;
} MsPatterns;
typedef struct {
  MsTypeParam **ptr;
  uint32_t len;
} MsTypeParams;

/* ---- types ---- */

typedef enum MsTypeKind { MS_TYPE_NAMED, MS_TYPE_FN } MsTypeKind;

struct MsTypeRef {
  uint32_t id;
  MsPos pos;
  uint8_t kind;
  MsName name;       /* named: possibly dotted */
  MsTypeRefs args;   /* named */
  MsParams params;   /* fn */
  MsTypeRef *result; /* fn */
  bool result_moves; /* fn: the result is written `move T`, owned memory handed over */
};

struct MsParam {
  uint32_t id;
  MsPos pos;
  MsName name;
  MsTypeRef *ty; /* NULL only for lambda parameters with inferred types */
  MsExpr *def;   /* default value or NULL */
  bool implied_default; /* `def` is the `null` a `T?` parameter or field gets without a written default */
  bool is_mutable;
  bool moving;
  bool holding; /* `hold x T`: the result keeps using the argument */
};

/* ---- expressions ---- */

typedef enum MsExprKind {
  MS_E_NUMBER,
  MS_E_BOOL,
  MS_E_VOID,
  MS_E_TEXT,
  MS_E_NAME,
  MS_E_MEMBER,
  MS_E_APPLY,
  MS_E_INDEX,
  MS_E_PROBE,
  MS_E_LIST,
  MS_E_MAP,
  MS_E_UNARY,
  MS_E_BINARY,
  MS_E_LAMBDA,
  MS_E_CALL,
  MS_E_MATCH
} MsExprKind;

typedef enum MsUnaryOp { MS_U_NOT, MS_U_NEG, MS_U_PLUS, MS_U_TRY } MsUnaryOp;
typedef enum MsBinaryOp {
  MS_B_OR,
  MS_B_AND,
  MS_B_EQ,
  MS_B_NE,
  MS_B_LT,
  MS_B_GT,
  MS_B_LE,
  MS_B_GE,
  MS_B_ADD,
  MS_B_SUB,
  MS_B_MUL,
  MS_B_DIV,
  MS_B_REM
} MsBinaryOp;

const char *ms_unary_str(MsUnaryOp op);
const char *ms_binary_str(MsBinaryOp op);
int ms_binary_precedence(MsBinaryOp op);

typedef struct MsTextPart {
  MsSpan lit;   /* literal text with escapes decoded; unused when expr is set */
  MsExpr *expr; /* interpolated expression, or NULL for a literal */
} MsTextPart;

typedef struct MsArg {
  MsPos pos;
  bool has_name;
  MsName name;
  MsExpr *value;
} MsArg;

typedef struct MsMapEntry {
  MsExpr *key, *value;
} MsMapEntry;

typedef struct MsArmBinding {
  MsName name;
  MsPos pos;
} MsArmBinding;

typedef struct MsArm {
  uint32_t id;
  MsPos pos;
  MsExpr *path;
  struct {
    MsArmBinding *ptr;
    uint32_t len;
  } bindings;
  MsStmts body;
  MsExpr *value; /* final expression, or NULL (yields Void) */
  bool from_if;
  bool bare;
} MsArm;

struct MsExpr {
  uint32_t id;
  MsPos pos, end;
  uint8_t kind; /* MsExprKind */
  uint8_t op;   /* MsUnaryOp or MsBinaryOp */
  union {
    MsName sym; /* NUMBER (spelling), NAME */
    bool flag;  /* BOOL */
    struct {
      MsTextPart *ptr;
      uint32_t len;
    } text;
    struct {
      MsExpr *left;
      MsName name;
    } member;
    struct {
      MsExpr *left;
      MsTypeRefs types;
      MsExpr *value; /* value reading of a single type argument, or NULL */
    } apply;
    struct {
      MsExpr *left, *right; /* INDEX (left, index), BINARY; PROBE and UNARY use left */
    } bin;
    MsExprs list;
    struct {
      MsMapEntry *ptr;
      uint32_t len;
    } map;
    struct {
      MsParams params;
      MsTypeRef *result;
      bool result_moves;
      MsStmts body;
    } lambda;
    struct {
      MsExpr *callee;
      struct {
        MsArg *ptr;
        uint32_t len;
      } args;
    } call;
    struct {
      MsExpr *scrutinee;
      struct {
        MsArm **ptr;
        uint32_t len;
      } arms;
    } match;
  } u;
};

/* The receiver and index of `left[index]`, however the bracket was parsed: an index, or an
 * application whose one bracket entry also reads as a value (`xs[i]` before name resolution says
 * `xs` is a value). False for any other expression. */
static inline bool ms_expr_index(const MsExpr *e, MsExpr **left, MsExpr **index) {
  if (e->kind == MS_E_INDEX) {
    *left = e->u.bin.left;
    *index = e->u.bin.right;
    return true;
  }
  if (e->kind == MS_E_APPLY && e->u.apply.value != NULL && e->u.apply.types.len == 1) {
    *left = e->u.apply.left;
    *index = e->u.apply.value;
    return true;
  }
  return false;
}

/* ---- patterns and statements ---- */

typedef enum MsPatternKind { MS_P_NAME, MS_P_LIST, MS_P_TYPE } MsPatternKind;

typedef struct MsPatternField {
  MsPos pos;
  MsName name;
  MsPattern *pattern;
} MsPatternField;

struct MsPattern {
  uint32_t id;
  MsPos pos;
  uint8_t kind;
  union {
    MsName name;
    MsPatterns list;
    struct {
      MsPatternField *ptr;
      uint32_t len;
    } fields;
  } u;
};

typedef enum MsStmtKind {
  MS_S_BIND,
  MS_S_ASSIGN,
  MS_S_CALL,
  MS_S_RETURN,
  MS_S_BREAK,
  MS_S_CONTINUE,
  MS_S_IF,
  MS_S_WHILE,
  MS_S_FOR
} MsStmtKind;

struct MsStmt {
  uint32_t id;
  MsPos pos;
  uint8_t kind;
  union {
    struct {
      bool is_mutable;
      MsPattern *pattern;
      MsTypeRef *ty;
      MsExpr *value;
      bool has_group;
      MsPos group;
    } bind;
    struct {
      bool member_target; /* target is a member expression, else the name */
      MsName name;
      MsExpr *target;
      bool has_compound;
      uint8_t compound; /* MsBinaryOp */
      MsExpr *value;
    } assign;
    MsExpr *expr; /* CALL; RETURN (NULL for a bare return) */
    struct {
      MsPattern *binding;
      bool is_mutable;
      MsExpr *cond;
      MsStmts body, else_body;
    } branch;
    struct {
      MsExpr *cond;
      MsStmts body;
    } loop;
    struct {
      MsName name;
      MsExpr *iter;
      MsStmts body;
    } each;
  } u;
};

/* ---- declarations ---- */

typedef struct MsFunc {
  MsName name;
  MsTypeParams type_params;
  MsParams params;
  MsTypeRef *result;
  bool result_moves; /* `fn f() move T`: the result hands over owned memory; an unmarked result borrows */
  MsStmts body;
  bool external;
  bool bodiless; /* declared with the body `...`: the runtime provides it */
  bool deferred; /* the checker set the body aside until a call reaches it (check/lazy_std.c): not a bodiless function */
} MsFunc;

typedef struct MsMethod {
  uint32_t id;
  MsPos pos;
  MsPos var_at;
  MsFunc func;
  bool mutating;
  bool consuming;
  bool holding; /* `fn hold T.m()`: the result keeps using the receiver */
  MsTypeRefs receiver_args;
} MsMethod;

/* The method that holds `func` as its `func` member. */
static inline const MsMethod *ms_method_of_func(const MsFunc *func) {
  /* The members of a method are laid out at their own alignment, so the step back to the method is aligned
   * too. */
  return __builtin_assume_aligned((const char *)func - offsetof(MsMethod, func), _Alignof(MsMethod));
}

typedef struct MsCase {
  uint32_t id;
  MsPos pos;
  MsName name;
  MsParams fields;
} MsCase;

typedef enum MsDeclKind {
  MS_D_FN,
  MS_D_CONST,
  MS_D_TYPE,
  MS_D_ENUM,
  MS_D_ALIAS,
  MS_D_INTERFACE,
  MS_D_IMPL,
  MS_D_TEST
} MsDeclKind;

typedef struct MsDecl {
  uint32_t id;
  MsPos pos;
  bool is_exported;
  bool synthetic;
  uint8_t kind;
  union {
    MsFunc fn;
    struct {
      MsName name;
      MsTypeRef *ty;
      MsExpr *value;
      MsPos init_pos;
    } konst;
    struct {
      MsName name;
      MsTypeParams type_params;
      MsParams fields;
      bool external, opaque;
    } type;
    struct {
      MsName name;
      MsTypeParams type_params;
      struct {
        MsCase **ptr;
        uint32_t len;
      } cases;
      bool opaque;
    } enumeration;
    struct {
      MsName name;
      MsTypeParams type_params;
      MsTypeRefs targets;
    } alias;
    struct {
      MsName name;
      MsTypeParams type_params;
      struct {
        MsMethod **ptr;
        uint32_t len;
      } methods;
    } iface;
    struct {
      MsTypeRef *contract; /* NULL for `impl Type` */
      MsTypeRef *receiver;
      MsTypeParams bounds;
      struct {
        MsMethod **ptr;
        uint32_t len;
      } methods;
    } impl;
    struct {
      MsSpan name;
      MsStmts body;
      bool bench;
      int64_t per;
    } test;
  } u;
} MsDecl;

typedef struct MsImport {
  uint32_t id;
  MsPos pos;    /* the `import` keyword */
  MsPos clause; /* first name of this binding's clause */
  MsPos name_pos;
  MsName name;
  MsSpan path;
} MsImport;

typedef struct MsModule {
  MsImport *imports;
  uint32_t nimports;
  MsDecl **decls;
  uint32_t ndecls;
  uint32_t node_count; /* node ids are 0..node_count */
  /* Editor recovery only: names of declarations left out and the spans that parsed after
   * blanking invalid statements. */
  MsSpan *omitted;
  uint32_t nomitted;
  MsOffsetRange *recovered;
  uint32_t nrecovered;
} MsModule;

/* An `impl Type` block, with no contract. */
static inline bool ms_decl_is_inherent_impl(const MsDecl *decl) {
  return decl->kind == MS_D_IMPL && decl->u.impl.contract == NULL;
}

/* Whether the declaration carries an implementation: a body, an `extern fn`, a constant, alias or test. */
static inline bool ms_decl_has_body(const MsDecl *decl) {
  switch ((MsDeclKind)decl->kind) {
  case MS_D_FN: return decl->u.fn.body.len > 0 || decl->u.fn.external;
  case MS_D_CONST:
  case MS_D_ALIAS: return true;
  case MS_D_TEST: return decl->u.test.body.len > 0;
  case MS_D_IMPL:
    for (uint32_t i = 0; i < decl->u.impl.methods.len; i++) {
      if (decl->u.impl.methods.ptr[i]->func.body.len > 0) {
        return true;
      }
    }
    return false;
  case MS_D_TYPE:
  case MS_D_ENUM:
  case MS_D_INTERFACE: return false;
  }
  return false;
}

/* Whether every import of `module` is from the standard library (`@std/`). */
static inline bool ms_module_only_std_imports(const MsModule *module) {
  for (uint32_t i = 0; i < module->nimports; i++) {
    if (!ms_span_starts_with(module->imports[i].path, ms_span_of_text("@std/"))) {
      return false;
    }
  }
  return true;
}

#endif
