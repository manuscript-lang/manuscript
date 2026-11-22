/* compiler/check/effects_reach.h: declared effects, and which project callables reach an effect no scope
 * permits.
 *
 * Callables are nodes of a graph whose edges are the callables each references (calls, function values,
 * closure bodies). A callable that declares effects (`// ms: effect NAME`) shows callers its declared names
 * instead of what its body reaches. A project callable other than the entry reaches an effect it is not
 * permitted when no `allow_effect` line (on it, then in its file header) matches, and a fetched package's
 * manifest caps what its callables may reach.
 *
 * Effect names intern to bit positions and each callable owns a fixed-width row of one flat bit matrix;
 * propagation is a worklist over caller lists.
 *
 * Ownership: every output array and the spans in it live in the arena given to ms_effects_resolve; spans of
 * the input (names, labels) are borrowed and must outlive the result. */
#ifndef MS_COMPILER_CHECK_EFFECTS_REACH_H
#define MS_COMPILER_CHECK_EFFECTS_REACH_H

#include "base/arena.h"
#include "compiler/syntax/pos.h"

/* A scope of `allow_effect` patterns; `present` is false when no line was written (everything permitted by
 * this scope). */
typedef struct MsEffectScope {
  bool present;
  const MsSpan *patterns;
  uint32_t count;
} MsEffectScope;

typedef struct MsReachEdge {
  MsName callee; /* the id of the referenced callable */
  MsPos pos;     /* its first reference in the caller, in source order */
} MsReachEdge;

typedef struct MsReachNode {
  MsName id;
  MsName file;
  MsSpan label; /* display name: `save`, or `Receiver.method` */
  MsPos pos;
  bool project; /* a project callable is checked; a standard-library one only contributes effects */
  bool entry;   /* `main` is the boundary: it may perform everything */
  const MsSpan *declared;
  uint32_t declared_count;
  MsEffectScope allow_fn;   /* lines directly above the callable */
  MsEffectScope allow_file; /* lines in the file header */
  MsEffectScope cap;        /* a fetched package's manifest effects: no line can widen them */
  const MsReachEdge *edges;
  uint32_t edge_count;
} MsReachNode;

/* A project callable that reaches an effect no scope permits. */
typedef struct MsReachViolation {
  MsName file;
  MsPos pos;     /* the first reference in the callable that brings the effect in */
  MsSpan effect;
  const MsSpan *path; /* labels from the violating callable down to the one that declares the effect */
  uint32_t path_count;
} MsReachViolation;

typedef struct MsEffectNames {
  const MsSpan *names; /* sorted */
  uint32_t count;
} MsEffectNames;

typedef struct MsReach {
  MsEffectNames *declared; /* per node: the effects callers see, sorted by name */
  MsEffectNames *permits;  /* per node: the `allow_effect` patterns of a project callable's own scope, as written */
  const MsReachViolation *violations; /* in node order, then effect order */
  uint32_t violation_count;
} MsReach;

MsReach ms_effects_resolve(const MsReachNode *nodes, uint32_t count, MsArena *arena);

#endif
