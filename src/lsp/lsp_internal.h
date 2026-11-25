/* lsp/lsp_internal.h: the pieces of `ms lsp`, the language server: framed input and output, URIs, UTF-16 text
 * positions and the forgiving token scanner. */
#ifndef MS_CLI_LSP_INTERNAL_H
#define MS_CLI_LSP_INTERNAL_H

#include <stdio.h>

#include "base/arena.h"
#include "base/list.h"
#include "base/strbuild.h"
#include "tooling/json_value.h"

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
/* The module name of a `manuscript-stdlib:` URI. Both spellings name one module: the server writes
 * `manuscript-stdlib:///core.ms`, and a client that normalizes URIs (VS Code) sends back `manuscript-stdlib:/core.ms`. */
bool lsp_uri_standard_module(MsSpan uri, MsSpan *name);
/* Rewrites every `uri` member below `node` that names a bundled module to `manuscript-stdlib:///<module>`, the one
 * spelling the server writes, so a request from a client that normalizes URIs reaches each handler in that form. */
void lsp_normalize_uris(MsArena *arena, MsJson *node);
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

/* A range as the JSON object LSP carries. */
void lsp_json_range(MsStrBuild *out, LspRange range);

/* The position of a byte offset, clamped into the source. */
LspPosition lsp_position(MsSpan source, size_t offset);

/* The start offset of every line of a source, so that a pass asking for many positions finds each by binary search
 * instead of counting newlines from the top: `lsp_position` costs the offset, which made a pass over every token of a
 * file quadratic. */
typedef struct LspLines {
  MsSpan source;
  size_t *starts; /* owned; starts[0] is 0 */
  size_t count;
} LspLines;
void lsp_lines_init(LspLines *lines, MsSpan source);
void lsp_lines_free(LspLines *lines);
/* The same answer as `lsp_position(lines->source, offset)`. */
LspPosition lsp_lines_position(const LspLines *lines, size_t offset);
/* The byte offset of a position. With `clamp`, a character past the end of a line or a line past the end of the document
 * clamps (a change range); otherwise it is refused, as is a position that splits a surrogate pair. */
bool lsp_offset(MsSpan source, LspPosition position, bool clamp, size_t *offset);
/* The range of the token containing `offset`, or an empty range at it. */
LspRange lsp_diagnostic_range(MsSpan source, size_t offset);

/* The forgiving scanner: comments, strings, names (identifiers, keywords and numbers) and single characters. */
typedef enum LspTokenKind { LSP_TOKEN_COMMENT, LSP_TOKEN_STRING, LSP_TOKEN_NAME, LSP_TOKEN_CHAR } LspTokenKind;
typedef struct LspEditorToken {
  LspTokenKind kind;
  size_t start, end;
} LspEditorToken;
MS_LIST_DEFINE(LspTokenList, lsp_token_list, LspEditorToken)
void lsp_scan_tokens(MsSpan source, LspTokenList *tokens);
/* Whether the string token ends with its closing quotes (an unfinished one runs to the end of the text). */
bool lsp_literal_closed(MsSpan source, const LspEditorToken *token);

/* The byte offset of `name` as a token on the line after `offset` (a newline exactly at `offset` is skipped): where a
 * header's declared name is, whatever precedes it. */
bool lsp_header(MsSpan source, size_t offset, MsSpan name, size_t *at);

/* Whether the last token of `line` that is not a comment is `:`, which opens an indented suite. */
bool lsp_line_opens_suite(MsSpan line);

#endif
