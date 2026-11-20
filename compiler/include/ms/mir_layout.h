/* MIR layout: which recursive types live behind a pointer (boxing), and the machine layout of
 * every type (port of crates/ms-mir layout.rs and the `Boxing` of ir/module.rs).
 *
 * Both read a finished module and never change it. The types they are asked about must already be
 * in the module's type table, and the table must not grow while a `MirBoxing` or `MirLayouts` is
 * in use. */
#ifndef MS_MIR_LAYOUT_H
#define MS_MIR_LAYOUT_H

#include "ms/mir.h"

/* Types are followed this deep through the fields they hold by value. A type nested deeper is
 * reported through `failed` and answered as not boxed; real programs stay far below it. */
#define MIR_LAYOUT_MAX_DEPTH 2000

/* ---- boxing ---- */

/* An alternative or an optional that contains itself by value lives behind a pointer. One
 * `MirBoxing` remembers the answers for a module; as in the Rust version, an answer given while a
 * cycle is still being explored is provisional, so the result of a query can depend on which
 * queries came before it in the same `MirBoxing`. */
typedef struct MirBoxing {
    const MirModule *module; /* borrowed from the caller, valid until mir_boxing_free */
    MsArena arena;           /* owned: the memo tables and the visit lists */
    uint8_t *alts;           /* owned: per alternative, 0 unknown, 1 not boxed, 2 boxed */
    uint8_t *opts;           /* owned: per inner type of an optional, the same codes */
    uint32_t depth;
    bool failed;             /* some query went past MIR_LAYOUT_MAX_DEPTH */
} MirBoxing;

void mir_boxing_init(MirBoxing *boxing, const MirModule *module);
void mir_boxing_free(MirBoxing *boxing);

/* Whether alternative `alt` contains itself by value. */
bool mir_boxing_alt(MirBoxing *boxing, uint32_t alt);
/* Whether `inner?` contains itself by value. */
bool mir_boxing_opt(MirBoxing *boxing, MirTy inner);

/* One-off queries with no memory between them (`Module::opt_is_boxed`). */
bool mir_alt_is_boxed(const MirModule *module, uint32_t alt);
bool mir_opt_is_boxed(const MirModule *module, MirTy inner);

#endif
