/* Expression layout for the formatter (crates/ms-syntax/src/format.rs, "Expression layout" and
 * "Statement grouping"): breaks long expressions at their delimiters and operators.
 *
 * The tokens of the text form a tree of delimited groups. A group that fits its line is printed
 * flat; otherwise it is printed one item per line, or packed into rows when its items are plain
 * values, with the closing delimiter on the group's own indentation. */
#include <stdlib.h>

#include "ms_rt/safe.h"
#include "ms/fixes.h"
#include "ms/walk.h"

#include "format_internal.h"

/* ---- the group tree ---- */

typedef struct Node {
    MsToken tok;
    int32_t group; /* index into the layout's groups, or -1 */
    bool space;
} Node;

typedef struct Nodes {
    const Node *ptr;
    size_t len;
} Nodes;

typedef struct Group {
    MsToken open, close;
    Nodes nodes;
    bool force;
    bool parameters;
    bool items;
    bool callee; /* opened by a call, index or literal rather than by a bare parenthesis */
    bool list;
} Group;

typedef struct Layout {
    Fmt *fmt;
    MsArena *arena; /* the tree */
    Str src;
    const Str *lines;
    size_t nlines;
    MsBuf groups;      /* Group */
    uint32_t *by_open; /* by offset of an opening token: group index + 1 */
    uint32_t *by_item; /* by offset of a group's first item: group index + 1 */
} Layout;

static Group *lay_group_at(const Layout *l, size_t gid) {
    return &((Group *)ms_buf_items(&l->groups))[gid];
}

static Str lay_text(const Layout *l, const MsToken *t) { return fmt_slice(l->src, t->lo, t->hi); }

static bool lay_is_comment(const Node *n) { return n->tok.kind == MS_T_Comment; }

static bool lay_is_trivia(const Node *n) { return fmt_layout_token((MsTok)n->tok.kind) || lay_is_comment(n); }

static size_t lay_line_indent(const Layout *l, uint32_t line) { return fmt_indent_of(l->lines[line - 1]); }

static uint32_t *lay_slot(const Layout *l, uint32_t *table, uint32_t offset) {
    return offset <= l->src.len ? &table[offset] : NULL;
}

static int32_t lay_lookup(const Layout *l, const uint32_t *table, uint32_t offset) {
    return offset <= l->src.len ? (int32_t)table[offset] - 1 : -1;
}

/* ---- which groups hold parameters ---- */

static void lay_parameters(Layout *l, MsParams params);

static void lay_type(Layout *l, const MsTypeRef *t) {
    if (t == NULL) {
        return;
    }
    if (t->kind == MS_TYPE_NAMED) {
        for (uint32_t i = 0; i < t->args.len; i++) {
            lay_type(l, t->args.ptr[i]);
        }
    } else {
        lay_parameters(l, t->params);
        lay_type(l, t->result);
    }
}

/* Offset of the token that starts `p`: its `var` or `move` keyword when it has one, else its name. */
static uint32_t lay_param_start(const Layout *l, const MsParam *p) {
    const char *keyword;
    if (p->moving) {
        keyword = "move";
    } else if (p->is_mutable) {
        keyword = "var";
    } else {
        return p->pos.offset;
    }
    const Str before = fmt_trim_end(fmt_slice(l->src, 0, p->pos.offset));
    if (!fmt_ends(before, keyword)) {
        return p->pos.offset;
    }
    return (uint32_t)(before.len - strlen(keyword));
}

static void lay_parameters(Layout *l, MsParams params) {
    if (params.len > 0) {
        const int32_t g = lay_lookup(l, l->by_item, lay_param_start(l, params.ptr[0]));
        if (g >= 0) {
            lay_group_at(l, (size_t)g)->parameters = true;
            lay_group_at(l, (size_t)g)->items = true;
        }
    }
    for (uint32_t i = 0; i < params.len; i++) {
        lay_type(l, params.ptr[i]->ty);
    }
}

static void lay_func(Layout *l, const MsFunc *f) {
    lay_parameters(l, f->params);
    lay_type(l, f->result);
}

static void lay_declaration(Layout *l, const MsDecl *d) {
    switch ((MsDeclKind)d->kind) {
    case MS_D_FN: lay_func(l, &d->u.fn); break;
    case MS_D_TYPE:
        for (uint32_t i = 0; i < d->u.type.fields.len; i++) {
            lay_type(l, d->u.type.fields.ptr[i]->ty);
        }
        break;
    case MS_D_ENUM:
        for (uint32_t i = 0; i < d->u.enumeration.cases.len; i++) {
            lay_parameters(l, d->u.enumeration.cases.ptr[i]->fields);
        }
        break;
    case MS_D_ALIAS:
        for (uint32_t i = 0; i < d->u.alias.targets.len; i++) {
            lay_type(l, d->u.alias.targets.ptr[i]);
        }
        break;
    case MS_D_INTERFACE:
        for (uint32_t i = 0; i < d->u.iface.methods.len; i++) {
            lay_func(l, &d->u.iface.methods.ptr[i]->func);
        }
        break;
    case MS_D_IMPL:
        for (uint32_t i = 0; i < d->u.impl.methods.len; i++) {
            lay_func(l, &d->u.impl.methods.ptr[i]->func);
        }
        break;
    case MS_D_CONST:
    case MS_D_TEST: break;
    }
}

/* ---- tokens and trees ---- */

/* The tokens with each line's trailing `//` comment added as a Comment token. Comments are
 * recovered only outside lexer tokens, so `//` and interpolation inside strings never become
 * formatter instructions. */
static MsToken *lay_layout_tokens(Layout *l, const MsToken *tokens, size_t ntokens, size_t *count) {
    uint32_t *last = MS_NEW_N(l->arena, uint32_t, l->nlines + 2);
    memset(last, 0, (l->nlines + 2) * sizeof *last);
    for (size_t i = 0; i < ntokens; i++) {
        if (!fmt_layout_token((MsTok)tokens[i].kind) && tokens[i].pos.line <= l->nlines) {
            last[tokens[i].pos.line] = tokens[i].pos.column - 1 + (tokens[i].hi - tokens[i].lo);
        }
    }
    MsBuf comments = {0};
    size_t offset = 0;
    for (size_t index = 0; index < l->nlines; index++) {
        const Str line = l->lines[index];
        const size_t tail = last[index + 1];
        if (tail <= line.len) {
            const size_t at = fmt_find(fmt_slice(line, tail, line.len), fmt_lit("//"));
            if (at != FMT_NONE) {
                const size_t column = tail + at;
                const Str text = fmt_trim_end_set(fmt_slice(line, column, line.len), " \t");
                MsToken comment = {.kind = MS_T_Comment, .lo = (uint32_t)(offset + column),
                                   .hi = (uint32_t)(offset + column + text.len)};
                comment.pos = (MsPos){(uint32_t)(offset + column), (uint32_t)index + 1, (uint32_t)column + 1};
                comment.end = comment.pos;
                MS_VEC_PUSH(comments, MsToken, comment);
            }
        }
        offset += line.len + 1;
    }
    const MsToken *found = ms_buf_items(&comments);
    const size_t nfound = MS_VEC_LEN(comments, MsToken);
    MsToken *result = MS_NEW_N(l->arena, MsToken, ntokens + nfound + 1);
    size_t n = 0;
    size_t next = 0;
    for (size_t i = 0; i < ntokens; i++) {
        while (next < nfound && found[next].pos.offset <= tokens[i].pos.offset) {
            result[n++] = found[next++];
        }
        result[n++] = tokens[i];
    }
    ms_buf_free(&comments);
    *count = n;
    return result;
}

