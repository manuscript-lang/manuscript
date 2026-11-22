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

/* The descriptor target of `key`, built when it is new. */
MirRef mird_descriptor(DataCx *cx, MirTy key);

/* Builds the ShapeTable of the type a `shape` instruction names (mir_shape_table.c). */
void mird_visit_shape(DataCx *cx, const MirFunc *func, const MirInst *inst);

/* The types of the collection shapes inside the shape table of `ty`: each needs a descriptor. */
void mir_shape_desc_types(const MirModule *module, MirLayouts *layouts, MirTy ty, MirIdList *out);

/* One symbol per long string literal, constant byte string and constant list that a function uses. */
void mird_constants(DataCx *cx);

#endif
