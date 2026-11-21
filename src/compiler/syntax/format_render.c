/* syntax/format_render.c: rendering the group tree flat, packed or one item per line. */
#include "compiler/syntax/format_layout.h"
#include "compiler/syntax/walk.h"

/* ---- rendering ---- */

/* A line starting with `.` after a flow step applies to the whole flow so far. Joined onto the
 * previous line it must read `| .name(...)`, since `step.name` would instead select a member of the
 * step. */
typedef struct FlowPrefix {
  int previous; /* token kind, or -1 */
  bool has_pipe;
} FlowPrefix;

static bool flow_advance(FlowPrefix *flow, const Node *node, uint32_t last_line) {
  const bool joined = node->tok.kind == MS_T_Dot && last_line != 0 && last_line != node->tok.pos.line &&
                      flow->has_pipe && flow->previous != MS_T_Pipe && flow->previous != MS_T_Try;
  // Only preceding code in the current comma-separated item contributes.
  if (node->group < 0 && node->tok.kind == MS_T_Comma) {
    flow->previous = -1;
    flow->has_pipe = false;
  } else if (!fmt_layout_token((MsTok)node->tok.kind) && node->tok.kind != MS_T_Comment) {
    flow->previous = node->tok.kind;
    flow->has_pipe = flow->has_pipe || node->tok.kind == MS_T_Pipe;
  }
  return joined;
}

/* The `.` of `?.`: a line cannot start with `?.`, so a chain never breaks there. */
static bool lay_optional_dot(Nodes nodes, size_t index) {
  return nodes.ptr[index].tok.kind == MS_T_Dot && index > 0 && nodes.ptr[index - 1].tok.kind == MS_T_Question;
}

static void lay_flat(const Layout *l, Nodes nodes, MsStrBuild *out) {
  const size_t start = ms_strbuild_length(out);
  uint32_t last_line = 0;
  FlowPrefix flow = {.previous = -1};
  for (size_t i = 0; i < nodes.len; i++) {
    const Node *node = &nodes.ptr[i];
    const bool joined = flow_advance(&flow, node, last_line);
    if (lay_is_trivia(node)) {
      continue;
    }
    if (joined) {
      ms_strbuild_append_text(out, " | ");
    } else if (ms_strbuild_length(out) != start && node->space) {
      ms_strbuild_append_byte(out, (uint8_t)(' '));
    }
    last_line = node->group >= 0 ? lay_group_at(l, (size_t)node->group)->close.pos.line : node->tok.pos.line;
    if (node->group >= 0) {
      const Group *g = lay_group_at(l, (size_t)node->group);
      fmt_put(out, lay_text(l, &g->open));
      lay_flat(l, g->nodes, out);
      fmt_put(out, lay_text(l, &g->close));
    } else {
      fmt_put(out, lay_text(l, &node->tok));
    }
  }
}

/* The flat text of `nodes` as a string in the arena. */
static MsSpan lay_flat_text(const Layout *l, Nodes nodes) {
  MsStrBuild out = {0};
  lay_flat(l, nodes, &out);
  return fmt_take(l->fmt, &out);
}

/* The width in scalars of the flat text of `nodes`. */
static size_t lay_flat_width(const Layout *l, Nodes nodes) {
  MsStrBuild out = {0};
  lay_flat(l, nodes, &out);
  const size_t width = fmt_chars(fmt_tail(&out, 0));
  ms_strbuild_free(&out);
  return width;
}

/* Splits at the first-level `separator` tokens: slices of `nodes`, pushed on `parts` as Nodes. */
static bool lay_separator_matches(MsTok kind, MsTok separator) {
  switch (separator) {
  case MS_T_Plus:
  case MS_T_Minus:
    return kind == MS_T_Plus || kind == MS_T_Minus;
  case MS_T_Star:
  case MS_T_Slash:
  case MS_T_Percent:
    return kind == MS_T_Star || kind == MS_T_Slash || kind == MS_T_Percent;
  default:
    return kind == separator;
  }
}

