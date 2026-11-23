/* Shared by the files of the closure half of the `inline` pass. */
#ifndef MS_COMPILER_OPT_OPT_INLINE_CLOSURE_H
#define MS_COMPILER_OPT_OPT_INLINE_CLOSURE_H

#include "compiler/opt/opt_inline.h"


/* Per value of one function: the closure code and captures when it is a plain-data closure built
 * by `closure.new`, or reached through one. */
typedef struct IcKnown {
  uint32_t n;
  uint32_t *code;        /* MIR_NONE when unknown */
  const MirValue **caps; /* the captured values */
  uint32_t *ncaps;
  uint32_t count;
} IcKnown;

/* Incoming block-parameter arguments: row `base[b] + j` lists the arguments passed for parameter
 * `j` of block `b`. */
typedef struct IcIncoming {
  uint32_t *base; /* nblocks + 1 */
  uint32_t *off;  /* rows + 1 */
  MirValue *args;
} IcIncoming;

typedef struct IcDelete {
  const MirValue *alias;
  bool *live;       /* by root */
  bool *dead_param; /* by row */
  const uint32_t *base;
} IcDelete;

typedef struct IcEnvUse {
  MirValue env;
  bool used;
} IcEnvUse;

/* The closure code held by each type field that every construction in the module sets to the same
 * capture-free closure and that nothing else ever writes: an open-addressed table of
 * (type, field) -> code, MIR_NONE marking a field with two closures or a write the analysis cannot
 * see. */
typedef struct IcFields {
  uint32_t mask;
  bool *used;
  uint32_t *type, *field, *code;
} IcFields;

typedef struct IcInline {
  MirModule *m;
  uint32_t fi, budget, grown;
  uint32_t *work, nwork, cwork;
  const IcFields *fields;
} IcInline;

/* Specialised copies already made: (callee, closure code, parameter) -> copy. */
typedef struct IcMade {
  uint32_t *callee, *code, *param, *copy;
  uint32_t n, cap;
} IcMade;

/* Replaces every use of `from` in `f` by `to`. */
typedef struct IcRename { MirValue from, to; } IcRename;

typedef struct IcSpecialize {
  MirModule *m;
  MsArena *arena;
  IcMade made;
  uint32_t spent;
  const bool *cyc;
  uint32_t ncyc;
} IcSpecialize;

enum { IC_SPECIALIZE_ROUNDS = 4 };

typedef struct IcSortEdit { MirValue addr; uint32_t thunk, code; } IcSortEdit;

bool ic_known_has(const IcKnown *k, MirValue v);
IcKnown ic_known_closures(MsArena *arena, const MirModule *m, const MirFunc *f);
/* Every value that always holds a known closure, including copies and block parameters of one. */
IcKnown ic_known_aliased(MsArena *arena, const MirModule *m, const MirFunc *f);
bool ic_delete_unused(MirModule *m, uint32_t fi);
bool ic_closure_usable(const MirFunc *f);

#endif
