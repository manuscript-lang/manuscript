/* Effects: what each callable may do, and which project callables reach an effect no scope permits.
 *
 * An effect is a name (`std.fs.read`). A callable declares effects with `// ms: effect NAME` lines
 * above it; callers then see the declared names instead of what the body reaches. A callable is
 * permitted effects with `// ms: allow_effect PATTERN` lines above it or in the file header. This
 * file holds the two parts that need nothing but source text and a reference graph: reading those
 * lines, and resolving the graph. Producing the graph from checked code is a later pass.
 *
 * Mirrors crates/ms-check/src/effect_directives.rs and effect_reach.rs. No global state. */
#ifndef MS_EFFECTS_H
#define MS_EFFECTS_H

#include "ms/base.h"
#include "ms/tables.h"
#include "ms_rt/safe.h"

/* ---- directives ---- */

/* A list of names that may be absent: `present` is false when no line was written, which is
 * different from a scope that was written and lists nothing. */
typedef struct MsEffectScope {
    const MsStr *names; /* borrowed from the arena the scope was read into */
    uint32_t count;
    bool present;
} MsEffectScope;

/* The directive lines of one comment block. */
typedef struct MsDirectives {
    MsEffectScope declared; /* `// ms: effect NAME`; `present` is unused */
    MsEffectScope allow;    /* `// ms: allow_effect PATTERN` */
} MsDirectives;

/* The lines of one source file, for header and per-declaration lookups. */
typedef struct MsSourceLines {
    const MsStr *lines; /* split at '\n', trailing '\r' removed; borrowed from `source` and the arena */
    uint32_t count;
} MsSourceLines;

/* Splits `source` into lines. The result borrows `source` and lives in `arena`. */
MsSourceLines ms_lines_index(MsArena *arena, MsStr source);

/* The file header: `//` lines at the top of the file, ended by a blank line. A comment block that
 * runs straight into code belongs to that declaration, not to the file. */
MsDirectives ms_lines_header(MsArena *arena, MsSourceLines lines);

/* The `//` lines directly above the 1-based `line`, up to a blank or code line, nearest first. */
MsDirectives ms_lines_above(MsArena *arena, MsSourceLines lines, uint32_t line);

/* Whether `effect` matches `pattern`: `*` matches everything, `a.b.*` a prefix, `*.write` a last
 * segment, and any other pattern only itself. */
bool ms_effect_matches(MsStr pattern, MsStr effect);

/* ---- reference graph ---- */

typedef struct MsReachEdge {
    uint32_t callee; /* the `id` of another node; an id no node has is ignored */
    MsPos pos;       /* where the first reference to it is */
} MsReachEdge;

/* One callable and the callables it references: calls, function values, closure bodies. */
typedef struct MsReachNode {
    uint32_t id; /* unique among the nodes */
    MsStr file;
    MsStr label; /* `save`, or `Receiver.method` */
    MsPos pos;
    bool project; /* a project callable is checked; a library one only contributes effects */
    bool entry;   /* `main` is the boundary: it may perform everything */
    const MsStr *declared;
    uint32_t ndeclared;
    MsEffectScope allow_fn;   /* lines directly above the callable */
    MsEffectScope allow_file; /* lines in the file header */
    MsEffectScope cap;        /* a fetched package's manifest effects: nothing widens them */
    const MsReachEdge *edges;
    uint32_t nedges;
} MsReachNode;

/* The effects callers see for one node that has any, sorted by name. */
typedef struct MsReachDeclared {
    uint32_t node; /* index into the node array */
    const MsStr *effects;
    uint32_t count;
} MsReachDeclared;

/* A project callable that reaches an effect no scope permits. */
typedef struct MsViolation {
    MsStr file;
    MsPos pos; /* the first reference in the callable that brings the effect in */
    MsStr effect;
    const uint32_t *path; /* node indices from the violating callable to the one that declares the effect */
    uint32_t npath;
} MsViolation;

typedef struct MsReach {
    const MsReachDeclared *declared; /* in node order */
    uint32_t ndeclared;
    const MsViolation *violations; /* in node order, then effect name order */
    uint32_t nviolations;
} MsReach;

/* Resolves declared effects over `nodes` and reports unpermitted reach. The result lives in
 * `arena`. Returns false, writing nothing, when two nodes share an id. */
MS_NODISCARD bool ms_reach_resolve(MsArena *arena, const MsReachNode *nodes, uint32_t count,
                                   MsReach *out);

/* ---- the scan of checked bodies (effect_scan.c) ---- */

/* What one callable's body reaches, read from the checker's facts. The edges are the first reference
 * to each callable, in source order; `unknown` is set when the body does something the scan cannot
 * classify (a call whose callee the checker did not resolve, a native outside `core/panic`).
 * Mirrors the `Scan` visitor of crates/ms-check/src/effects.rs, for the constructs the C body
 * checker handles so far; a body it did not check has no facts and is not scanned. */
typedef struct MsScanEdge {
    MsSymId callee;
    MsPos pos;
} MsScanEdge;

typedef struct MsScanNode {
    const MsScanEdge *edges;
    uint32_t nedges;
    bool unknown;
    bool write; /* assigns to a member */
    bool partial; /* reaches a method or interface call, whose edge the scan does not record yet */
} MsScanNode;

/* Scans the declaration `d` (a function or constant) of `module`, whose body the checker checked.
 * The edges live in `arena`. */
MsScanNode ms_effect_scan_decl(MsArena *arena, const MsCheck *c, MsModId module, const MsDecl *d);

/* ---- per-entity facts (effect_facts.c) ---- */

/* What the review facts say about one project function or constant, for the facts JSON. All strings
 * live in the arena the facts were made in. `partial` is set when the scan cannot yet see every
 * edge below it (a method or interface call, a body of a library callable the checker has not
 * checked): the arrays are then incomplete and must not be read as "empty". */
typedef struct MsEntityEffects {
    const MsDecl *decl;
    bool partial;
    const MsStr *effects; /* declared effects the callable reaches, sorted */
    uint32_t neffects;
    const MsStr *permits; /* `allow_effect` patterns in force, as written */
    uint32_t npermits;
    const MsStr *calls; /* project callables the body calls: declaration names, sorted and unique */
    uint32_t ncalls;
    const MsStr *external; /* callees outside the project: their symbol ids, sorted and unique */
    uint32_t nexternal;
} MsEntityEffects;

/* Facts for every body-checked function and constant of project `module`, whose source is `text`
 * (the other modules' text is the checker's own). Run the ownership walk first: it marks bindings that close at scope end (MS_BIND_RESOURCE), whose implicit `close` call makes a function `partial`. The result has one row per such declaration in
 * declaration order; `*count` is the number of rows. */
MsEntityEffects *ms_effect_facts(MsArena *arena, const MsCheck *c, MsModId module, MsStr text, uint32_t *count);

#endif
