/* compiler/mir/mir_data_internal.h: what the data files share. Not part of the layer's interface. */
#ifndef MS_COMPILER_MIR_MIR_DATA_INTERNAL_H
#define MS_COMPILER_MIR_MIR_DATA_INTERNAL_H

#include "compiler/mir/mir_data.h"
#include "compiler/mir/mir_layout.h"

typedef struct DataCx {
  MirModule *module;
  const MirGlue *glue;
  MirLayouts *layouts;
  MirData *data;
} DataCx;

/* Adds a symbol and returns its index. */
uint32_t mird_add_sym(DataCx *cx, const MirDataSym *sym);

/* The symbol name `ms.<kind>.<n>` in the module's arena. */
MsSpan mird_name(DataCx *cx, const char *kind, uint32_t n);

void mird_put_word(uint8_t *at, uint64_t value);

/* Calls `visit` for every instruction of every function. */
typedef void (*MirdInstFn)(DataCx *cx, const MirFunc *func, const MirInst *inst);
void mird_each_inst(DataCx *cx, MirdInstFn visit);

/* An id list of `count` entries, all MIR_NONE. */
void mird_fill_none(MirIdList *list, size_t count);

/* One symbol per long string literal, constant byte string and constant list that a function uses. */
void mird_constants(DataCx *cx);

#endif
