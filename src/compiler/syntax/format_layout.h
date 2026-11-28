/* syntax/format_layout.h: the group tree of the expression layout pass and what its files share.
 * Private to the formatter. */
#ifndef MS_SYNTAX_FORMAT_LAYOUT_H
#define MS_SYNTAX_FORMAT_LAYOUT_H

#include "compiler/syntax/format_internal.h"

typedef struct Node {
  MsToken tok;
  int32_t group; /* index into the layout's groups, or -1 */
  bool space;
} Node;
MS_LIST_DEFINE(NodeList, node_list, Node)

typedef struct Nodes {
  const Node *ptr;
  size_t len;
} Nodes;
MS_LIST_DEFINE(NodesList, nodes_list, Nodes)

typedef struct Group {
  MsToken open, close;
  Nodes nodes;
  bool force;
  bool parameters;
  bool items;
  bool callee; /* opened by a call, index or literal rather than by a bare parenthesis */
  bool list;
} Group;
MS_LIST_DEFINE(GroupList, group_list, Group)

typedef struct Layout {
  Fmt *fmt;
  MsArena *arena; /* the tree */
  MsSpan src;
  const MsSpan *lines;
  size_t nlines;
  GroupList groups;
  uint32_t *by_open; /* by offset of an opening token: group index + 1 */
  uint32_t *by_item; /* by offset of a group's first item: group index + 1 */
} Layout;

static inline Group *lay_group_at(const Layout *l, size_t gid) {
  return &((Group *)l->groups.ptr)[gid];
}

static inline MsSpan lay_text(const Layout *l, const MsToken *t) {
  return fmt_slice(l->src, t->lo, t->hi);
}

static inline bool lay_is_comment(const Node *n) {
  return n->tok.kind == MS_T_Comment;
}

static inline bool lay_is_trivia(const Node *n) {
  return fmt_layout_token((MsTok)n->tok.kind) || lay_is_comment(n);
}

static inline size_t lay_line_indent(const Layout *l, uint32_t line) {
  return fmt_indent_of(l->lines[line - 1]);
}

static inline uint32_t *lay_slot(const Layout *l, uint32_t *table, uint32_t offset) {
  return offset <= l->src.len ? &table[offset] : NULL;
}

static inline int32_t lay_lookup(const Layout *l, const uint32_t *table, uint32_t offset) {
  return offset <= l->src.len ? (int32_t)table[offset] - 1 : -1;
}

/* ---- shared by the layout files ---- */

bool fmt_group_statement_expressions(Fmt *f, MsSpan source, bool strip, MsSpan *out);
void lay_parameters(Layout *l, MsParams params);
size_t lay_following_width(const Layout *l, Nodes rest, bool clause);
MsToken *lay_layout_tokens(Layout *l, const MsToken *tokens, size_t ntokens, size_t *count);
Nodes lay_sequence_tree(Layout *l, const MsToken *tokens, size_t ntokens, size_t *at, TokenList *code,
                        int close_kind);
void lay_declaration(Layout *l, const MsDecl *d);
void lay_group(const Layout *l, size_t gid, size_t indent, size_t column, size_t following, MsStrBuild *out);

#endif