static void lay_split(Nodes nodes, MsTok separator, NodesList *parts) {
  parts->len = 0;
  size_t start = 0;
  for (size_t i = 0; i < nodes.len; i++) {
    const Node *node = &nodes.ptr[i];
    if (node->group >= 0 || !lay_separator_matches((MsTok)node->tok.kind, separator) ||
        lay_optional_dot(nodes, i)) {
      continue;
    }
    size_t end = i;
    if (separator == MS_T_Comma) {
      end++;
      // A trailing comment explains the item before this comma.
      while (end < nodes.len && nodes.ptr[end].tok.kind == MS_T_Comment &&
             nodes.ptr[end].tok.pos.line == node->tok.pos.line) {
        end++;
      }
    }
    if (end > start) {
      nodes_list_push(parts, ((Nodes){nodes.ptr + start, end - start}));
    }
    start = end;
  }
  if (start < nodes.len) {
    nodes_list_push(parts, ((Nodes){nodes.ptr + start, nodes.len - start}));
  }
}

/* Pack atomic list values into rows using their printed width. */
static bool lay_simple_items(const Nodes *parts, size_t count) {
  for (size_t p = 0; p < count; p++) {
    size_t values = 0;
    for (size_t i = 0; i < parts[p].len; i++) {
      const Node *node = &parts[p].ptr[i];
      if (fmt_layout_token((MsTok)node->tok.kind) || node->tok.kind == MS_T_Comma) {
        continue;
      }
      if (node->group >= 0 || node->tok.kind == MS_T_Comment) {
        return false;
      }
      values++;
    }
    if (values != 1) {
      return false;
    }
  }
  return count > 1;
}

/* The part of a source line after a parameter list that belongs to the same signature: the return
 * type, up to the suite colon, or up to the comma or closing delimiter that ends an enclosing
 * parameter. */
static MsSpan lay_signature_tail(MsSpan tail) {
  int depth = 0;
  for (size_t i = 0; i < tail.len; i++) {
    const char b = (char)tail.ptr[i];
    if (b == '(' || b == '[' || b == '{') {
      depth++;
    } else if (b == ')' || b == ']' || b == '}') {
      if (depth == 0) {
        return fmt_slice(tail, 0, i);
      }
      depth--;
    } else if ((b == ':' || b == ',') && depth == 0) {
      return fmt_slice(tail, 0, i);
    }
  }
  return tail;
}

/* Drops an authored trailing comma when the group has no comments or suites, so a group that
 * collapses onto one line reads cleanly. */
static Nodes lay_trim_trailing_comma(Nodes nodes) {
  ptrdiff_t last = (ptrdiff_t)nodes.len - 1;
  while (last >= 0 && fmt_layout_token((MsTok)nodes.ptr[last].tok.kind)) {
    last--;
  }
  if (last < 0 || nodes.ptr[last].group >= 0 || nodes.ptr[last].tok.kind != MS_T_Comma) {
    return nodes;
  }
  for (size_t i = 0; i < nodes.len; i++) {
    if (nodes.ptr[i].tok.kind == MS_T_Comment) {
      return nodes;
    }
  }
  return (Nodes){nodes.ptr, (size_t)last};
}

/* The binding level of the operator at nodes[index] (pipe 0, `or` 1, ... member dot 6), or -1 when the
 * node is not one the layout breaks at. */
static int lay_precedence(Nodes nodes, size_t index) {
  switch ((MsTok)nodes.ptr[index].tok.kind) {
  case MS_T_Pipe:
    return 0;
  case MS_T_Or:
    return 1;
  case MS_T_And:
    return 2;
  case MS_T_EqEq:
  case MS_T_NotEq:
  case MS_T_Lt:
  case MS_T_Gt:
  case MS_T_Le:
  case MS_T_Ge:
    return 3;
  case MS_T_Plus:
  case MS_T_Minus:
    return 4;
  case MS_T_Star:
  case MS_T_Slash:
  case MS_T_Percent:
    return 5;
  case MS_T_Dot:
    return lay_optional_dot(nodes, index) ? -1 : 6;
  default:
    return -1;
  }
}

