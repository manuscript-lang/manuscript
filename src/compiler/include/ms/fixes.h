/* Machine-applicable fixes for diagnostics: the pure builders of crates/ms-check/src/suggestions.rs.
 * A misspelled name carries `; did you mean 'x'?` and an unresolved standard name carries
 * `; add: import x from "module"`; when exactly one edit is named, the diagnostic also carries it
 * as an MsFix. The expression fixes rewrite the source range of one expression.
 *
 * Every builder returns false when it offers no fix. Replacement text is allocated in the arena.
 * Whitespace trimming is ASCII; the Rust helper also trims Unicode spaces, which these messages
 * and declarations do not contain. */
#ifndef MS_FIXES_H
#define MS_FIXES_H

#include "ms/ast.h"
#include "ms/hints.h"

/* The fix for a diagnostic at `pos` whose offending name has `len` bytes. */
MS_NODISCARD bool ms_fix_for(MsArena *arena, MsStr message, MsPos pos, size_t len, MsFix *out);

/* Records `fix` as the edit `diag` carries. */
void ms_diag_set_fix(MsDiag *diag, MsFix fix);

/* Gives `diag`, a diagnostic about the `len`-byte name at its position, the fix its message names (ms_fix_for), if
 * it names exactly one. */
void ms_diag_fix_name(MsArena *arena, MsDiag *diag, size_t len);

/* The `var` form of the immutable binding `name := v` or `name: T := v` declared at `decl`; none
 * unless the source reads a plain name there, so patterns and loop variables get no edit. */
MS_NODISCARD bool ms_binding_to_var(MsArena *arena, MsStr source, MsPos decl, MsFix *out);

/* Removal of the `()` after the nullary case `name` called at `pos`. */
MS_NODISCARD bool ms_drop_case_parens(MsStr source, MsPos pos, MsStr name, MsFix *out);

/* Where the written expression starts: `pos` anchors members, operators and index reads, so this
 * follows the leftmost operand. */
MsPos ms_expr_start(const MsExpr *e);

/* `value.call` for the expression `e`, parenthesised when `e` is not atomic. */
MS_NODISCARD bool ms_append_call(MsArena *arena, MsStr source, const MsExpr *e, MsStr call, MsFix *out);

/* `value()` for a no-argument method named without its parentheses. */
MS_NODISCARD bool ms_append_parens(MsArena *arena, MsStr source, const MsExpr *e, MsFix *out);

/* `value.is_some()` or `value.is_none()` for `value != none` / `value == none`: the fix replaces
 * `whole` and tests `other`. */
MS_NODISCARD bool ms_none_test(MsArena *arena, MsStr source, const MsExpr *whole, const MsExpr *other,
                               bool present, MsFix *out);

/* `f"{value}"` for the expression `e`, unless its text would not nest. */
MS_NODISCARD bool ms_interpolate(MsArena *arena, MsStr source, const MsExpr *e, MsFix *out);

/* Converts the Int expression `e` to Float: `3` becomes `3.0`, else `.to_float()`. */
MS_NODISCARD bool ms_to_float(MsArena *arena, MsStr source, const MsExpr *e, MsFix *out);

/* The conversion fix for an `actual` value used where `expected` is required. */
MS_NODISCARD bool ms_conversion_fix(MsArena *arena, MsStr source, const MsExpr *e, MsStr actual,
                                    MsStr expected, MsFix *out);

/* Whether the operator `op` of the binary expression at `pos` is the operator of a compound
 * assignment (`x += y`). The parser desugars that to `x = x + y`, so the left operand is the
 * assignment target and no fix may rewrite it. */
bool ms_is_compound_operator(MsStr source, MsPos pos, MsStr op);

#endif
