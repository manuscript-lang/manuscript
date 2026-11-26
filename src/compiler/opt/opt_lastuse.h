/* Shared by the files of the `lastuse` pass. */
#ifndef MS_COMPILER_OPT_OPT_LASTUSE_H
#define MS_COMPILER_OPT_OPT_LASTUSE_H

#include "compiler/opt/opt_pass.h"


typedef struct LuList {
  uint64_t *v;
  uint32_t n, cap;
} LuList;

/* A position inside a block: an original instruction (`idx` is its index plus one, 0 for the
 * block start), or the `after`-th drop this pass has appended behind it (0 is the instruction). */
typedef struct LuPos {
  uint64_t idx;
  uint32_t after;
} LuPos;

/* The drops to insert behind one anchor, in emission order. */
typedef struct LuGroup {
  uint64_t anchor;
  MirValue *v;
  uint32_t n, cap;
} LuGroup;

/* The groups of one block, sorted by anchor. */
typedef struct LuPending {
  LuGroup *g;
  uint32_t n, cap;
} LuPending;

/* Where a value is read, built once per function so each candidate costs its own footprint rather
 * than a scan of the function. Instruction indices are those of the original function: the pass
 * never inserts or removes instructions while it analyses, it types the drops it removes and the
 * drops it adds and rewrites every block at the end. New edge blocks are added at once. */
typedef struct LuCtx {
  MirModule *m;
  MirFunc *f;
  MsArena *arena;
  MirMode *modes;
  uint32_t nvcap, nbcap;
  /* per value */
  LuList *uses;           /* block << 32 | instruction, including drops */
  LuList *term_uses;      /* blocks whose terminator passes the value on */
  LuList *pending_blocks; /* blocks holding a pending drop of the value */
  bool *slots;
  uint32_t *fam_gen;
  /* per block */
  bool **removed;
  LuPending *pending;
  LuList *preds; /* once per edge */
  uint32_t *lid_gen, *lid, *drop_gen, *drop_at, *cons_gen, *cons_at;
  uint32_t gen;
} LuCtx;

typedef struct LuTermCtx {
  LuCtx *x;
  uint32_t block;
} LuTermCtx;

typedef struct LuFamily {
  MsArena *arena; /* where the arrays live; they grow as members are found */
  MirValue *v;    /* members, in discovery order */
  uint32_t n, vcap;
  MirValue *work;
  uint32_t nwork, wcap;
} LuFamily;

typedef struct LuPlace {
  uint32_t block;
  LuPos pos;
} LuPlace;

/* Per-block facts of the region the analysis reads. */
typedef struct LuRegion {
  uint32_t nb;
  uint32_t *order; /* block of each local index, ascending */
  LuPos *end, *lo, *last;
  bool *any, *has_last;
} LuRegion;

/* One candidate's analysis: the family, the region it is read over and the facts per block. */
typedef struct LuRun {
  LuCtx *x;
  MsArena *ca;
  MirValue v;
  uint32_t db, di; /* defining block, instruction (MIR_NONE for a block parameter) */
  LuFamily fam;
  uint32_t nexisting;
  uint64_t *existing; /* the live drops of `v` */
  LuRegion r;
  uint32_t dl;
  bool *live_in, *live_out, *owned_in, *owned_out, *consumed;
} LuRun;

/* The drops of `v` to place: (block, position the drop follows) and edges (block << 32 | slot). */
typedef struct LuPlan {
  LuPlace *place;
  uint32_t nplace;
  uint64_t *edges;
  uint32_t nedges;
} LuPlan;

typedef struct LuCand {
  MirValue v;
  uint32_t block, inst; /* inst is MIR_NONE for a block parameter */
} LuCand;

void *lu_zeroed(MsArena *a, size_t n, size_t elem);
int lu_cmp(LuPos a, LuPos b);
LuPos lu_at(uint32_t i);
LuPos lu_start(void);
LuPos lu_end(void);
bool lu_live(const LuCtx *x, uint32_t bi, uint32_t ii);
uint32_t lu_use_block(uint64_t u);
uint32_t lu_use_inst(uint64_t u);
bool lu_in_family(const LuCtx *x, MirValue w);
bool lu_store_view(const LuCtx *x, const MirInst *i, MirValue w);
void lu_fit(LuCtx *x);
void lu_insert_pending(LuCtx *x, uint32_t bi, LuPos pos, MirValue v);
void lu_family(LuCtx *x, MsArena *ca, LuFamily *fam, MirValue v, uint32_t param_of);
bool lu_edge_consumes(const MirFunc *f, uint32_t bi, uint32_t slot, MirValue v);
void lu_add_edge(LuCtx *x, MirValue v, uint32_t pred, uint32_t slot);
bool lu_candidate(LuCtx *x, MirValue v, uint32_t db, uint32_t di);

#endif
