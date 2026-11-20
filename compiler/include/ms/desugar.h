/* Inherent-impl desugaring: the pass that runs on a parsed module before its declarations are
 * entered in the checker tables.
 *
 * Each `impl Type:` block (a `fn Type.name()` method group) becomes `impl Type$methods for Type:`
 * with a synthesized interface carrying the same signatures, so a type's own methods follow the
 * ordinary implementation rules. Blocks for one receiver form merge into the first. Property
 * markers (`// ms: data`) above a bundled type become body-less `Data` or `Clonable` impls, and an
 * `impl` whose receiver names a set alias (`type Ordered = Int | Float`) becomes one impl per
 * member, each with fresh node ids.
 *
 * Mirrors `desugar_inherent_impls` in crates/ms-check/src/passes.rs. The input tree is not
 * changed: the result shares its nodes except for the ones it had to build. */
#ifndef MS_DESUGAR_H
#define MS_DESUGAR_H

#include "ms/ast.h"
#include "ms/base.h"
#include "ms/tables.h"

/* What the pass reads. */
typedef struct MsDesugarInput {
    MsStr file;                /* the module's path; a path under `@std/` is a bundled module */
    MsStr source;              /* the module's text, for the property markers of bundled types */
    const MsModule *module;
    MsDecl *const *foreign;    /* types another module declares that this one's methods may name */
    uint32_t nforeign;
} MsDesugarInput;

/* A misuse of an inherent block: reported as a type-phase diagnostic at `pos`. */
typedef struct MsInherentError {
    MsPos pos;
    MsStr message;
} MsInherentError;

typedef struct MsDesugared {
    MsDecl **decls;
    uint32_t ndecls;
    MsInherentError *errors;
    uint32_t nerrors;
    uint32_t node_count; /* node ids are 0..node_count; the pass allocated the ones past the input's */
} MsDesugared;

/* Desugars `in->module`. Every node and text of the result lives in `arena`; `names` gains the
 * names of the generated interfaces. */
void ms_desugar_inherent_impls(MsArena *arena, MsNames *names, const MsDesugarInput *in, MsDesugared *out);

/* Desugars the module row `module` of `c`: its syntax becomes a module with the desugared
 * declarations, allocated in `c->arena`, and its inherent errors are returned through `errors`
 * (`nerrors` of them, in `c->arena`). Run before `ms_module_declare`. `source` is the module's
 * text and `foreign` the types of a sibling module, as in `MsDesugarInput`. */
void ms_module_desugar(MsCheck *c, MsModId module, MsStr source, MsDecl *const *foreign,
                       uint32_t nforeign, MsInherentError **errors, uint32_t *nerrors);

/* A deep copy of `method` in `arena` whose every node has a fresh id drawn from `*next_id`
 * (renumber_method in crates/ms-syntax/src/renumber.rs). The old tree is not changed. */
MsMethod *ms_method_copy_fresh(MsArena *arena, uint32_t *next_id, const MsMethod *old);

#endif
