/* compiler/own/borrows_internal.h: the state the borrow pass shares between collecting borrows and judging them. */
#ifndef MS_COMPILER_OWN_BORROWS_INTERNAL_H
#define MS_COMPILER_OWN_BORROWS_INTERNAL_H

#include "compiler/own/class.h"
#include "compiler/own/bind.h"
#include "compiler/own/result_borrows.h"
#include "compiler/own/expr_text.h"
#include "compiler/syntax/walk.h"

typedef struct Borrow {
  uint32_t binding; /* the borrowing binding */
  MsName name;
  MsPos at; /* where it is bound */
  uint32_t after; /* the offset its initializer ends at */
  bool mutable_;
  bool alias; /* bound from a bare name the binding takes (`b := s`, `s` not read again): the source only gives way to a move */
  bool loop; /* the variable of a `for`: the loop keeps the source frozen for its whole body */
  bool captured;     /* a closure or promise reads it through a capture */
  bool method_value; /* a method read as a value (`f := xs.any`): it keeps its receiver until it is last called */
  uint32_t root; /* the binding it borrows from */
  const MsExpr *place; /* the part of it that is borrowed */
  uint32_t parts; /* bit i: the view covers the storage of type argument i of its receiver; 0 when it covers all of it */
} Borrow;

typedef struct Change {
  uint32_t root;
  MsPos pos;     /* where the changed place starts */
  uint32_t end;  /* the offset it ends at */
  bool moved;   /* a whole name goes to a `move` parameter */
  bool assign;  /* a whole name is assigned: a field or element store is a change of the name */
  MsPos at;     /* where the diagnostic points: a stored field's own name, else where the place starts */
  const MsExpr *place; /* the changed place; NULL when it is the whole binding */
  const MsExpr *lambda; /* the outermost open closure that captured the root and changes it, or NULL */
  bool value_write; /* a `var` argument or receiver that is a value of a map (`m[k]`): changes the value in place, never the keys */
} Change;

typedef struct Use {
  uint32_t binding;
  uint32_t offset;
  uint32_t loop; /* a loop's own use of its variable at the end of the body: where that `for` starts, plus one; else 0 */
} Use;

/* A source range: a branch's two arms exclude each other; a loop body runs again after its end. */
typedef struct Range {
  uint32_t lo, split, hi; /* an if: [lo, split) is the then arm and [split, hi] the else arm; a loop: [lo, hi] */
  bool loop;
} Range;

/* What a borrowing expression was computed from: the place it reads and the innermost call applied to it. */
typedef struct Source {
  uint32_t root;
  const MsExpr *place;
  const MsExpr *call;
  uint32_t parts; /* see Borrow */
} Source;

/* A borrowing call in a position that keeps its result. */
typedef struct Keep {
  const MsExpr *kept;
  Source source;
  bool returned; /* a value the function hands back that it only reads in place: no borrow origin, see report_returned */
} Keep;

/* A block that ends in an unconditional `break` or `return`: a change in [lo, at) is followed by that exit, so no earlier
 * or later use in the loop (or, for a `return`, anywhere) runs after it. */
typedef struct Exit {
  uint32_t lo, at;
  bool is_return;
} Exit;

MS_LIST_DEFINE(RangeList, range_list, Range)
MS_LIST_DEFINE(ExitList, exit_list, Exit)
MS_LIST_DEFINE(LambdaList, lambda_list, const MsExpr *)
MS_LIST_DEFINE(SourceList, source_list, Source)
MS_LIST_DEFINE(KeepList, keep_list, Keep)
MS_LIST_DEFINE(BorrowList, borrow_list, Borrow)
MS_LIST_DEFINE(ChangeList, change_list, Change)
MS_LIST_DEFINE(UseList, use_list, Use)

typedef struct Borrows {
  MsCheckProgram *program;
  MsClassifier *classes;
  uint32_t module;
  MsFacts *facts;
  MsSpan source;
  BorrowList borrows;
  ChangeList changes;
  UseList uses;
  UseList view_vars; /* the `var`s that hold a view: a later store replaces the reference */
  RangeList ranges;
  ExitList exits;
  LambdaList kept; /* closures handed to a function the runtime keeps them in (a started promise) */
  KeepList keeps;
  SourceList extra; /* the origins after the first that the last origin_of_* query found */
  uint32_t high; /* the furthest end offset seen by the current measuring walk */
  bool ref_result; /* the callable being walked answers a `&` result: `ok(part)` wraps a view, it keeps nothing */
  uint32_t lambdas; /* open closures: what they return is theirs */
  const MsExpr *outer; /* the outermost open closure */
} Borrows;

/* Describes a value a function hands back that it only reads in place; false when nothing is wrong. */
bool ms_borrows_describe_returned(Borrows *pass, const MsExpr *value, MsStrBuild *text);
/* Whether `call` lends a whole collection rather than an element. */
bool ms_borrows_lends_collection(const Borrows *pass, const MsExpr *call);
/* Reports every change of a source made while a borrow of it is still used, then clears the lists. */
void ms_borrows_judge(Borrows *pass);

#endif
