/* compiler/own/live_pass.h: the state of one backward liveness walk, shared by its statement and expression
 * halves. */
#ifndef MS_COMPILER_OWN_LIVE_PASS_H
#define MS_COMPILER_OWN_LIVE_PASS_H

#include "compiler/own/bind.h"
#include "compiler/own/live.h"

MS_LIST_DEFINE(MsLiveStack, ms_live_stack, MsLiveSet)

typedef struct MsLivePass {
  const MsFacts *facts;
  MsArena *arena;
  const MsNames *names;
  MsLiveness *out;
  MsLiveStack breaks;    /* owned: what is live after each enclosing loop */
  MsLiveStack continues; /* owned: what is live at the head of each enclosing loop */
  MsLiveSet exit;        /* owned: live at `return`: captured variables inside a lambda */
} MsLivePass;

/* Walks a statement list backwards; takes and returns the live set. */
MsLiveSet ms_live_block(MsLivePass *pass, MsStmts body, MsLiveSet live);

/* Walks an expression backwards, updating the live set in place. */
void ms_live_expr(MsLivePass *pass, const MsExpr *expr, MsLiveSet *live);

/* Records a use of a place below `binding`: `node` keys the binding's own entry and `place_node` the place's. */
void ms_live_record(MsLivePass *pass, MsNode node, MsNode place_node, uint32_t binding, MsLivePath path,
                    MsLiveSet *live);

#endif
