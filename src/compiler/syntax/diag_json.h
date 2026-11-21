/* compiler/syntax/diag_json.h: the JSON text of diagnostics, byte for byte as crates/ms-cli writes it:
 * two-space indent, members in the order code, subcode, phase, message, position, end, fix. */
#ifndef MS_SYNTAX_DIAG_JSON_H
#define MS_SYNTAX_DIAG_JSON_H

#include "base/strbuild.h"
#include "compiler/syntax/pos.h"

/* A JSON string as the Rust CLI writes it: `<`, `>`, `&`, U+2028 and U+2029 escaped as \u00XX. */
void ms_json_string(MsStrBuild *out, MsSpan text);

/* `{file, line, column, offset}` as an object whose members sit `depth` levels deep. */
void ms_json_position(MsStrBuild *out, MsSpan file, MsPos pos, size_t depth);

/* A diagnostic object of `phase` in `file` with its braces at four spaces of indent (the entry of the
 * top-level `diagnostics` array). `code` is the family code; the sub-code is derived from the message. */
void ms_json_diag(MsStrBuild *out, MsSpan file, const char *phase, const MsDiag *diag);

#endif