/* The operator the layout breaks at: the lowest precedence one among the first-level nodes, and
 * how many of it there are. -1 for none. */
static int lay_layout_operators(Nodes nodes, size_t *count_out) {
  int selected = -1;
  int level = 7;
  size_t count = 0;
  for (size_t index = 0; index < nodes.len; index++) {
    const Node *node = &nodes.ptr[index];
    if (node->tok.kind == MS_T_Newline || node->tok.kind == MS_T_Fn) {
      *count_out = 0;
      return -1; // operators here belong to a callable body or type
    }
    if (node->group >= 0) {
      continue;
    }
    const int p = lay_precedence(nodes, index);
    if (p < 0) {
      continue;
    }
    if (p < level) {
      selected = node->tok.kind;
      level = p;
      count = 1;
    } else if (p == level) {
      count++;
    }
  }
  *count_out = count;
  return selected;
}

static void lay_item(const Layout *l, Nodes nodes, size_t indent, MsStrBuild *out);

/* The items of a broken group, one per line, with a trailing comma when `trailing`. */
static void lay_group_items(const Layout *l, const Group *g, Nodes nodes, const Nodes *parts, size_t nparts,
                            bool trailing, size_t indent, MsStrBuild *out) {
  // A comma after a callback body would belong to the body.
  for (size_t i = 0; i < nodes.len; i++) {
    trailing = trailing && nodes.ptr[i].tok.kind != MS_T_Comment && nodes.ptr[i].tok.kind != MS_T_Fn;
  }
  for (size_t i = 0; i < nparts; i++) {
    const size_t start = ms_strbuild_length(out);
    ms_strbuild_append_byte(out, (uint8_t)('\n'));
    lay_item(l, parts[i], indent + 4, out);
    if (ms_strbuild_length(out) == start + 1) {
      out->bytes.len = start;
    } else if (trailing && i + 1 == nparts) {
      bool has_layout = false;
      for (size_t k = 0; k < parts[i].len; k++) {
        has_layout = has_layout || fmt_layout_token((MsTok)parts[i].ptr[k].tok.kind);
      }
      if (!has_layout) {
        ms_strbuild_append_byte(out, (uint8_t)(','));
      }
    }
  }
  ms_strbuild_append_byte(out, (uint8_t)('\n'));
  fmt_spaces(out, indent);
  fmt_put(out, lay_text(l, &g->close));
}

/* The width after a group's closing delimiter that shares its last line. */
static size_t lay_suffix_width(const Layout *l, const Group *g, size_t following) {
  if (!g->parameters) {
    return following;
  }
  const MsSpan line = l->lines[g->close.pos.line - 1];
  const size_t from = g->close.pos.column - 1 + (g->close.hi - g->close.lo);
  // A callback body and enclosing arguments do not belong to its signature, and neither do
  // sibling parameters after a function-typed parameter.
  return from <= line.len ? fmt_chars(lay_signature_tail(fmt_slice(line, from, line.len))) : 0;
}

static void lay_sequence(const Layout *l, Nodes nodes, size_t indent, size_t column, bool prefix,
                         MsStrBuild *out);

/* Writes the group on one line when its contents lay out without a break: a child's complexity
 * or width can expand the containing argument. */
static bool lay_try_one_line(const Layout *l, const Group *g, Nodes nodes, size_t indent, size_t column,
                             MsStrBuild *out) {
  MsStrBuild trial = {0};
  lay_sequence(l, nodes, indent, column + (g->open.hi - g->open.lo), false, &trial);
  const bool one_line = fmt_find_byte(fmt_tail(&trial, 0), '\n') == FMT_NONE;
  if (one_line) {
    fmt_put(out, lay_text(l, &g->open));
    fmt_put(out, fmt_tail(&trial, 0));
    fmt_put(out, lay_text(l, &g->close));
  }
  ms_strbuild_free(&trial);
  return one_line;
}

/* Width of the text after a group on its line, up to the next group that has its own continuation
 * boundary: its contents must not force this group (such as a list before a map callback) to
 * expand as well. */
