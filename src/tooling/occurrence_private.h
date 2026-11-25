/* Owns occurrence_private.h: the builder state occurrence.c shares with occurrence_types.c. */
#ifndef MS_TOOLING_OCCURRENCE_PRIVATE_H
#define MS_TOOLING_OCCURRENCE_PRIVATE_H

#include "tooling/occurrence.h"

#include "tooling/avec.h"

typedef struct Builder {
  MsArena *arena;
  MsCheckProgram *program;
  MsOccurrences out;
  MsWrittenTypes *written_out; /* every resolved written type, when the caller asked */
  /* Per user module, indexed by node id. */
  MsSymbolId **symbol_at;               /* the symbol a declaration node declares */
  const MsMethodEntry ***method_at;     /* the method a method node declares */
  MsSpan **param_key;                   /* the key of the parameter or field a node declares */
  MsTy **written;                       /* the checked type of a written type node */
  bool **assigned;                      /* an expression that is the target of an assignment */
  uint32_t module;                      /* the module being walked */
  struct TypeSites *sink;               /* where the written-type collectors append */
} Builder;

/* One written type: its node, the position of its name and the name; a function type has none. */
typedef struct TypeSite {
  uint32_t id, offset;
  MsName name;
  bool named;
} TypeSite;

MS_AVEC(TypeSites, type_sites, TypeSite)

MsSpan ms_occ_symbol_key(const Builder *b, MsSymbolId id);
MsSpan ms_occ_module_file(const Builder *b, uint32_t module);
MsSpan ms_occ_name_text(const Builder *b, MsName name);
void ms_occ_add(Builder *b, MsSpan key, MsSpan name, uint32_t module, uint32_t offset, bool declaration, bool write, MsTy ty,
               MsSymbolId symbol, bool method);
MsSymbolId ms_occ_type_symbol(const Builder *b, MsTy ty);
void ms_occ_declare_types(Builder *b, uint32_t module);
void ms_occ_declare_type_parameters(Builder *b, uint32_t module);

#endif
