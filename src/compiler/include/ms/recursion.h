/* Finite generic applications: the graph walk of crates/ms-check/src/recursion.rs. A generic
 * function or type may refer to itself only with the type arguments it was given; changing them
 * would instantiate without end. The checker builds the graph (one node per generic declaration,
 * one edge per use that names type arguments) and reports the faults this returns.
 *
 * Two types are the same when their MsTy is the same: the table interns structures. */
#ifndef MS_RECURSION_H
#define MS_RECURSION_H

#include "ms/base.h"
#include "ms/types.h"

typedef enum MsAppMode {
    MS_APP_FUNCTIONS, /* generic functions and methods, found from the calls in their bodies */
    MS_APP_TYPES      /* generic types and interfaces, found from their fields and operations */
} MsAppMode;

/* A use of `target` (a node index) with type arguments written in terms of the source node's
 * variables. `file` and `pos` say where; `site` names the field or operation (types only). */
typedef struct MsAppEdge {
    const MsTy *args;
    MsStr site;
    uint32_t target;
    uint32_t nargs;
    MsSym file;
    MsPos pos;
} MsAppEdge;

/* A generic declaration, in declaration order, with its type variables and its uses. */
typedef struct MsAppNode {
    const MsTy *variables;
    const MsAppEdge *edges;
    uint32_t nvariables;
    uint32_t nedges;
} MsAppNode;

typedef struct MsAppFault {
    const MsAppEdge *edge;
} MsAppFault;

/* The faults, in the order the Rust checker reports them (one per offending edge visit; the
 * checker deduplicates identical diagnostics). Returns how many; `faults` is allocated in `arena`.
 * Types are interned in `tys`. */
size_t ms_check_applications(MsArena *arena, MsTyTable *tys, MsAppMode mode, const MsAppNode *nodes,
                             uint32_t count, const MsAppFault **faults);

/* The diagnostic text of a fault. */
MsStr ms_application_message(MsArena *arena, MsAppMode mode, const MsAppEdge *edge);

#endif
