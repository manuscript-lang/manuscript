/* compiler/check/names_hint.h: the diagnostic for a name that means nothing.
 *
 * "unknown binding NAME" followed by the hint the oracle gives: a habit from another language, a field of the
 * receiver, a standard module to import, a near spelling, or the generic declare-it advice. The diagnostic
 * carries the one edit the hint names, when it names exactly one. */
#ifndef MS_COMPILER_CHECK_NAMES_HINT_H
#define MS_COMPILER_CHECK_NAMES_HINT_H

#include "compiler/check/scope_walk.h"

/* Reports that the name read at `pos` is unknown, in the resolution phase. */
void ms_unknown_name_report(MsCheckProgram *program, uint32_t module, MsPos pos, MsName name,
                            const MsBindingList *scope, const MsScopeSite *site);

#endif
