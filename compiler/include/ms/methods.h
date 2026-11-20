/* The operations of interfaces and the methods of implementations: what a call on a value can
 * resolve to. The Rust checker's `Definition.operations` and `Program.methods`.
 *
 * An operation is a function declared in an `interface`; a method is an operation an `impl`
 * supplies, or an inherent method (an impl that desugaring synthesized an interface for, see
 * desugar.h). `ms_module_resolve_operations` reads the interfaces of a module whose types are
 * resolved (`ms_module_resolve_types`, check.h). */
#ifndef MS_METHODS_H
#define MS_METHODS_H

#include "ms/ast.h"
#include "ms/check.h"
#include "ms/facts.h"
#include "ms/tables.h"

/* One operation of an interface. */
typedef struct MsOperation {
    MsSym name;
    MsTy ty;                /* the signature over the interface's variables and `Self` */
    const MsMethod *decl;   /* the declaration inside the interface */
    const MsTy *vars;       /* the operation's own type variables */
    uint32_t nvars;
} MsOperation;

typedef struct MsOperations {
    MsOperation *items;
    uint32_t count, cap;
} MsOperations;

/* The columns of the method table and the operations by interface symbol; owned by the caller
 * and freed with `ms_methods_free`. */
typedef struct MsMethodTable {
    MsOperations *operations; /* by symbol id; grown on demand */
    uint32_t operations_cap;
} MsMethodTable;

void ms_methods_init(MsMethodTable *table);
void ms_methods_free(MsMethodTable *table);

/* Resolves the operations of every interface the module declares: its own type variables with
 * bounds and defaults, and its signature with `Self` in scope. Appends the diagnostics the Rust
 * checker reports for them to the module's list. */
void ms_module_resolve_operations(MsCheck *c, MsModId module, MsMethodTable *table);

/* The operations of the interface symbol `sym`, in declaration order; NULL when it has none. */
const MsOperations *ms_interface_operations(const MsMethodTable *table, MsSymId sym);

/* The operations of the module's interfaces in the form c_oracle_methods.rs prints, one `op` line
 * each, in declaration order. */
void ms_dump_operations(MsBuf *out, const MsCheck *c, MsModId module, const MsMethodTable *table);

#endif
