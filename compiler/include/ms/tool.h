/* The tool interface: libms entry points that a Manuscript program calls through `extern fn`.
 *
 * Tools written in Manuscript (lint, docs, symbol search, ...) cannot hold a C pointer, so every
 * entry point takes text and returns flat tables: a `List[Int]` of fixed-width records, plus
 * `List[String]` where text is needed. Nothing here keeps state between calls. The Manuscript side
 * of each table (record width, column order) lives in `tools/ms/syntax.ms`; the two are one
 * contract. Signatures follow crates/ms-rt-abi/include/ms_abi.h. */
#ifndef MS_TOOL_H
#define MS_TOOL_H

#include <stdint.h>

#include "ms_abi.h"

/* Token record, MS_TOOL_TOKEN_WIDTH integers: kind, lo, hi (byte range in the CRLF-normalised
 * text), start offset/line/column, end offset/line/column (original-source coordinates). */
#define MS_TOOL_TOKEN_WIDTH 9

/* Lexes `text` into `out`. Status 0 is success; status 1 is the first lexical error, with its
 * message in `message_out`, and `code_out` holds its byte offset. */
uint8_t ms_tool_lex(const ms_str *text, ms_list *out, int64_t *code_out, ms_str *message_out);

/* The token kind names, indexed by the `kind` column: "NAME", "STRING", "(", "fn", ... */
void ms_tool_token_kinds(ms_list *out);

#endif
