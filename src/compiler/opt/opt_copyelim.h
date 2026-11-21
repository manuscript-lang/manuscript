/* Shared by the files of the `copyelim` pass. */
#ifndef MS_COMPILER_OPT_OPT_COPYELIM_H
#define MS_COMPILER_OPT_OPT_COPYELIM_H

#include "compiler/opt/opt_pass.h"


/* A position (block, instruction). */
typedef struct CpePos {
  uint32_t block, index;
} CpePos;

/* Operand uses of each value as positions in program order; a value used twice by one
 * instruction appears twice. Terminator uses are not listed. In one arena. */
typedef struct CpeUses {
  uint32_t *start; /* nvalues + 2 entries */
  CpePos *at;
} CpeUses;

static inline uint32_t cpe_nuses(const CpeUses *u, MirValue v) { return u->start[v + 1] - u->start[v]; }
static inline CpePos cpe_use(const CpeUses *u, MirValue v, uint32_t k) { return u->at[u->start[v] + k]; }

/* Operand uses of each value within one block's instructions, sorted by value then position. */
typedef struct CpeBlockUses {
  uint64_t *keys; /* value << 32 | instruction */
  uint32_t n;
} CpeBlockUses;

/* The values each value is borrowed by: results that borrow from their operands (or, with
 * `all`, every result that is not an owned non-view one). In one arena, as CSR. */
typedef struct CpeBorrows {
  uint32_t *start;
  MirValue *list;
} CpeBorrows;

/* A growing list of positions. */
typedef struct CpeDead {
  CpePos *at;
  uint32_t n, cap;
} CpeDead;

/* What a scan of one block's instructions found for the source `v`: a drop ending the path at
 * `*drop_at`, an instruction reading what was borrowed from `v` (the path is not clean), or
 * nothing (the block passes `v` on untouched). */
typedef enum CpeScan { CE_SCAN_PASSES, CE_SCAN_DROP, CE_SCAN_READ } CpeScan;

typedef struct CpeHeld {
  const bool *held;
  bool used;
} CpeHeld;

/* The facts `cpe_move_across` reads about a function. */
typedef struct CpeFlow {
  bool *owned;
  uint32_t *home;
  CpeBorrows borrows;
  bool *tainted;
  MirPreds preds;
} CpeFlow;

/* What the copy-elimination of one function reads. */
typedef struct CpeLocal {
  const MirModule *m;
  const MirFunc *f;
  CpeUses at;
  CpePos *defs;
  uint32_t *uses;     /* operand and terminator uses per value */
  uint32_t *unstable; /* per block, prefix counts of memory-writing instructions; see `cpe_unstable` */
  uint32_t *unstable_base;
  MirMode *modes;     /* scratch for one instruction's argument modes */
} CpeLocal;

typedef struct CpeFind {
  MirValue v;
  bool hit;
} CpeFind;

/* A field taken out of the dying type: the load, its copy, and the field. */
typedef struct CpeTaken {
  uint32_t get, copy, field;
} CpeTaken;

CpeUses cpe_operand_uses(MsArena *arena, const MirFunc *f);
bool cpe_next_use(const CpeUses *u, MirValue v, uint32_t bi, uint32_t i, CpePos *out);
CpeBlockUses cpe_block_uses(MsArena *arena, const MirBlockData *b);
uint32_t cpe_after_start(const CpeBlockUses *u, MirValue v, uint32_t i);
bool cpe_after_next(const CpeBlockUses *u, MirValue v, uint32_t *cursor, uint32_t *at);
bool cpe_first_after(const CpeBlockUses *u, const MirBlockData *b, MirValue v, uint32_t i, MirOp op, uint32_t *out);
CpeBorrows cpe_borrows_of(MsArena *arena, const MirModule *m, const MirFunc *f, bool strict);
void cpe_hold(const CpeBorrows *br, MirValue v, uint32_t nvalues, bool *held, MirValue *stack);
bool *cpe_view_tainted(MsArena *arena, const MirModule *m, const MirFunc *f);
void cpe_dead_push(MsArena *arena, CpeDead *d, uint32_t block, uint32_t index);
void cpe_remove_insts(MsArena *arena, MirFunc *f, CpeDead *dead);
void cpe_apply_rename(MirFunc *f, MirValue *rename, bool terms);
MirValue *cpe_new_values(MsArena *arena, const MirFunc *f, MirValue fill);
bool *cpe_new_flags(MsArena *arena, const MirFunc *f);
bool cpe_move_dead_sources(MsArena *arena, const MirModule *m, MirFunc *f);
bool cpe_move_across(MsArena *arena, const MirModule *m, MirFunc *f);
bool cpe_borrow_local_copies(MsArena *arena, const MirModule *m, MirFunc *f);
bool cpe_alias_stable(MsArena *arena, const MirModule *m, MirFunc *f);
bool cpe_unbox_dead_options(MsArena *arena, MirModule *m, MirFunc *f);
bool cpe_unbox_dead_sources(MsArena *arena, MirModule *m, MirFunc *f);
bool cpe_take_type_fields(MsArena *arena, const MirModule *m, MirFunc *f);

#endif