size_t lay_following_width(const Layout *l, Nodes rest, bool clause) {
  NodeList tail = {0};
  for (size_t i = 0; i < rest.len; i++) {
    Node next = rest.ptr[i];
    if (next.tok.kind == MS_T_Newline || next.tok.kind == MS_T_Comment ||
        (clause && next.tok.kind == MS_T_Colon)) {
      break;
    }
    if (next.group >= 0) {
      const Group *ng = lay_group_at(l, (size_t)next.group);
      if (ng->nodes.len != 0 && !(clause && ng->nodes.len <= 2)) {
        next.group = -1;
        node_list_push(&tail, next);
        break;
      }
    }
    node_list_push(&tail, next);
  }
  const Nodes nodes = {tail.ptr, tail.len};
  size_t following = lay_flat_width(l, nodes);
  if (nodes.len > 0 && nodes.ptr[0].space) {
    following++;
  }
  node_list_free(&tail);
  return following;
}

/* An item's enclosing delimiters already allow continuation lines. Break its operators directly
 * rather than inserting another pair of parentheses. */
static void lay_item(const Layout *l, Nodes nodes, size_t indent, MsStrBuild *out) {
  size_t count;
  const int breaker = lay_layout_operators(nodes, &count);
  if (breaker < 0) {
    lay_sequence(l, nodes, indent, indent, true, out);
    return;
  }
  MsStrBuild text = {0};
  lay_sequence(l, nodes, indent, indent, true, &text);
  bool long_line = false;
  size_t start = 0;
  const MsSpan rendered = ms_strbuild_span(&text);
  for (size_t i = 0; i <= rendered.len; i++) {
    if (i == rendered.len || rendered.ptr[i] == '\n') {
      long_line = long_line || fmt_chars(fmt_slice(rendered, start, i)) > FMT_WIDTH;
      start = i + 1;
    }
  }
  if (!long_line || (breaker == MS_T_Dot && count < 2) || fmt_is_comparison((MsTok)breaker)) {
    fmt_put(out, fmt_tail(&text, 0)); // keep comparison operands together
    ms_strbuild_free(&text);
    return;
  }
  ms_strbuild_free(&text);
  NodesList parts = {0};
  lay_split(nodes, (MsTok)breaker, &parts);
  const Nodes *list = parts.ptr;
  for (size_t index = 0; index < parts.len; index++) {
    if (index > 0) {
      ms_strbuild_append_byte(out, (uint8_t)('\n'));
    }
    lay_sequence(l, list[index], indent, indent, true, out);
  }
  nodes_list_free(&parts);
}

static void lay_packed(const Layout *l, const Group *g, const Nodes *parts, size_t nparts, size_t indent,
                       MsStrBuild *out) {
  fmt_put(out, lay_text(l, &g->open));
  size_t column = 0;
  for (size_t i = 0; i < nparts; i++) {
    const MsSpan text = lay_flat_text(l, parts[i]);
    const size_t width = fmt_chars(text);
    if (column == 0 || column + 1 + width > FMT_WIDTH) {
      ms_strbuild_append_byte(out, (uint8_t)('\n'));
      fmt_spaces(out, indent + 4);
      column = indent + 4;
    } else {
      ms_strbuild_append_byte(out, (uint8_t)(' '));
      column += 1;
    }
    fmt_put(out, text);
    column += width;
  }
  ms_strbuild_append_byte(out, (uint8_t)('\n'));
  fmt_spaces(out, indent);
  fmt_put(out, lay_text(l, &g->close));
}

static bool lay_has_comment(Nodes nodes) {
  for (size_t i = 0; i < nodes.len; i++) {
    if (nodes.ptr[i].tok.kind == MS_T_Comment) {
      return true;
    }
  }
  return false;
}

