/* compiler/check/symbol_text.h: how diagnostics name a module-level symbol. */
#ifndef MS_COMPILER_CHECK_SYMBOL_TEXT_H
#define MS_COMPILER_CHECK_SYMBOL_TEXT_H

#include "compiler/check/program.h"

/* `constant`, `function`, `type` or `declaration`, with `imported ` before the first three when the symbol
 * belongs to a module other than `module`. */
const char *ms_symbol_description(uint32_t module, const MsSymbol *symbol);

/* Whether the symbol is a module-level `let` constant. */
bool ms_symbol_is_constant(const MsSymbol *symbol);

#endif
