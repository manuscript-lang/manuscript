/* Constant arithmetic over literals: the folding and the certain faults of
 * crates/ms-check/src/constfaults.rs. Pure functions of the syntax tree; the checker supplies the
 * integer type's range and name and reports the messages returned here. */
#ifndef MS_CONSTFOLD_H
#define MS_CONSTFOLD_H

#include "ms/ast.h"
#include "ms/base.h"

__extension__ typedef __int128 MsInt128;

/* ---- number literals (crates/ms-syntax/src/number.rs) ---- */

/* The literal as plain decimal text: separators removed and a `0x` or `0b` value written in base
 * 10. A hex or binary value beyond 128 bits is returned unconverted so range checks fail. */
MsStr ms_number_canonical(MsArena *arena, MsStr text);

/* Whether canonical literal text is a `Decimal` (`d` suffix). */
bool ms_number_is_decimal(MsStr canonical);

/* Whether canonical literal text is a fractional float (a point or exponent). */
bool ms_number_is_fractional(MsStr canonical);

/* ---- folding ---- */

/* Memoized facts about the arithmetic trees of one module. Each fact of a node reads only the
 * facts of its operands, so every node is visited once however deep the tree. */
typedef struct MsLiteralFacts MsLiteralFacts;

MsLiteralFacts *ms_literal_facts_new(MsArena *arena, const MsNames *names, uint32_t node_count);

/* The value of an integer expression built from literals and `+ - * / %` within the inclusive
 * range [lo, hi]. False when an operand is not constant, a division is by zero, or an
 * intermediate leaves the range. */
MS_NODISCARD bool ms_fold(MsLiteralFacts *facts, const MsExpr *e, MsInt128 lo, MsInt128 hi, MsInt128 *out);

/* What a tree of plain literals and arithmetic is. Mixed integer and fractional literals have no
 * common kind. */
typedef enum MsLiteralKind { MS_LITERAL_NONE, MS_LITERAL_INTEGER, MS_LITERAL_FRACTIONAL } MsLiteralKind;

MsLiteralKind ms_literal_tree_kind(MsLiteralFacts *facts, const MsExpr *e);

/* ---- certain faults ---- */

/* The diagnostic for `left op right` over integers of the type named `type_name`, whose values are
 * [lo, hi], when constant operands make it fault; empty when it cannot be shown to. */
MsStr ms_constant_arithmetic_fault(MsArena *arena, MsLiteralFacts *facts, MsBinaryOp op, const MsExpr *left,
                                   const MsExpr *right, const char *type_name, MsInt128 lo, MsInt128 hi);

/* The diagnostic for a constant `index` outside the list literal `left`, folded as an `Int` of
 * [lo, hi]; empty otherwise. */
MsStr ms_constant_index_fault(MsArena *arena, MsLiteralFacts *facts, const MsExpr *left, const MsExpr *index,
                              MsInt128 lo, MsInt128 hi);

#endif
