/* compiler/mir/mir_data.h: the static data every back end emits the same way: type descriptors, interface
 * vtables, globals, long string literals, constant byte strings and lists, and the shared blocks of
 * payloadless alternative cases. MIR decides what each symbol holds (name, alignment, bytes, and the addresses
 * inside it); the emitter only prints that in its own text, so no back end carries layout knowledge.
 *
 * Ownership: a MirData owns its lists and map (mir_data_free); symbol names, bytes and relocations live in the
 * module's arena, so the module outlives the data. Build it after glue, whose functions the symbols point at. */
#ifndef MS_COMPILER_MIR_MIR_DATA_H
#define MS_COMPILER_MIR_MIR_DATA_H

#include "base/map.h"
#include "compiler/mir/mir_desc.h"
#include "compiler/mir/mir_glue.h"

/* What an address points at. */
typedef enum MirRefKind { MREF_DATA, MREF_FUNC, MREF_RUNTIME } MirRefKind;

typedef struct MirRef {
  MirRefKind kind;
  uint32_t index;  /* MREF_DATA: index in MirData.syms; MREF_FUNC: function id */
  MsSpan runtime;  /* MREF_RUNTIME: the symbol */
} MirRef;

/* The eight bytes at `offset` of the symbol hold the address of `to`. */
typedef struct MirReloc {
  uint32_t offset;
  MirRef to;
} MirReloc;

typedef struct MirDataSym {
  MsSpan name;
  uint32_t size;
  uint32_t align;
  bool writable;
  MsSpan bytes; /* `size` bytes, or empty for all zero */
  MirReloc *relocs; /* in the module arena */
  uint32_t nrelocs;
} MirDataSym;

MS_LIST_DEFINE(MirDataSymList, mir_data_sym_list, MirDataSym)

/* The shared block of a payloadless case of a boxed alternative: the case index, then zeros. Such values never
 * allocate, and dropping them frees nothing. */
typedef struct MirUnit {
  uint32_t alt, case_index, sym;
} MirUnit;

MS_LIST_DEFINE(MirUnitList, mir_unit_list, MirUnit)

MS_MAP_DEFINE(MirDescMap, mir_desc_map, MirTy, MirRef, ms_hash_u32_key, ms_equal_u32_key)

typedef struct MirData {
  MirDataSymList syms;
  MirIdList globals;      /* symbol of each module global */
  MirIdList vtables;      /* symbol of each module vtable */
  MirUnitList units;      /* the unit blocks some function builds */
  MirIdList blobs;        /* by blob id: the symbol of the constant bytes, MIR_NONE when no function uses it */
  MirIdList list_consts;  /* by constant list id: the symbol of its elements, MIR_NONE when unused */
  MirIdList strings;      /* by string id: the symbol of a long literal's bytes, MIR_NONE for a short or unused one */
  MirDescMap descs;       /* every descriptor key seen, with its target */
  MirDescMap shapes;      /* every type a `shape` names, with its ShapeTable symbol */
} MirData;

/* The data of `module`: one symbol per global and vtable, one per constant a function uses, and one per
 * descriptor any function names (and any inner descriptor those name). */
void mir_data_build(MirModule *module, const MirGlue *glue, MirData *out);
void mir_data_free(MirData *data);

/* The data symbol of the unit block of case `case_index` of boxed alternative `alt`, or MIR_NONE. */
uint32_t mir_data_unit(const MirData *data, uint32_t alt, uint32_t case_index);

/* The target of the descriptor for `key`, which mir_data_build saw in a function; a runtime reference with an
 * empty symbol when it did not. */
MirRef mir_data_desc(const MirData *data, MirTy key);

/* The ShapeTable symbol of the type a `shape` instruction names; a runtime reference with an empty symbol when
 * mir_data_build did not see it. */
MirRef mir_data_shape(const MirData *data, MirTy ty);

/* The two words of string literal `text`. A literal of up to 15 bytes is an inline string, so `*is_static` is
 * false and `lo`, `hi` are the words; a longer one is static data (MirData.strings) whose address is the first
 * word and `hi` the second, flagged ASCII when every byte is. */
void mir_str_lit_words(MsSpan text, bool *is_static, uint64_t *lo, uint64_t *hi);

#endif
