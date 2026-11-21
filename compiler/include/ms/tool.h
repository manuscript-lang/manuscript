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

/* Block-comment byte ranges (start, end pairs) in the CRLF-normalised text, as MsLexed.blocks; empty
 * when the text does not lex. */
void ms_tool_lex_blocks(const ms_str *text, ms_list *out);

/* The token kind names, indexed by the `kind` column: "NAME", "STRING", "(", "fn", ... */
void ms_tool_token_kinds(ms_list *out);


/* Formats `text` (the source formatter, include/ms/format.h) into `out`. Status 0 is success; status 1
 * is the first syntax error: `code_out` holds its byte offset and `message_out` holds
 * "<code>\t<line>\t<column>\t<message>" (the stable diagnostic code, 1-based line and byte column).
 * Invalid UTF-8 reports offset 0 at line 1, column 1. */
uint8_t ms_tool_format(const ms_str *text, ms_str *out, int64_t *code_out, ms_str *message_out);

/* The `[dependencies]` of an ms.toml as rows `alias\turl\tkind\treference` (kind tag, sha or version; the reference is
 * the tag, the commit or the requirement), sorted by alias; path dependencies are left out. Status 0 is success;
 * status 1 is an error with the Rust driver's text in `message_out`; status 2 means the C reader does not cover the
 * manifest (the caller falls back to `ms`'s Rust reader), with what is missing in `message_out`. */
uint8_t ms_tool_dependencies(const ms_str *manifest, ms_list *out, ms_str *message_out);

/* The project an ms.toml describes (ms_project_read), as rows whose first field names the kind, in this order:
 * `root`, `file`, `name`, `source` and `entry` (a library has an empty entry) with one field each; `version` when
 * `[project] version` is set; `alias`, `embed` and `path` as `kind\tname\ttarget` (the target a canonical path),
 * `dep` as `dep\talias\turl\tkind\treference` (the row ms_tool_dependencies returns), `allow` as
 * `allow\tname\tpattern...` for `[effects]`, `effect` for each `[project] effects`, `workspace` when a `[workspace]`
 * table exists and `member` for each of its members as written. Status 0 is success; 1 is an error with the Rust
 * driver's text in `message_out`; 2 means the C reader does not cover the manifest. */
uint8_t ms_tool_project(const ms_str *manifest, ms_list *out, ms_str *message_out);

/* The files `ms fmt` formats for `target` (ms_project_format_paths): the file itself, or the modules of a directory or
 * of the project an ms.toml names, in order. Status 0 is success; 1 is an error with the Rust driver's text in
 * `message_out`; 2 means the C reader does not cover the target (a workspace root, a project with dependencies). */
uint8_t ms_tool_discover(const ms_str *target, ms_list *out, ms_str *message_out);

/* Resolves and fetches the dependencies of the project whose ms.toml is `manifest` (ms_install in ms/packages.h) and
 * writes ms.lock when it changed; `update` names the repositories to re-pick, `locked` fails instead of changing
 * ms.lock and `frozen` leaves it alone. Rows, in copy-id order, are `name\tspec\trevision\tstate\teffects`: the
 * alias that reaches the copy (else its id), `url#reference`, the full commit, `fetched`, `cached` (downloaded, but
 * the cache held the content) or `kept` (the locked copy was intact in the cache), and `[project] effects` joined by
 * spaces (`none` without any). Status 0 is success; 1 is an error with the Rust text in `message_out`; 2 means the C
 * reader does not cover the project (a workspace, a manifest form it lacks). */
uint8_t ms_tool_install(const ms_str *manifest, const ms_list *update, uint8_t locked, uint8_t frozen, ms_list *out, ms_str *message_out);

/* ---- syntax trees ---- */

/* A parsed module, kept in C. `extern type Tree` on the Manuscript side. A parse that fails still
 * yields a Tree: it has no nodes and holds the error. */
ms_object *ms_tool_parse(const ms_str *text);
/* The first syntax error's message, or "" when the parse succeeded. */
void ms_tool_tree_error(ms_object *tree, ms_str *out);
/* Its byte offset, line and column (0 when the parse succeeded). */
int64_t ms_tool_tree_error_offset(ms_object *tree);
int64_t ms_tool_tree_error_line(ms_object *tree);
int64_t ms_tool_tree_error_column(ms_object *tree);

