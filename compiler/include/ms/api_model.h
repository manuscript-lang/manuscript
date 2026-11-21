/* The standard library's API model: every public module's declarations with their types, fields,
 * cases, operations and documentation, as the JSON the Rust `ms-tooling` `api_model` example
 * prints (crates/ms-tooling/src/guide/api.rs). `ms search_symbol` and the generated reference read it. */
#ifndef MS_API_MODEL_H
#define MS_API_MODEL_H

#include "ms/stdlib.h"

/* Appends the model of the loaded standard library (`ms_std_load`) to `out`: pretty-printed JSON with
 * two-space indents and `&`, `<`, `>` escaped, a modules array sorted by path. `files` are the same
 * files the library was loaded from, for their comments. */
void ms_api_model_json(MsBuf *out, MsCheck *c, const MsStdFile *files, uint32_t nfiles);

#endif
