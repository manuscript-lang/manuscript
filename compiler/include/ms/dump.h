/* Canonical text forms used to compare the C front end with the Rust one. */
#ifndef MS_DUMP_H
#define MS_DUMP_H

#include "ms/ast.h"
#include "ms/base.h"

/* Quotes `s` in the dump's string syntax: printable ASCII as is, other bytes as \xNN. */
void ms_dump_quote(MsBuf *out, const char *s, size_t n);
void ms_dump_pos(MsBuf *out, MsPos p);
/* "error line:col:off end=... fix=... opener=N "message"\n" */
void ms_dump_diag(MsBuf *out, const MsDiag *d);

/* The canonical tree dump of crates/ms-syntax/src/dump.rs. */
void ms_dump_module(MsBuf *out, const MsNames *names, const MsModule *m);

#include "ms/tables.h"

/* The standard-library tables in the form crates/ms-check/examples/c_oracle.rs prints. */
void ms_dump_std_tables(MsBuf *out, const MsCheck *c);

/* The declared types of one module, as `c_oracle --scope` prints them: one `sym` line per
 * declaration with its variables, fields and cases beneath, then a `typeref` line per resolved
 * type reference. */
void ms_dump_module_types(MsBuf *out, const MsCheck *c, MsModId m);

/* The checked functions of the module: `fn LINE:COLUMN clean`, then `expr ID TYPE` for each
 * expression of the body in tree order. The form `c_oracle --bodies` prints. */
void ms_dump_module_bodies(MsBuf *out, const MsCheck *c, MsModId m, const bool *declined);
/* The functions the C passes checked, each with the diagnostics inside it. */
void ms_dump_module_ownership(MsBuf *out, const MsCheck *c, MsModId m);
/* `fn L:C` and the `edge NAME L:C` lines of each checked function and constant, as `c_oracle --effects`. */
void ms_dump_module_effects(MsBuf *out, const MsCheck *c, MsModId m, MsStr text);

/* The module's fact model as JSON (see compiler/src/check/dump_facts.c); `text` is its source, and the
 * bodies must have been checked for the effect columns. */
void ms_dump_module_facts(MsBuf *out, MsCheck *c, MsModId m, MsStr text);

/* Helpers the fact writers share (dump_facts.c, dump_sites.c). */
bool ms_facts_is_std(const MsCheck *c, MsModId module);              /* a bundled standard-library module */
void ms_facts_put_json(MsBuf *out, const char *text, size_t len); /* a JSON string, html-safe like the Rust writer */
const char *ms_facts_kind_of(const MsDecl *d);                    /* the entity kind: `fn`, `constant`, `impl`, ... */
void ms_facts_put_impl_name(MsBuf *out, const MsNames *names, const MsDecl *d); /* `Contract for Type`, or `Type` */

/* The call sites and flow of the callables of one module (dump_sites.c): what `inspect` records as call targets
 * and what `flow.rs` turns into steps. Each call fills `external` with the JSON array of the targets that are not
 * project entities and `flow` with the JSON array of steps. False when the checker did not keep the body, so
 * neither is complete; both are then `[]`. */
typedef struct MsSites MsSites;
MsSites *ms_sites_new(MsCheck *c, MsModId m, MsStr text);
void ms_sites_free(MsSites *s);
bool ms_sites_decl(MsSites *s, const MsDecl *d, MsBuf *external, MsBuf *flow);
bool ms_sites_method(MsSites *s, const MsDecl *impl, const MsMethod *method, MsBuf *external, MsBuf *flow);

/* The fact model of a whole project: the entities and imports of each module `mods[i]` (source `texts[i]`),
 * in one document, so keys and files carry the modules' own names. */
void ms_dump_project_facts(MsBuf *out, MsCheck *c, const MsModId *mods, const MsStr *texts, uint32_t count);

/* `{"nodes": [{"id", "kind"}]}`: the type kind of each expression the checker typed, by node id. */
void ms_dump_module_nodes(MsBuf *out, const MsCheck *c, MsModId m);

#endif