/* The operator a group breaks at, or -1. `*flow` is set for a long pipe flow, which breaks at each pipe. */
static int lay_group_breaker(const Group *g, Nodes nodes, MsSpan flat, size_t column, bool *flow) {
  size_t count;
  int breaker = lay_layout_operators(nodes, &count);
  if (g->items || (breaker == MS_T_Dot && count < 2)) {
    breaker = -1;
  }
  if (breaker >= 0 && fmt_is_comparison((MsTok)breaker)) {
    breaker = -1; // keep each comparison together as one operand
  }
  // A flow of three or more stages that is not short reads one stage per line.
  size_t pipes = 0;
  for (size_t i = 0; i < nodes.len; i++) {
    pipes += nodes.ptr[i].group < 0 && nodes.ptr[i].tok.kind == MS_T_Pipe;
  }
  *flow = !g->callee && !g->parameters && g->open.kind == MS_T_LParen && pipes >= 2 &&
          column + fmt_chars(flat) > FMT_FLOW_WIDTH;
  return *flow ? MS_T_Pipe : breaker;
}

void lay_group(const Layout *l, size_t gid, size_t indent, size_t column, size_t following, MsStrBuild *out) {
  const Group *g = lay_group_at(l, gid);
  const Nodes nodes = lay_trim_trailing_comma(g->nodes);
  MsStrBuild flat_buf = {0};
  fmt_put(&flat_buf, lay_text(l, &g->open));
  lay_flat(l, nodes, &flat_buf);
  fmt_put(&flat_buf, lay_text(l, &g->close));
  const MsSpan flat = fmt_take(l->fmt, &flat_buf);
  const size_t suffix = lay_suffix_width(l, g, following);
  bool force = g->force || column + fmt_chars(flat) + suffix > FMT_WIDTH;
  bool force_flow = false;
  int breaker = lay_group_breaker(g, nodes, flat, column, &force_flow);
  force = force || force_flow || lay_has_comment(nodes);
  const bool flow = force_flow;
  NodesList parts_buf = {0};
  lay_split(nodes, MS_T_Comma, &parts_buf);
  size_t nparts = parts_buf.len;
  if (nparts == 0) {
    fmt_put(out, flat);
    nodes_list_free(&parts_buf);
    return;
  }
  const bool comma_separated = nparts > 1;
  if (!force) {
    if (lay_try_one_line(l, g, nodes, indent, column, out)) {
      nodes_list_free(&parts_buf);
      return;
    }
    force = true;
  }
  if (force && nparts == 1 && breaker >= 0) {
    lay_split(nodes, (MsTok)breaker, &parts_buf);
    nparts = parts_buf.len;
  }
  const Nodes *parts = parts_buf.ptr;
  if (g->list && !g->force && lay_simple_items(parts, nparts)) {
    lay_packed(l, g, parts, nparts, indent, out);
    nodes_list_free(&parts_buf);
    return;
  }
  // Keep an opener's trailing comment on its original line.
  fmt_put(out, lay_text(l, &g->open));
  if (nodes.len > 0 && nodes.ptr[0].tok.kind == MS_T_Comment &&
      nodes.ptr[0].tok.pos.line == g->open.pos.line) {
    ms_strbuild_append_text(out, "  ");
    fmt_put(out, lay_text(l, &nodes.ptr[0].tok));
    const Nodes remaining = {nodes.ptr + 1, nodes.len - 1};
    lay_split(remaining, MS_T_Comma, &parts_buf);
    nparts = parts_buf.len;
    if (nparts == 1 && breaker >= 0) {
      lay_split(remaining, (MsTok)breaker, &parts_buf);
      nparts = parts_buf.len;
    }
    parts = parts_buf.ptr;
  }
  const bool trailing = comma_separated && !flow && (g->items || g->parameters || g->list) &&
                        (g->open.kind == MS_T_LParen || g->open.kind == MS_T_LBracket);
  lay_group_items(l, g, nodes, parts, nparts, trailing, indent, out);
  nodes_list_free(&parts_buf);
}

/* The writer of `sequence`: output text plus the column and indentation of its last line. */
typedef struct SeqWriter {
  MsStrBuild *out;
  size_t start;
  size_t column;
  size_t line_indent;
} SeqWriter;

