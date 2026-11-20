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

/* The module's fact model as JSON (see compiler/src/check/dump_facts.c). */
void ms_dump_module_facts(MsBuf *out, const MsCheck *c, MsModId m);

/* `{"nodes": [{"id", "kind"}]}`: the type kind of each expression the checker typed, by node id. */
void ms_dump_module_nodes(MsBuf *out, const MsCheck *c, MsModId m);

#endif
