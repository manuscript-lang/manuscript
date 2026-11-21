/* compiler/check/symbol_text.c: naming symbols in diagnostics. */
#include "compiler/check/symbol_text.h"

bool ms_symbol_is_constant(const MsSymbol *symbol) {
  return symbol->decl != NULL && symbol->decl->kind == MS_D_CONST;
}

const char *ms_symbol_description(uint32_t module, const MsSymbol *symbol) {
  const bool imported = symbol->module != module;
  if (ms_symbol_is_constant(symbol)) {
    return imported ? "imported constant" : "constant";
  }
  if (symbol->kind == MS_SYMBOL_FN) {
    return imported ? "imported function" : "function";
  }
  if (symbol->kind == MS_SYMBOL_TYPE) {
    return imported ? "imported type" : "type";
  }
  return "declaration";
}