static void seq_measure_from(SeqWriter *w, size_t start) {
  const MsSpan text = fmt_tail(w->out, start);
  const size_t newline = fmt_rfind_byte(text, '\n');
  if (newline != FMT_NONE) {
    const MsSpan tail = fmt_slice(text, newline + 1, text.len);
    w->column = fmt_chars(tail);
    w->line_indent = fmt_indent_of(tail);
  } else {
    w->column += fmt_chars(text);
  }
}

static void seq_write(SeqWriter *w, MsSpan text) {
  const size_t start = ms_strbuild_length(w->out);
  fmt_put(w->out, text);
  seq_measure_from(w, start);
}

static bool seq_is_empty(const SeqWriter *w) {
  return ms_strbuild_length(w->out) == w->start;
}

static void lay_sequence(const Layout *l, Nodes nodes, size_t indent, size_t column, bool prefix,
                         MsStrBuild *out) {
  SeqWriter w = {.out = out, .start = ms_strbuild_length(out), .column = column, .line_indent = indent};
  int64_t first_indent = 0;
  for (size_t i = 0; i < nodes.len; i++) {
    // A leading comment may sit off the code's indentation.
    if (!lay_is_trivia(&nodes.ptr[i])) {
      first_indent = (int64_t)lay_line_indent(l, nodes.ptr[i].tok.pos.line);
      break;
    }
  }
  bool pending = false;
  bool suite = false;
  uint32_t last_line = 0;
  FlowPrefix flow = {.previous = -1};
  for (size_t index = 0; index < nodes.len; index++) {
    const Node *node = &nodes.ptr[index];
    const bool joined = flow_advance(&flow, node, last_line);
    if (fmt_layout_token((MsTok)node->tok.kind)) {
      pending = pending || node->tok.kind == MS_T_Newline;
      suite = suite || node->tok.kind == MS_T_Newline;
      continue;
    }
    const bool comment = node->tok.kind == MS_T_Comment;
    if (comment && last_line != node->tok.pos.line && !seq_is_empty(&w)) {
      pending = true;
    }
    if (!seq_is_empty(&w) && !pending && !suite && last_line != 0 && last_line != node->tok.pos.line) {
      // An original line break joins this line to the output line. A suite opened here is
      // indented relative to the line that holds its header.
      first_indent = (int64_t)lay_line_indent(l, node->tok.pos.line);
    }
    if (seq_is_empty(&w) || pending) {
      if (!seq_is_empty(&w)) {
        seq_write(&w, ms_span_of_text("\n"));
        for (uint32_t line = last_line + 1; line < node->tok.pos.line; line++) {
          if (fmt_is_blank(l->lines[line - 1])) {
            seq_write(&w, ms_span_of_text("\n"));
            break;
          }
        }
      }
      w.line_indent = indent;
      if (suite) {
        const int64_t shifted =
            (int64_t)indent + (int64_t)lay_line_indent(l, node->tok.pos.line) - first_indent;
        w.line_indent = shifted > 0 ? (size_t)shifted : 0;
      }
      if (prefix || !seq_is_empty(&w)) {
        const size_t start = ms_strbuild_length(out);
        fmt_spaces(out, w.line_indent);
        seq_measure_from(&w, start);
      }
    } else if (comment) {
      seq_write(&w, ms_span_of_text("  "));
    } else if (joined) {
      seq_write(&w, ms_span_of_text(" | "));
    } else if (node->space) {
      seq_write(&w, ms_span_of_text(" "));
    }
    if (node->group >= 0) {
      const Nodes rest = {nodes.ptr + index + 1, nodes.len - index - 1};
      const size_t following = lay_following_width(l, rest, false);
      const size_t start = ms_strbuild_length(out);
      lay_group(l, (size_t)node->group, w.line_indent, w.column, following, out);
      seq_measure_from(&w, start);
      last_line = lay_group_at(l, (size_t)node->group)->close.pos.line;
    } else {
      seq_write(&w, lay_text(l, &node->tok));
      last_line = node->tok.pos.line;
    }
    pending = comment;
  }
}