static Nodes lay_sequence_tree(Layout *l, const MsToken *tokens, size_t ntokens, size_t *at, MsBuf *code,
                               int close_kind) {
    MsBuf nodes = {0};
    while (*at < ntokens && (int)tokens[*at].kind != close_kind) {
        const MsToken token = tokens[*at];
        (*at)++;
        Node node = {.tok = token, .group = -1, .space = false};
        if (!fmt_layout_token((MsTok)token.kind) && token.kind != MS_T_Comment) {
            MS_VEC_PUSH(*code, MsToken, token);
            const size_t n = MS_VEC_LEN(*code, MsToken);
            node.space = n > 1 && fmt_token_space(ms_buf_items(code), n - 1);
        }
        int end = -1;
        switch ((MsTok)token.kind) {
        case MS_T_LParen: end = MS_T_RParen; break;
        case MS_T_LBracket: end = MS_T_RBracket; break;
        case MS_T_LBrace: end = MS_T_RBrace; break;
        default: break;
        }
        if (end >= 0) {
            bool items = token.kind != MS_T_LParen;
            const size_t ncode = MS_VEC_LEN(*code, MsToken);
            if (ncode > 1) {
                const MsToken *before = &MS_VEC_AT(*code, MsToken, ncode - 2);
                items = items || before->kind == MS_T_Name || before->kind == MS_T_RParen ||
                        before->kind == MS_T_RBracket || before->kind == MS_T_Fn;
            }
            const Nodes children = lay_sequence_tree(l, tokens, ntokens, at, code, end);
            const MsToken close_token = tokens[*at];
            MS_VEC_PUSH(*code, MsToken, close_token);
            (*at)++;
            // Only a nested suite keeps a group multi-line; authored line breaks otherwise
            // collapse when the group fits.
            bool force = false;
            for (size_t i = 0; i < children.len; i++) {
                force = force || children.ptr[i].tok.kind == MS_T_Newline;
            }
            const size_t gid = MS_VEC_LEN(l->groups, Group);
            *lay_slot(l, l->by_open, token.pos.offset) = (uint32_t)gid + 1;
            for (size_t i = 0; i < children.len; i++) {
                if (!lay_is_trivia(&children.ptr[i])) {
                    uint32_t *slot = lay_slot(l, l->by_item, children.ptr[i].tok.pos.offset);
                    if (slot != NULL) {
                        *slot = (uint32_t)gid + 1;
                    }
                    break;
                }
            }
            const Group group = {.open = token, .close = close_token, .nodes = children, .force = force,
                                 .items = items, .callee = items};
            MS_VEC_PUSH(l->groups, Group, group);
            node.group = (int32_t)gid;
        }
        MS_VEC_PUSH(nodes, Node, node);
    }
    Nodes result = {0};
    result.len = MS_VEC_LEN(nodes, Node);
    Node *copy = MS_NEW_N(l->arena, Node, result.len + 1);
    if (result.len != 0) {
        memcpy(copy, nodes.data, result.len * sizeof(Node));
    }
    ms_buf_free(&nodes);
    result.ptr = copy;
    return result;
}

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

