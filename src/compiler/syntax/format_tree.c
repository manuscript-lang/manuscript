/* syntax/format_tree.c: which groups hold parameters, and the token tree. */
#include "compiler/syntax/format_layout.h"
#include "compiler/syntax/walk.h"

/* ---- which groups hold parameters ---- */

void lay_parameters(Layout *l, MsParams params);

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
  const MsSpan before = fmt_trim_end(fmt_slice(l->src, 0, p->pos.offset));
  if (!fmt_ends(before, keyword)) {
    return p->pos.offset;
  }
  return (uint32_t)(before.len - ms_span_of_text(keyword).len);
}

void lay_parameters(Layout *l, MsParams params) {
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

void lay_declaration(Layout *l, const MsDecl *d) {
  switch ((MsDeclKind)d->kind) {
  case MS_D_FN:
    lay_func(l, &d->u.fn);
    break;
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
  case MS_D_TEST:
    break;
  }
}

/* ---- tokens and trees ---- */

/* The tokens with each line's trailing `//` comment added as a Comment token. Comments are
 * recovered only outside lexer tokens, so `//` and interpolation inside strings never become
 * formatter instructions. */
MsToken *lay_layout_tokens(Layout *l, const MsToken *tokens, size_t ntokens, size_t *count) {
  uint32_t *last = MS_ARENA_NEW_ARRAY(l->arena, uint32_t, l->nlines + 2);
  memset(last, 0, (l->nlines + 2) * sizeof *last);
  for (size_t i = 0; i < ntokens; i++) {
    if (!fmt_layout_token((MsTok)tokens[i].kind) && tokens[i].pos.line <= l->nlines) {
      last[tokens[i].pos.line] = tokens[i].pos.column - 1 + (tokens[i].hi - tokens[i].lo);
    }
  }
  TokenList comments = {0};
  size_t offset = 0;
  for (size_t index = 0; index < l->nlines; index++) {
    const MsSpan line = l->lines[index];
    const size_t tail = last[index + 1];
    if (tail <= line.len) {
      const size_t at = fmt_find(fmt_slice(line, tail, line.len), ms_span_of_text("//"));
      if (at != FMT_NONE) {
        const size_t column = tail + at;
        const MsSpan text = fmt_trim_end_set(fmt_slice(line, column, line.len), " \t");
        MsToken comment = {.kind = MS_T_Comment,
                           .lo = (uint32_t)(offset + column),
                           .hi = (uint32_t)(offset + column + text.len)};
        comment.pos = (MsPos){(uint32_t)(offset + column), (uint32_t)index + 1, (uint32_t)column + 1};
        comment.end = comment.pos;
        token_list_push(&comments, comment);
      }
    }
    offset += line.len + 1;
  }
  const MsToken *found = comments.ptr;
  const size_t nfound = comments.len;
  MsToken *result = MS_ARENA_NEW_ARRAY(l->arena, MsToken, ntokens + nfound + 1);
  size_t n = 0;
  size_t next = 0;
  for (size_t i = 0; i < ntokens; i++) {
    while (next < nfound && found[next].pos.offset <= tokens[i].pos.offset) {
      result[n++] = found[next++];
    }
    result[n++] = tokens[i];
  }
  token_list_free(&comments);
  *count = n;
  return result;
}

Nodes lay_sequence_tree(Layout *l, const MsToken *tokens, size_t ntokens, size_t *at, TokenList *code,
                        int close_kind) {
  NodeList nodes = {0};
  while (*at < ntokens && (int)tokens[*at].kind != close_kind) {
    const MsToken token = tokens[*at];
    (*at)++;
    Node node = {.tok = token, .group = -1, .space = false};
    if (!fmt_layout_token((MsTok)token.kind) && token.kind != MS_T_Comment) {
      token_list_push(code, token);
      const size_t n = code->len;
      node.space = n > 1 && fmt_token_space(code->ptr, n - 1);
    }
    int end = -1;
    switch ((MsTok)token.kind) {
    case MS_T_LParen:
      end = MS_T_RParen;
      break;
    case MS_T_LBracket:
      end = MS_T_RBracket;
      break;
    case MS_T_LBrace:
      end = MS_T_RBrace;
      break;
    default:
      break;
    }
    if (end >= 0) {
      bool items = token.kind != MS_T_LParen;
      const size_t ncode = code->len;
      if (ncode > 1) {
        const MsToken *before = &code->ptr[ncode - 2];
        items = items || before->kind == MS_T_Name || before->kind == MS_T_RParen ||
                before->kind == MS_T_RBracket || before->kind == MS_T_Fn;
      }
      const Nodes children = lay_sequence_tree(l, tokens, ntokens, at, code, end);
      const MsToken close_token = tokens[*at];
      token_list_push(code, close_token);
      (*at)++;
      // Only a nested suite keeps a group multi-line; authored line breaks otherwise
      // collapse when the group fits.
      bool force = false;
      for (size_t i = 0; i < children.len; i++) {
        force = force || children.ptr[i].tok.kind == MS_T_Newline;
      }
      const size_t gid = l->groups.len;
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
      const Group group = {.open = token,
                           .close = close_token,
                           .nodes = children,
                           .force = force,
                           .items = items,
                           .callee = items};
      group_list_push(&l->groups, group);
      node.group = (int32_t)gid;
    }
    node_list_push(&nodes, node);
  }
  Nodes result = {0};
  result.len = nodes.len;
  Node *copy = MS_ARENA_NEW_ARRAY(l->arena, Node, result.len + 1);
  if (result.len != 0) {
    memcpy(copy, nodes.ptr, result.len * sizeof(Node));
  }
  node_list_free(&nodes);
  result.ptr = copy;
  return result;
}