/* The tree as MS_TOOL_NODE_WIDTH-integer records in preorder: kind, id, start offset/line/column,
 * end offset/line/column, flags, a, b, child count. The children of a record follow it, each with
 * its own children. `a` and `b` are indexes into `ms_tool_tree_names` (or -1) unless a kind says
 * otherwise; `flags` are the booleans and operator of the node. An absent optional child is a
 * `None` record; a list is a `List` record whose children are the elements. Each kind below:
 * `flags`, `a`, `b`, then the children in order.
 *   Module        a=import count, b=node count        imports, then declarations
 *   Import        a=name, b=path                      Pos (clause), Pos (name)
 *   Fn            1 export, 2 synthetic, 4 extern; a=name       TypeParams, Params, result, Body
 *   Const         a=name                              type, value, Pos (init)
 *   Type          8 opaque, 4 extern; a=name          TypeParams, Params (fields)
 *   Enum          a=name                              TypeParams, List of Case (a=name; Params)
 *   Alias         a=name                              TypeParams, List of target types
 *   Interface     a=name                              TypeParams, List of Method
 *   Impl          -                                   contract, receiver, TypeParams (bounds), Methods
 *   Test          16 bench; a=name text, b=per        Body
 *   Method        1 mutating, 2 consuming, 4 extern; a=name  Pos (var), List of receiver types,
 *                                                     TypeParams, Params, result, Body
 *   Param         1 mutable, 2 moving; a=name         type, default
 *   TypeParam     a=name                              List of bounds, default type
 *   TypeNamed     a=name                              List of arguments
 *   TypeFn        -                                   Params, result
 *   Number, Name  a=spelling        Bool 1=true       Member a=name: left
 *   Text          -                                   TextPart (1 interpolated; a=literal): the expression
 *   Apply         -                                   left, List of types, value
 *   Index, Binary 11/Binary: flags=operator           left, right        Probe, Unary: operand
 *   ListExpr      -                                   elements           Map: MapEntry (key, value)
 *   Lambda        -                                   Params, result, Body
 *   Call          -                                   callee, List of Arg (1 named; a=name): value
 *   Match         -                                   scrutinee, List of Arm (1 from if, 2 bare):
 *                                                     path, List of ArmBinding (a=name), Body, value
 *   PatName       a=name     PatList: patterns        PatType: PatField (a=name): pattern
 *   Bind          1 mutable, 2 has group (end=group)  pattern, type, value
 *   Assign        1 member target, 2 compound, op<<8; a=name   target, value
 *   If            1 mutable                           binding pattern, condition, Body, else Body
 *   While, For    For: a=name                         While: condition, Body; For: iterable, Body
 *   CallStmt, Return                                  expression
 * Operators: unary not, -, +, try (0..3); binary or, and, ==, !=, <, >, <=, >=, +, -, *, /, %. */
#define MS_TOOL_NODE_WIDTH 12
void ms_tool_tree_nodes(ms_object *tree, ms_list *out);
/* Every identifier and literal text the nodes name. */
void ms_tool_tree_names(ms_object *tree, ms_list *out);
/* The node kind names, indexed by the `kind` column. */
void ms_tool_node_kinds(ms_list *out);
/* The reserved words, in token order: `and` through `while`, without the `_` token. */
void ms_tool_keywords(ms_list *out);

/* ---- analysis (the language server) ---- */

/* Checks `text` as a module of its own (`extern type Analysis` on the Manuscript side) (a program that imports a project module is status 2: not covered yet) and
 * reports what the checker knows, keyed by the syntax-node ids of `ms_tool_tree_nodes` (`Syntax.id`), so a tool joins
 * them to a tree of the same text. the rows hold three counts (nodes, bindings, symbols) and then the rows:
 *   node, MS_TOOL_ANALYZE_NODE_WIDTH:     id, resolution (MsResolution), reference (binding, symbol, field, case or
 *                                         method id, -1 for none), type of the expression, type of the written type,
 *                                         symbol id of the function a call expression calls (-1 for none)
 *   binding, MS_TOOL_ANALYZE_BINDING_WIDTH: name, type, declaring node id, line, column, offset, role (MsBindRole),
 *                                         flags (1 mutable, 2 moving, 4 fed), reads
 *   symbol, MS_TOOL_ANALYZE_SYMBOL_WIDTH: id, name, kind (0 type, 1 fn, 2 alias), module path, 1 when declared in this
 *                                         text, 1 when exported, declaration node id (-1 for a primitive), offset, line,
 *                                         column, type
 * Every name, module path and type text is an index into the names (-1 for none); types print as source reads them.
 */
#define MS_TOOL_ANALYZE_NODE_WIDTH 6
#define MS_TOOL_ANALYZE_BINDING_WIDTH 9
#define MS_TOOL_ANALYZE_SYMBOL_WIDTH 11
ms_object *ms_tool_analyze(const ms_str *text);
/* 0 analysed, 1 syntax error, 2 not covered; the message of a status other than 0. */
uint8_t ms_tool_analysis_status(ms_object *analysis);
void ms_tool_analysis_message(ms_object *analysis, ms_str *out);
/* The counts and rows described above, and the name and type texts they index. */
void ms_tool_analysis_rows(ms_object *analysis, ms_list *out);
void ms_tool_analysis_names(ms_object *analysis, ms_list *out);

#endif
