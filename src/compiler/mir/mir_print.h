/* compiler/mir/mir_print.h: the MIR text form, a dump format only: passes exchange the in-memory module. The
 * text is what `ms emit` writes, so it follows the oracle's canonical form: values are renumbered densely in
 * definition order and blocks are labelled by index. */
#ifndef MS_COMPILER_MIR_MIR_PRINT_H
#define MS_COMPILER_MIR_MIR_PRINT_H

#include "base/strbuild.h"
#include "compiler/mir/mir.h"

/* Appends the whole module. */
void mir_print_module(const MirModule *module, MsStrBuild *out);

/* Appends one function, ending in `}\n`. */
void mir_print_func(const MirModule *module, const MirFunc *func, MsStrBuild *out);

/* Appends a type as source of the text form reads it (`list<str>`, `Shape`, `fn(int) -> int`). */
void mir_print_ty(const MirModule *module, MirTy type, MsStrBuild *out);

/* Appends `text` in double quotes with the escapes the text form uses. */
void mir_print_quoted(MsStrBuild *out, MsSpan text);

/* The text name of a role (empty for none) and of a comparison. */
MsSpan mir_role_name(MirRole role);
MsSpan mir_cc_name(MirCc cc);

/* Appends a finite float as the shortest text that reads back, always with a fractional part. */
void mir_print_float(MsStrBuild *out, double value);

#endif