static void lay_flat(const Layout *l, Nodes nodes, MsBuf *out) {
    const size_t start = out->len;
    uint32_t last_line = 0;
    FlowPrefix flow = {.previous = -1};
    for (size_t i = 0; i < nodes.len; i++) {
        const Node *node = &nodes.ptr[i];
        const bool joined = flow_advance(&flow, node, last_line);
        if (lay_is_trivia(node)) {
            continue;
        }
        if (joined) {
            ms_buf_puts(out, " | ");
        } else if (out->len != start && node->space) {
            ms_buf_putc(out, ' ');
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
static Str lay_flat_text(const Layout *l, Nodes nodes) {
    MsBuf out = {0};
    lay_flat(l, nodes, &out);
    return fmt_take(l->fmt, &out);
}

/* The width in scalars of the flat text of `nodes`. */
static size_t lay_flat_width(const Layout *l, Nodes nodes) {
    MsBuf out = {0};
    lay_flat(l, nodes, &out);
    const size_t width = fmt_chars(fmt_tail(&out, 0));
    ms_buf_free(&out);
    return width;
}

/* Splits at the first-level `separator` tokens: slices of `nodes`, pushed on `parts` as Nodes. */
static bool lay_separator_matches(MsTok kind, MsTok separator) {
    switch (separator) {
    case MS_T_Plus:
    case MS_T_Minus: return kind == MS_T_Plus || kind == MS_T_Minus;
    case MS_T_Star:
    case MS_T_Slash:
    case MS_T_Percent: return kind == MS_T_Star || kind == MS_T_Slash || kind == MS_T_Percent;
    default: return kind == separator;
    }
}

static void lay_split(Nodes nodes, MsTok separator, MsBuf *parts) {
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
            MS_VEC_PUSH(*parts, Nodes, ((Nodes){nodes.ptr + start, end - start}));
        }
        start = end;
    }
    if (start < nodes.len) {
        MS_VEC_PUSH(*parts, Nodes, ((Nodes){nodes.ptr + start, nodes.len - start}));
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
static Str lay_signature_tail(Str tail) {
    int depth = 0;
    for (size_t i = 0; i < tail.len; i++) {
        const char b = tail.ptr[i];
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
        int p;
        switch ((MsTok)node->tok.kind) {
        case MS_T_Pipe: p = 0; break;
        case MS_T_Or: p = 1; break;
        case MS_T_And: p = 2; break;
        case MS_T_EqEq:
        case MS_T_NotEq:
        case MS_T_Lt:
        case MS_T_Gt:
        case MS_T_Le:
        case MS_T_Ge: p = 3; break;
        case MS_T_Plus:
        case MS_T_Minus: p = 4; break;
        case MS_T_Star:
        case MS_T_Slash:
        case MS_T_Percent: p = 5; break;
        case MS_T_Dot:
            if (lay_optional_dot(nodes, index)) {
                continue;
            }
            p = 6;
            break;
        default: continue;
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

static void lay_item(const Layout *l, Nodes nodes, size_t indent, MsBuf *out);

/* The items of a broken group, one per line, with a trailing comma when `trailing`. */
static void lay_group_items(const Layout *l, const Group *g, Nodes nodes, const Nodes *parts, size_t nparts,
                            bool trailing, size_t indent, MsBuf *out) {
    // A comma after a callback body would belong to the body.
    for (size_t i = 0; i < nodes.len; i++) {
        trailing = trailing && nodes.ptr[i].tok.kind != MS_T_Comment && nodes.ptr[i].tok.kind != MS_T_Fn;
    }
    for (size_t i = 0; i < nparts; i++) {
        const size_t start = out->len;
        ms_buf_putc(out, '\n');
        lay_item(l, parts[i], indent + 4, out);
        if (out->len == start + 1) {
            out->len = start;
        } else if (trailing && i + 1 == nparts) {
            bool has_layout = false;
            for (size_t k = 0; k < parts[i].len; k++) {
                has_layout = has_layout || fmt_layout_token((MsTok)parts[i].ptr[k].tok.kind);
            }
            if (!has_layout) {
                ms_buf_putc(out, ',');
            }
        }
    }
    ms_buf_putc(out, '\n');
    fmt_spaces(out, indent);
    fmt_put(out, lay_text(l, &g->close));
}

/* The width after a group's closing delimiter that shares its last line. */
static size_t lay_suffix_width(const Layout *l, const Group *g, size_t following) {
    if (!g->parameters) {
        return following;
    }
    const Str line = l->lines[g->close.pos.line - 1];
    const size_t from = g->close.pos.column - 1 + (g->close.hi - g->close.lo);
    // A callback body and enclosing arguments do not belong to its signature, and neither do
    // sibling parameters after a function-typed parameter.
    return from <= line.len ? fmt_chars(lay_signature_tail(fmt_slice(line, from, line.len))) : 0;
}

static void lay_sequence(const Layout *l, Nodes nodes, size_t indent, size_t column, bool prefix, MsBuf *out);

/* Writes the group on one line when its contents lay out without a break: a child's complexity
 * or width can expand the containing argument. */
static bool lay_try_one_line(const Layout *l, const Group *g, Nodes nodes, size_t indent, size_t column,
                             MsBuf *out) {
    MsBuf trial = {0};
    lay_sequence(l, nodes, indent, column + (g->open.hi - g->open.lo), false, &trial);
    const bool one_line = fmt_find_byte(fmt_tail(&trial, 0), '\n') == FMT_NONE;
    if (one_line) {
        fmt_put(out, lay_text(l, &g->open));
        fmt_put(out, fmt_tail(&trial, 0));
        fmt_put(out, lay_text(l, &g->close));
    }
    ms_buf_free(&trial);
    return one_line;
}

static void lay_group(const Layout *l, size_t gid, size_t indent, size_t column, size_t following, MsBuf *out);

/* Width of the text after a group on its line, up to the next group that has its own continuation
 * boundary: its contents must not force this group (such as a list before a map callback) to
 * expand as well. */
static size_t lay_following_width(const Layout *l, Nodes rest, bool clause) {
    MsBuf tail = {0};
    for (size_t i = 0; i < rest.len; i++) {
        Node next = rest.ptr[i];
        if (next.tok.kind == MS_T_Newline || next.tok.kind == MS_T_Comment || (clause && next.tok.kind == MS_T_Colon)) {
            break;
        }
        if (next.group >= 0) {
            const Group *ng = lay_group_at(l, (size_t)next.group);
            if (ng->nodes.len != 0 && !(clause && ng->nodes.len <= 2)) {
                next.group = -1;
                MS_VEC_PUSH(tail, Node, next);
                break;
            }
        }
        MS_VEC_PUSH(tail, Node, next);
    }
    const Nodes nodes = {ms_buf_items(&tail), MS_VEC_LEN(tail, Node)};
    size_t following = lay_flat_width(l, nodes);
    if (nodes.len > 0 && nodes.ptr[0].space) {
        following++;
    }
    ms_buf_free(&tail);
    return following;
}

/* An item's enclosing delimiters already allow continuation lines. Break its operators directly
 * rather than inserting another pair of parentheses. */
static void lay_item(const Layout *l, Nodes nodes, size_t indent, MsBuf *out) {
    size_t count;
    const int operator = lay_layout_operators(nodes, &count);
    if (operator < 0) {
        lay_sequence(l, nodes, indent, indent, true, out);
        return;
    }
    MsBuf text = {0};
    lay_sequence(l, nodes, indent, indent, true, &text);
    bool long_line = false;
    size_t start = 0;
    for (size_t i = 0; i <= text.len; i++) {
        if (i == text.len || text.data[i] == '\n') {
            long_line = long_line || fmt_chars(fmt_str(text.data + start, i - start)) > FMT_WIDTH;
            start = i + 1;
        }
    }
    if (!long_line || (operator == MS_T_Dot && count < 2) || fmt_is_comparison((MsTok)operator)) {
        fmt_put(out, fmt_tail(&text, 0)); // keep comparison operands together
        ms_buf_free(&text);
        return;
    }
    ms_buf_free(&text);
    MsBuf parts = {0};
    lay_split(nodes, (MsTok)operator, & parts);
    const Nodes *list = ms_buf_items(&parts);
    for (size_t index = 0; index < MS_VEC_LEN(parts, Nodes); index++) {
        if (index > 0) {
            ms_buf_putc(out, '\n');
        }
        lay_sequence(l, list[index], indent, indent, true, out);
    }
    ms_buf_free(&parts);
}

static void lay_packed(const Layout *l, const Group *g, const Nodes *parts, size_t nparts, size_t indent, MsBuf *out) {
    fmt_put(out, lay_text(l, &g->open));
    size_t column = 0;
    for (size_t i = 0; i < nparts; i++) {
        const Str text = lay_flat_text(l, parts[i]);
        const size_t width = fmt_chars(text);
        if (column == 0 || column + 1 + width > FMT_WIDTH) {
            ms_buf_putc(out, '\n');
            fmt_spaces(out, indent + 4);
            column = indent + 4;
        } else {
            ms_buf_putc(out, ' ');
            column += 1;
        }
        fmt_put(out, text);
        column += width;
    }
    ms_buf_putc(out, '\n');
    fmt_spaces(out, indent);
    fmt_put(out, lay_text(l, &g->close));
}

static void lay_group(const Layout *l, size_t gid, size_t indent, size_t column, size_t following, MsBuf *out) {
    const Group *g = lay_group_at(l, gid);
    const Nodes nodes = lay_trim_trailing_comma(g->nodes);
    MsBuf flat_buf = {0};
    fmt_put(&flat_buf, lay_text(l, &g->open));
    lay_flat(l, nodes, &flat_buf);
    fmt_put(&flat_buf, lay_text(l, &g->close));
    const Str flat = fmt_take(l->fmt, &flat_buf);
    const size_t suffix = lay_suffix_width(l, g, following);
    bool force = g->force || column + fmt_chars(flat) + suffix > FMT_WIDTH;
    size_t count;
    int operator = lay_layout_operators(nodes, &count);
    if (g->items || (operator == MS_T_Dot && count < 2)) {
        operator = -1;
    }
    if (operator >= 0 && fmt_is_comparison((MsTok)operator)) {
        operator = -1; // keep each comparison together as one operand
    }
    for (size_t i = 0; i < nodes.len; i++) {
        force = force || nodes.ptr[i].tok.kind == MS_T_Comment;
    }
    // A flow of three or more stages that is not short reads one stage per line.
    size_t pipes = 0;
    for (size_t i = 0; i < nodes.len; i++) {
        pipes += nodes.ptr[i].group < 0 && nodes.ptr[i].tok.kind == MS_T_Pipe;
    }
    const bool flow = !g->callee && !g->parameters && g->open.kind == MS_T_LParen && pipes >= 2 &&
                      column + fmt_chars(flat) > FMT_FLOW_WIDTH;
    if (flow) {
        force = true;
        operator = MS_T_Pipe;
    }
    MsBuf parts_buf = {0};
    lay_split(nodes, MS_T_Comma, &parts_buf);
    size_t nparts = MS_VEC_LEN(parts_buf, Nodes);
    if (nparts == 0) {
        fmt_put(out, flat);
        ms_buf_free(&parts_buf);
        return;
    }
    const bool comma_separated = nparts > 1;
    if (!force) {
        if (lay_try_one_line(l, g, nodes, indent, column, out)) {
            ms_buf_free(&parts_buf);
            return;
        }
        force = true;
    }
    if (force && nparts == 1 && operator >= 0) {
        lay_split(nodes, (MsTok)operator, &parts_buf);
        nparts = MS_VEC_LEN(parts_buf, Nodes);
    }
    const Nodes *parts = ms_buf_items(&parts_buf);
    if (g->list && !g->force && lay_simple_items(parts, nparts)) {
        lay_packed(l, g, parts, nparts, indent, out);
        ms_buf_free(&parts_buf);
        return;
    }
    // Keep an opener's trailing comment on its original line.
    fmt_put(out, lay_text(l, &g->open));
    if (nodes.len > 0 && nodes.ptr[0].tok.kind == MS_T_Comment && nodes.ptr[0].tok.pos.line == g->open.pos.line) {
        ms_buf_puts(out, "  ");
        fmt_put(out, lay_text(l, &nodes.ptr[0].tok));
        const Nodes remaining = {nodes.ptr + 1, nodes.len - 1};
        lay_split(remaining, MS_T_Comma, &parts_buf);
        nparts = MS_VEC_LEN(parts_buf, Nodes);
        if (nparts == 1 && operator >= 0) {
            lay_split(remaining, (MsTok)operator, &parts_buf);
            nparts = MS_VEC_LEN(parts_buf, Nodes);
        }
        parts = ms_buf_items(&parts_buf);
    }
    const bool trailing = comma_separated && !flow && (g->items || g->parameters || g->list) &&
                          (g->open.kind == MS_T_LParen || g->open.kind == MS_T_LBracket);
    lay_group_items(l, g, nodes, parts, nparts, trailing, indent, out);
    ms_buf_free(&parts_buf);
}

/* The writer of `sequence`: output text plus the column and indentation of its last line. */
typedef struct SeqWriter {
    MsBuf *out;
    size_t start;
    size_t column;
    size_t line_indent;
} SeqWriter;

static void seq_measure_from(SeqWriter *w, size_t start) {
    const Str text = fmt_tail(w->out, start);
    const size_t newline = fmt_rfind_byte(text, '\n');
    if (newline != FMT_NONE) {
        const Str tail = fmt_slice(text, newline + 1, text.len);
        w->column = fmt_chars(tail);
        w->line_indent = fmt_indent_of(tail);
    } else {
        w->column += fmt_chars(text);
    }
}

static void seq_write(SeqWriter *w, Str text) {
    const size_t start = w->out->len;
    fmt_put(w->out, text);
    seq_measure_from(w, start);
}

static bool seq_is_empty(const SeqWriter *w) { return w->out->len == w->start; }

static void lay_sequence(const Layout *l, Nodes nodes, size_t indent, size_t column, bool prefix, MsBuf *out) {
    SeqWriter w = {.out = out, .start = out->len, .column = column, .line_indent = indent};
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
                seq_write(&w, fmt_lit("\n"));
                for (uint32_t line = last_line + 1; line < node->tok.pos.line; line++) {
                    if (fmt_is_blank(l->lines[line - 1])) {
                        seq_write(&w, fmt_lit("\n"));
                        break;
                    }
                }
            }
            w.line_indent = indent;
            if (suite) {
                const int64_t shifted = (int64_t)indent + (int64_t)lay_line_indent(l, node->tok.pos.line) - first_indent;
                w.line_indent = shifted > 0 ? (size_t)shifted : 0;
            }
            if (prefix || !seq_is_empty(&w)) {
                const size_t start = out->len;
                fmt_spaces(out, w.line_indent);
                seq_measure_from(&w, start);
            }
        } else if (comment) {
            seq_write(&w, fmt_lit("  "));
        } else if (joined) {
            seq_write(&w, fmt_lit(" | "));
        } else if (node->space) {
            seq_write(&w, fmt_lit(" "));
        }
        if (node->group >= 0) {
            const Nodes rest = {nodes.ptr + index + 1, nodes.len - index - 1};
            const size_t following = lay_following_width(l, rest, false);
            const size_t start = out->len;
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

/* ---- callbacks and calls that carry suites ---- */

typedef struct SuiteCuts {
    Fmt *fmt;
    Str source;
    const MsToken *tokens;
    size_t ntokens;
    MsBuf cuts;   /* MsRange */
    bool *suites; /* by expression id: a lambda or match, or an expression holding one */
    MsBuf stack;  /* bool per expression being walked */
} SuiteCuts;

static void cuts_expr(void *ctx, const MsExpr *e) {
    SuiteCuts *s = ctx;
    MS_VEC_PUSH(s->stack, bool, e->kind == MS_E_LAMBDA || e->kind == MS_E_MATCH);
}

/* The number of tokens that start before `offset` (the tokens are in source order). */
static size_t lay_tokens_before(const MsToken *tokens, size_t ntokens, uint32_t offset) {
    size_t low = 0;
    size_t high = ntokens;
    while (low < high) {
        const size_t mid = low + (high - low) / 2;
        if (tokens[mid].pos.offset < offset) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    return low;
}

static void cuts_leave(void *ctx, const MsExpr *e) {
    SuiteCuts *s = ctx;
    const bool suite = MS_VEC_LAST(s->stack, bool);
    MS_VEC_POP(s->stack, bool);
    if (suite) {
        s->suites[e->id] = true;
        if (s->stack.len != 0) {
            MS_VEC_LAST(s->stack, bool) = true;
        }
    }
    if (e->kind != MS_E_CALL) {
        return;
    }
    for (uint32_t i = 0; i < e->u.call.args.len; i++) {
        const MsExpr *arg = e->u.call.args.ptr[i].value;
        if (arg->kind != MS_E_LAMBDA) {
            continue;
        }
        const MsStmts written = fmt_written_body(arg);
        if (written.len != 1 || written.ptr[0]->kind != MS_S_RETURN || written.ptr[0]->u.expr == NULL) {
            continue;
        }
        const MsStmt *body = written.ptr[0];
        // Nested suites retain indentation relative to this body.
        if (s->suites[body->u.expr->id]) {
            continue;
        }
        size_t start = lay_tokens_before(s->tokens, s->ntokens, body->pos.offset);
        const MsToken *colon = NULL;
        while (start > 0) {
            start--;
            if (!fmt_layout_token((MsTok)s->tokens[start].kind)) {
                colon = &s->tokens[start];
                break;
            }
        }
        if (colon == NULL) {
            continue;
        }
        const size_t from = colon->hi;
        const size_t to = body->pos.offset;
        // Interpolated expressions keep offsets local to their text, so the range can be reversed
        // or off a boundary.
        if (from > to || to > s->source.len ||
            (to < s->source.len && fmt_is_continuation(s->source.ptr[to])) ||
            (from < s->source.len && fmt_is_continuation(s->source.ptr[from]))) {
            continue;
        }
        const Str gap = fmt_slice(s->source, from, to);
        if (colon->kind == MS_T_Colon && fmt_contains(gap, "\n") && fmt_is_blank(gap)) {
            MS_VEC_PUSH(s->cuts, MsRange, ((MsRange){from, to}));
        }
    }
}

static int range_order(const void *a, const void *b) {
    const MsRange *x = a;
    const MsRange *y = b;
    if (x->start != y->start) {
        return x->start < y->start ? -1 : 1;
    }
    if (x->end != y->end) {
        return x->end < y->end ? -1 : 1;
    }
    return 0;
}

/* Joining an explicit return to its callback header preserves its meaning. A bare call cannot be
 * joined: an inline body would implicitly return it. */
static bool lay_compact_callback_suites(Fmt *f, const MsModule *module, const MsToken *tokens, size_t ntokens, Str source,
                                        Str *out) {
    MsArena scratch = {0};
    SuiteCuts s = {.fmt = f, .source = source, .tokens = tokens, .ntokens = ntokens};
    s.suites = MS_NEW_N(&scratch, bool, (size_t)module->node_count + 1);
    memset(s.suites, 0, ((size_t)module->node_count + 1) * sizeof *s.suites);
    const MsVisitor visitor = {.ctx = &s, .expr = cuts_expr, .leave_expr = cuts_leave};
    for (uint32_t i = 0; i < module->ndecls; i++) {
        ms_walk_decl(&visitor, module->decls[i]);
    }
    ms_arena_free(&scratch);
    ms_buf_free(&s.stack);
    const size_t count = MS_VEC_LEN(s.cuts, MsRange);
    if (count == 0) {
        ms_buf_free(&s.cuts);
        return false;
    }
    MsRange *cuts = ms_buf_items(&s.cuts);
    qsort(cuts, count, sizeof *cuts, range_order);
    FmtEdit *edits = MS_NEW_N(f->arena, FmtEdit, count);
    size_t kept = 0;
    for (size_t i = 0; i < count; i++) {
        if (i > 0 && cuts[i].start == cuts[i - 1].start && cuts[i].end == cuts[i - 1].end) {
            continue; // duplicate
        }
        edits[kept++] = (FmtEdit){cuts[i].start, cuts[i].end, fmt_lit(" ")};
    }
    *out = fmt_apply_edits(f, source, edits, kept);
    ms_buf_free(&s.cuts);
    return true;
}

/* ---- the layout pass ---- */

typedef struct FlagsCtx {
    Layout *layout;
} FlagsCtx;

static void flags_expr(void *ctx, const MsExpr *e) {
    Layout *l = ((FlagsCtx *)ctx)->layout;
    switch ((MsExprKind)e->kind) {
    case MS_E_CALL: {
        if (e->u.call.args.len == 0) {
            return;
        }
        // Interpolation is part of one atomic string token.
        const int32_t g = lay_lookup(l, l->by_item, e->u.call.args.ptr[0].pos.offset);
        if (g < 0) {
            return;
        }
        lay_group_at(l, (size_t)g)->items = true;
        for (uint32_t i = 0; i < e->u.call.args.len; i++) {
            if (fmt_block_lambda(e->u.call.args.ptr[i].value)) {
                lay_group_at(l, (size_t)g)->force = true;
            }
        }
        break;
    }
    case MS_E_LIST: {
        const int32_t g = lay_lookup(l, l->by_open, e->pos.offset);
        if (g >= 0) {
            lay_group_at(l, (size_t)g)->list = true;
        }
        break;
    }
    case MS_E_LAMBDA: lay_parameters(l, e->u.lambda.params); break;
    default: break;
    }
}

/* ---- statement grouping ---- */

#define NO_PAIR UINT32_MAX

typedef struct Edit {
    size_t offset;
    size_t order;
    bool close; /* a `)` that goes before everything else at the offset */
    Str text;
} Edit;

typedef struct Grouper {
    Fmt *fmt;
    Str source;
    const MsToken *tokens;
    size_t ntokens;
    uint32_t *pairs; /* the close bracket's token index for each open bracket's, NO_PAIR elsewhere */
    MsBuf insert;    /* Edit */
    MsBuf remove;    /* FmtEdit */
    bool strip;
} Grouper;

/* The last token starting at `offset`, or FMT_NONE. */
static size_t group_start_of(const Grouper *g, uint32_t offset) {
    size_t low = 0;
    size_t high = g->ntokens;
    while (low < high) {
        const size_t mid = low + (high - low) / 2;
        if (g->tokens[mid].pos.offset <= offset) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    if (low == 0 || g->tokens[low - 1].pos.offset != offset) {
        return FMT_NONE;
    }
    return low - 1;
}

/* The close bracket matching the open bracket token `open`, or FMT_NONE. */
static size_t group_pair(const Grouper *g, size_t open) {
    return g->pairs[open] == NO_PAIR ? FMT_NONE : g->pairs[open];
}

static void group_insert(Grouper *g, size_t offset, bool close, Str text) {
    const Edit edit = {offset, MS_VEC_LEN(g->insert, Edit), close, text};
    MS_VEC_PUSH(g->insert, Edit, edit);
}

/* The flat text of tokens [from, to), layout tokens skipped. */
static Str group_flat(Grouper *g, size_t from, size_t to) {
    MsBuf flat = {0};
    MsBuf code = {0};
    for (size_t i = from; i < to; i++) {
        const MsToken *t = &g->tokens[i];
        if (fmt_layout_token((MsTok)t->kind)) {
            continue;
        }
        MS_VEC_PUSH(code, MsToken, *t);
        const size_t n = MS_VEC_LEN(code, MsToken);
        if (n > 1 && fmt_token_space(ms_buf_items(&code), n - 1)) {
            ms_buf_putc(&flat, ' ');
        }
        fmt_put(&flat, fmt_token_text(g->source, t));
    }
    ms_buf_free(&code);
    return fmt_take(g->fmt, &flat);
}

/* Parentheses around a whole method chain only add a line; the layout pass restores them when the
 * chain cannot hug its last call. */
static void group_unwrap_chain(Grouper *g, size_t start) {
    const MsToken *tokens = g->tokens;
    const size_t close = group_pair(g, start);
    if (close == FMT_NONE || tokens[start].kind != MS_T_LParen) {
        return;
    }
    if (start > 0) {
        switch ((MsTok)tokens[start - 1].kind) {
        case MS_T_Assign:
        case MS_T_ColonAssign:
        case MS_T_Return:
        case MS_T_Newline:
        case MS_T_Indent:
        case MS_T_Dedent: break;
        default: return;
        }
    }
    if (close + 1 < g->ntokens) {
        switch ((MsTok)tokens[close + 1].kind) {
        case MS_T_Newline:
        case MS_T_Dedent:
        case MS_T_Colon:
        case MS_T_Eof: break;
        default: return;
        }
    }
    int depth = 0;
    int dots = 0;
    for (size_t i = start + 1; i < close; i++) {
        const MsTok k = (MsTok)tokens[i].kind;
        if (fmt_is_open(k)) {
            depth++;
        } else if (k == MS_T_RParen || k == MS_T_RBracket || k == MS_T_RBrace) {
            depth--;
        } else if (k == MS_T_Dot && depth == 0) {
            dots++;
        } else if (k == MS_T_Newline || k == MS_T_Indent || k == MS_T_Dedent || k == MS_T_Fn || k == MS_T_If ||
                   k == MS_T_Else ||
                   // an operator or flow step: the parentheses decide the grouping
                   (depth == 0 && (k == MS_T_Pipe || k == MS_T_And || k == MS_T_Or || fmt_is_comparison(k) ||
                                   fmt_is_arith(k)))) {
            return;
        }
    }
    const Str inner = fmt_slice(g->source, tokens[start].hi, tokens[close].lo);
    if (dots >= 1 && !fmt_contains(inner, "//") && tokens[start + 1].kind != MS_T_Dot) {
        const FmtEdit edit = {tokens[start].lo, tokens[close].hi, group_flat(g, start + 1, close)};
        MS_VEC_PUSH(g->remove, FmtEdit, edit);
    }
}

typedef struct Call {
    size_t open, close;
} Call;

/* What a value expression is made of, at its top level. */
typedef struct WrapScan {
    size_t end;
    int booleans, dots, operators, pipes;
    MsBuf calls; /* the calls whose arguments could break */
} WrapScan;

/* Counts the operators of the value that starts at tokens[start] and ends before offset `limit`.
 * False when an indented suite makes the value impossible to wrap. */
static bool group_scan(Grouper *g, size_t start, uint32_t limit, WrapScan *scan) {
    const MsToken *tokens = g->tokens;
    scan->end = start;
    while (scan->end < g->ntokens && tokens[scan->end].pos.offset < limit) {
        const size_t at = scan->end;
        const size_t close = group_pair(g, at);
        if (close != FMT_NONE) {
            // A call with a trivial argument gains nothing from breaking.
            if (tokens[at].kind == MS_T_LParen && close > at + 3) {
                MS_VEC_PUSH(scan->calls, Call, ((Call){at, close}));
            }
            scan->end = close + 1;
            continue;
        }
        const MsTok kind = (MsTok)tokens[at].kind;
        if (fmt_layout_token(kind)) {
            return false; // an indented suite cannot be wrapped as a partial value
        }
        if (kind == MS_T_And || kind == MS_T_Or) {
            scan->booleans++;
        } else if (kind == MS_T_Dot) {
            // A line starting with `.` after a flow step applies to the whole flow, which
            // `| .name` spells out as a stage of its own.
            if (scan->pipes > 0 && at > start && tokens[at].pos.line != tokens[at - 1].pos.line &&
                tokens[at - 1].kind != MS_T_Pipe && tokens[at - 1].kind != MS_T_Try) {
                group_insert(g, tokens[at].lo, false, fmt_lit("| "));
                scan->pipes++;
            }
            scan->dots++;
        } else if (kind == MS_T_Pipe) {
            scan->pipes++;
        } else if (fmt_is_arith(kind) || fmt_is_comparison(kind)) {
            scan->operators++;
        }
        scan->end++;
    }
    return true;
}

/* Whether the opening parenthesis of one of the calls still fits on the first line, so the chain
 * can break inside that call rather than wrap whole. */
static bool group_hugs(const Grouper *g, size_t start, size_t column, const MsBuf *calls) {
    const MsToken *tokens = g->tokens;
    const Call *list = ms_buf_items(calls);
    for (size_t c = 0; c < MS_VEC_LEN(*calls, Call); c++) {
        size_t head = column;
        MsBuf code = {0};
        for (size_t i = start; i <= list[c].open; i++) {
            if (fmt_layout_token((MsTok)tokens[i].kind)) {
                continue;
            }
            MS_VEC_PUSH(code, MsToken, tokens[i]);
            const size_t n = MS_VEC_LEN(code, MsToken);
            if (n > 1 && fmt_token_space(ms_buf_items(&code), n - 1)) {
                head += 1;
            }
            head += tokens[i].hi - tokens[i].lo;
        }
        ms_buf_free(&code);
        if (head <= FMT_WIDTH) {
            return true;
        }
    }
    return false;
}

static void group_wrap(Grouper *g, size_t start, uint32_t limit) {
    if (g->strip) {
        return;
    }
    const MsToken *tokens = g->tokens;
    WrapScan scan = {0};
    const bool wrappable = group_scan(g, start, limit, &scan);
    if (!wrappable || scan.end == start) {
        ms_buf_free(&scan.calls);
        return;
    }
    const size_t end = scan.end;
    const int operators = scan.booleans + scan.operators + scan.pipes;
    const Str flat = group_flat(g, start, end);
    const size_t column = tokens[start].pos.column - 1;
    size_t width = column + fmt_chars(flat);
    if (end < g->ntokens && tokens[end].kind == MS_T_Colon) {
        width += 1; // the condition's suite colon occupies a column too
    }
    const bool hugs = operators == 0 && group_hugs(g, start, column, &scan.calls);
    ms_buf_free(&scan.calls);
    if ((scan.pipes >= 2 && width > FMT_FLOW_WIDTH) ||
        (width > FMT_WIDTH && !hugs && (operators > 0 || scan.dots >= 2))) {
        group_insert(g, tokens[start].lo, false, fmt_lit("("));
        group_insert(g, tokens[end - 1].hi, true, fmt_lit(")"));
    }
}

static void group_stmt(void *ctx, const MsStmt *s) {
    Grouper *g = ctx;
    if (fmt_is_destructure_head(s)) {
        return;
    }
    const MsExpr *value = fmt_statement_value(s);
    if (value == NULL || fmt_suite_expression(value)) {
        return;
    }
    size_t start = group_start_of(g, s->pos.offset);
    if (start == FMT_NONE) {
        return;
    }
    const MsToken *tokens = g->tokens;
    if (tokens[start].kind == MS_T_String || tokens[start].kind == MS_T_Fn) {
        return;
    }
    switch ((MsStmtKind)s->kind) {
    case MS_S_IF:
        start += 1;
        if (s->u.branch.binding != NULL) {
            // `if let name = value:` wraps only the value.
            while (tokens[start].kind != MS_T_Assign && tokens[start].kind != MS_T_ColonAssign) {
                start++;
            }
            start++;
        }
        break;
    case MS_S_WHILE: start += 1; break;
    case MS_S_RETURN:
        if (tokens[start].kind == MS_T_Return) {
            start += 1;
        }
        break;
    case MS_S_BIND:
        if (tokens[start].kind == MS_T_Void) {
            // `void value` is a binding of `_` with no `:=` token; only the value wraps.
            start += 1;
            break;
        }
        MS_FALLTHROUGH;
    case MS_S_ASSIGN:
    case MS_S_FOR: {
        const bool is_for = s->kind == MS_S_FOR;
        while (is_for ? tokens[start].kind != MS_T_In
                      : (tokens[start].kind != MS_T_Assign && tokens[start].kind != MS_T_ColonAssign)) {
            const size_t end = group_pair(g, start);
            if (end != FMT_NONE) {
                start = end;
            }
            start++;
        }
        start++;
        break;
    }
    case MS_S_CALL: {
        // `xs[i] = value` is a call of `[]=`; only the value wraps.
        size_t at = start;
        while (at < g->ntokens && tokens[at].pos.offset < value->end.offset) {
            const size_t end = group_pair(g, at);
            if (end != FMT_NONE) {
                at = end + 1;
                continue;
            }
            if (tokens[at].kind == MS_T_Assign) {
                start = at + 1;
                break;
            }
            at++;
        }
        break;
    }
    default: break;
    }
    group_wrap(g, start, value->end.offset);
}

static int fmt_edit_order(const void *a, const void *b) {
    const FmtEdit *x = a;
    const FmtEdit *y = b;
    if (x->from != y->from) {
        return x->from < y->from ? -1 : 1;
    }
    if (x->to != y->to) {
        return x->to < y->to ? -1 : 1;
    }
    return fmt_compare(x->text, y->text);
}

static int insert_order(const void *a, const void *b) {
    const Edit *x = a;
    const Edit *y = b;
    if (x->offset != y->offset) {
        return x->offset < y->offset ? -1 : 1;
    }
    return x->order < y->order ? -1 : 1;
}

/* Matches each opening delimiter with its closing one: `pairs[open] = close`. */
static void group_match_pairs(Grouper *g, MsArena *scratch) {
    g->pairs = MS_NEW_N(scratch, uint32_t, g->ntokens + 1);
    for (size_t i = 0; i < g->ntokens; i++) {
        g->pairs[i] = NO_PAIR;
    }
    MsBuf stack = {0};
    for (size_t i = 0; i < g->ntokens; i++) {
        const MsTok k = (MsTok)g->tokens[i].kind;
        if (fmt_is_open(k)) {
            MS_VEC_PUSH(stack, size_t, i);
        } else if ((k == MS_T_RParen || k == MS_T_RBracket || k == MS_T_RBrace) && stack.len != 0) {
            g->pairs[MS_VEC_LAST(stack, size_t)] = (uint32_t)i;
            MS_VEC_POP(stack, size_t);
        }
    }
    ms_buf_free(&stack);
}

/* The source with the grouping parentheses of `g.insert` added: all the text inserted at one
 * offset is the `)` that go in front, then the rest in the order it was added. */
static Str group_apply_inserts(Fmt *f, Str source, Grouper *g) {
    const size_t count = MS_VEC_LEN(g->insert, Edit);
    Edit *ops = ms_buf_items(&g->insert);
    if (count > 1) {
        qsort(ops, count, sizeof *ops, insert_order);
    }
    FmtEdit *edits = MS_NEW_N(f->arena, FmtEdit, count + 1);
    size_t nedits = 0;
    for (size_t i = 0; i < count;) {
        size_t end = i;
        MsBuf text = {0};
        while (end < count && ops[end].offset == ops[i].offset) {
            if (ops[end].close) {
                ms_buf_put(&text, ops[end].text.ptr, ops[end].text.len);
            }
            end++;
        }
        for (size_t k = i; k < end; k++) {
            if (!ops[k].close) {
                ms_buf_put(&text, ops[k].text.ptr, ops[k].text.len);
            }
        }
        edits[nedits++] = (FmtEdit){ops[i].offset, ops[i].offset, fmt_take(f, &text)};
        i = end;
    }
    return fmt_apply_edits(f, source, edits, nedits);
}

/* Ordinary newlines cannot split ungrouped expressions. Adds grouping only around a statement's
 * complete value, retaining its precedence and inline suite. With `strip`, removes parentheses
 * around a whole method chain instead. */
static bool fmt_group_statement_expressions(Fmt *f, Str source, bool strip, Str *out) {
    MsArena scratch = {0};
    MsModule module;
    MsLexed lexed;
    if (!fmt_parse(f, &scratch, source, &module) || !fmt_lex(f, &scratch, source, &lexed)) {
        ms_arena_free(&scratch);
        return false;
    }
    Grouper g = {.fmt = f, .source = source, .tokens = lexed.tokens, .ntokens = lexed.ntokens, .strip = strip};
    group_match_pairs(&g, &scratch);
    if (strip) {
        for (size_t start = 0; start < lexed.ntokens; start++) {
            group_unwrap_chain(&g, start);
        }
    }
    const MsVisitor visitor = {.ctx = &g, .stmt = group_stmt};
    for (uint32_t i = 0; i < module.ndecls; i++) {
        const MsDecl *d = module.decls[i];
        // A constant's synthetic statement starts at its initializer, which may be text, so it
        // bypasses the keyword and text-statement handling.
        if (d->kind == MS_D_CONST && !fmt_suite_expression(d->u.konst.value)) {
            const size_t start = group_start_of(&g, d->u.konst.init_pos.offset);
            if (start != FMT_NONE) {
                group_wrap(&g, start, d->u.konst.value->end.offset);
            }
        }
        ms_walk_decl(&visitor, d);
    }
    if (strip) {
        const size_t count = MS_VEC_LEN(g.remove, FmtEdit);
        FmtEdit *edits = ms_buf_items(&g.remove);
        if (count > 1) {
            qsort(edits, count, sizeof *edits, fmt_edit_order);
        }
        *out = fmt_apply_edits(f, source, edits, count);
    } else {
        *out = group_apply_inserts(f, source, &g);
    }
    ms_buf_free(&g.insert);
    ms_buf_free(&g.remove);
    ms_arena_free(&scratch);
    return true;
}

/* A grouped import is laid out one clause per line by `group_imports`; the item layout would
 * split inside a clause. */
static bool lay_import_clauses(Str text, Nodes nodes, size_t index, const Group *g) {
    if (g->open.kind != MS_T_LParen || index < 1 || nodes.ptr[index - 1].tok.kind != MS_T_Import) {
        return false;
    }
    for (size_t k = 0; k < g->nodes.len; k++) {
        if (g->nodes.ptr[k].tok.kind == MS_T_Name && fmt_is(fmt_token_text(text, &g->nodes.ptr[k].tok), "from")) {
            return true;
        }
    }
    return false;
}

/* The width that follows group `index` on its closing line. Only a method call in a chain counts
 * what follows it; other groups (type arguments, clause patterns) keep their own line. */
static size_t lay_group_following(const Layout *l, Str text, Nodes nodes, size_t index, const Group *g) {
    if (g->open.kind != MS_T_LParen) {
        return 0;
    }
    if (index >= 2 && nodes.ptr[index - 1].tok.kind == MS_T_Name && nodes.ptr[index - 2].tok.kind == MS_T_Dot) {
        return lay_following_width(l, (Nodes){nodes.ptr + index + 1, nodes.len - index - 1}, true);
    }
    if (index >= 1 && nodes.ptr[index - 1].tok.kind == MS_T_Import) {
        // The `from "path"` clause shares the closing line.
        const Str rest = fmt_slice(text, g->close.hi, text.len);
        const size_t end = fmt_find_byte(rest, '\n');
        return fmt_chars(end == FMT_NONE ? rest : fmt_slice(rest, 0, end));
    }
    return 0;
}

bool fmt_expression_layout(Fmt *f, Str source, Str *out) {
    Str text;
    if (!fmt_group_statement_expressions(f, source, true, &text) ||
        !fmt_group_statement_expressions(f, text, false, &text)) {
        return false;
    }
    MsArena scratch = {0};
    MsModule module;
    MsLexed lexed;
    if (!fmt_parse(f, &scratch, text, &module) || !fmt_lex(f, &scratch, text, &lexed)) {
        ms_arena_free(&scratch);
        return false;
    }
    Str compacted;
    if (lay_compact_callback_suites(f, &module, lexed.tokens, lexed.ntokens, text, &compacted)) {
        ms_arena_free(&scratch);
        text = compacted;
        if (!fmt_parse(f, &scratch, text, &module) || !fmt_lex(f, &scratch, text, &lexed)) {
            ms_arena_free(&scratch);
            return false;
        }
    }
    MsArena tree = {0};
    MsBuf line_buf = {0};
    size_t start = 0;
    for (size_t i = 0; i <= text.len; i++) {
        if (i == text.len || text.ptr[i] == '\n') {
            const Str line = fmt_slice(text, start, i);
            MS_VEC_PUSH(line_buf, Str, line);
            start = i + 1;
        }
    }
    Layout l = {.fmt = f, .arena = &tree, .src = text, .lines = ms_buf_items(&line_buf),
                .nlines = MS_VEC_LEN(line_buf, Str)};
    l.by_open = MS_NEW_N(&tree, uint32_t, text.len + 2);
    l.by_item = MS_NEW_N(&tree, uint32_t, text.len + 2);
    memset(l.by_open, 0, (text.len + 2) * sizeof *l.by_open);
    memset(l.by_item, 0, (text.len + 2) * sizeof *l.by_item);
    size_t ntokens;
    const MsToken *with_comments = lay_layout_tokens(&l, lexed.tokens, lexed.ntokens, &ntokens);
    MsBuf code = {0};
    size_t at = 0;
    const Nodes nodes = lay_sequence_tree(&l, with_comments, ntokens, &at, &code, -1);
    ms_buf_free(&code);
    FlagsCtx flags = {&l};
    const MsVisitor visitor = {.ctx = &flags, .expr = flags_expr};
    for (uint32_t i = 0; i < module.ndecls; i++) {
        lay_declaration(&l, module.decls[i]);
        ms_walk_decl(&visitor, module.decls[i]);
    }
    MsBuf output = {0};
    size_t offset = 0;
    for (size_t index = 0; index < nodes.len; index++) {
        if (nodes.ptr[index].group < 0) {
            continue;
        }
        const size_t gid = (size_t)nodes.ptr[index].group;
        const Group *g = lay_group_at(&l, gid);
        if (lay_import_clauses(text, nodes, index, g)) {
            continue;
        }
        fmt_put(&output, fmt_slice(text, offset, g->open.lo));
        const Str so_far = fmt_tail(&output, 0);
        const size_t newline = fmt_rfind_byte(so_far, '\n');
        const Str line = newline == FMT_NONE ? so_far : fmt_slice(so_far, newline + 1, so_far.len);
        lay_group(&l, gid, fmt_indent_of(line), fmt_chars(line), lay_group_following(&l, text, nodes, index, g),
                  &output);
        offset = g->close.hi;
    }
    fmt_put(&output, fmt_slice(text, offset, text.len));
    *out = fmt_take(f, &output);
    ms_buf_free(&line_buf);
    ms_buf_free(&l.groups);
    ms_arena_free(&tree);
    ms_arena_free(&scratch);
    return true;
}
