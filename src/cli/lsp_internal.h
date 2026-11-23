/* cli/lsp_internal.h: the pieces of `ms lsp`, the language server: framed input and output, URIs, UTF-16 text
 * positions and the forgiving token scanner. Port of crates/ms-lsp/src/{transport,uri,text}.rs. */
#ifndef MS_CLI_LSP_INTERNAL_H
#define MS_CLI_LSP_INTERNAL_H

#include <stdio.h>

#include "base/list.h"
#include "base/strbuild.h"

/* ---- framing ---- */

typedef enum LspFrameStatus { LSP_FRAME_OK, LSP_FRAME_EOF, LSP_FRAME_FAILED } LspFrameStatus;

/* Reads one `Content-Length` frame into `body` (replacing its contents). On failure `error` names why. */
LspFrameStatus lsp_read_frame(FILE *input, MsStrBuild *body, const char **error);

/* Writes `body` as one frame and flushes. */
void lsp_write_frame(FILE *output, MsSpan body);

/* A JSON string literal as the server writes it: only `"`, `\` and control characters are escaped. */
void lsp_json_string(MsStrBuild *out, MsSpan text);

/* ---- URIs ---- */

bool lsp_uri_is_standard_library(MsSpan uri);
/* A `file:` URI that does not decode to a path. */
bool lsp_uri_is_malformed_file(MsSpan uri);
/* The path of a `file:` URI; any other URI is its own name. Appended to `out`. */
void lsp_uri_filename(MsSpan uri, MsStrBuild *out);
/* The `file:` URI of an absolute path. */
void lsp_file_uri(MsSpan path, MsStrBuild *out);

/* ---- text positions ---- */

typedef struct LspPosition {
  size_t line, character;
} LspPosition;

typedef struct LspRange {
  LspPosition start, end;
} LspRange;

size_t lsp_utf16_length(MsSpan bytes);
/* The position of a byte offset, clamped into the source. */
LspPosition lsp_position(MsSpan source, size_t offset);
/* The byte offset of a position. With `clamp`, a character past the end of a line or a line past the end of the document
 * clamps (a change range); otherwise it is refused, as is a position that splits a surrogate pair. */
bool lsp_offset(MsSpan source, LspPosition position, bool clamp, size_t *offset);
/* The range of the token containing `offset`, or an empty range at it. */
LspRange lsp_diagnostic_range(MsSpan source, size_t offset);

/* The byte offset of `name` as a token on the line after `offset` (a newline exactly at `offset` is skipped): where a
 * header's declared name is, whatever precedes it. */
bool lsp_header(MsSpan source, size_t offset, MsSpan name, size_t *at);

/* Whether the last token of `line` that is not a comment is `:`, which opens an indented suite. */
bool lsp_line_opens_suite(MsSpan line);

#endif
