/* syntax/format_names.c: names that share a type are written together. Neighbouring fields, parameters
 * and enum payload names with the same type (and default) become `width, height Int`. Lists and runs
 * that hold a comment between the names stay as written. */
#include <stdlib.h>
#include <string.h>

#include "compiler/syntax/format_internal.h"

enum { GROUP_LIMIT = 32 };

typedef struct Item {
  size_t names[GROUP_LIMIT]; /* token indices of the names */
  size_t nnames;
  size_t lo, hi;         /* source range of the whole item */
  size_t mod_lo, mod_hi; /* the `move`/`var` before the names; empty when none */
  size_t rest_lo, rest_hi; /* the type and default */
} Item;

MS_LIST_DEFINE(ItemList, item_list, Item)

typedef struct NameEdit {
  size_t lo, hi;
  MsSpan text;
} NameEdit;

MS_LIST_DEFINE(NameEditList, name_edit_list, NameEdit)

typedef struct Ctx {
  Fmt *f;
  MsSpan text;
  const MsToken *tok;
  size_t ntok;
  NameEditList edits;
} Ctx;

static bool opens(MsTok k) {
  return k == MS_T_LParen || k == MS_T_LBracket || k == MS_T_LBrace || k == MS_T_BlockOpen;
}

static bool closes(MsTok k) {
  return k == MS_T_RParen || k == MS_T_RBracket || k == MS_T_RBrace || k == MS_T_BlockClose;
}

static bool type_start(MsTok k) {
  return k == MS_T_Name || k == MS_T_Fn || k == MS_T_LParen;
}

static bool word_is(const Ctx *c, size_t i, const char *word) {
  return c->tok[i].kind == MS_T_Name && fmt_eq(fmt_slice(c->text, c->tok[i].lo, c->tok[i].hi), ms_span_of_text(word));
}

/* True when the token range [a, b] reads `[move|var] name[, name]* Type [= default]`; fills `item`. */
static bool read_item(const Ctx *c, size_t a, size_t b, Item *item) {
  *item = (Item){.lo = c->tok[a].lo, .hi = c->tok[b].hi};
  size_t i = a;
  if (b >= a + 2 && (c->tok[a].kind == MS_T_Var ||
                     (word_is(c, a, "move") && c->tok[a + 1].kind == MS_T_Name &&
                      type_start((MsTok)c->tok[a + 2].kind)))) {
    item->mod_lo = c->tok[a].lo;
    item->mod_hi = c->tok[a].hi;
    i++;
  }
  while (i <= b && c->tok[i].kind == MS_T_Name && item->nnames < GROUP_LIMIT) {
    item->names[item->nnames++] = i++;
    if (i < b && c->tok[i].kind == MS_T_Comma) {
      i++;
      continue;
    }
    break;
  }
  if (item->nnames == 0 || i > b || !type_start((MsTok)c->tok[i].kind) || c->tok[i - 1].kind == MS_T_Comma) {
    return false;
  }
  item->rest_lo = c->tok[i].lo;
  item->rest_hi = c->tok[b].hi;
  return true;
}

/* Only whitespace (and, for a list, one comma) lies between two items. */
static bool gap_clean(const Ctx *c, size_t from, size_t to, bool list) {
  size_t commas = 0, newlines = 0;
  for (size_t i = from; i < to; i++) {
    const char ch = (char)c->text.ptr[i];
    if (ch == ',') {
      commas++;
    } else if (ch == '\n') {
      newlines++;
    } else if (ch != ' ' && ch != '\t') {
      return false;
    }
  }
  return list ? commas == 1 : commas == 0 && newlines == 1;
}

static bool same_text(const Ctx *c, size_t alo, size_t ahi, size_t blo, size_t bhi) {
  return fmt_eq(fmt_slice(c->text, alo, ahi), fmt_slice(c->text, blo, bhi));
}

static bool mergeable(const Ctx *c, const Item *a, const Item *b, bool list) {
  return a->nnames + b->nnames <= GROUP_LIMIT && gap_clean(c, a->hi, b->lo, list) &&
         same_text(c, a->rest_lo, a->rest_hi, b->rest_lo, b->rest_hi) &&
         same_text(c, a->mod_lo, a->mod_hi, b->mod_lo, b->mod_hi);
}

/* Records the edit that joins items[first..last] into one. */
static void join_run(Ctx *c, const Item *items, size_t first, size_t last) {
  if (last == first) {
    return;
  }
  MsStrBuild text = {0};
  if (items[first].mod_hi > items[first].mod_lo) {
    fmt_put(&text, fmt_slice(c->text, items[first].mod_lo, items[first].mod_hi));
    fmt_put(&text, ms_span_of_text(" "));
  }
  bool any = false;
  for (size_t k = first; k <= last; k++) {
    for (size_t n = 0; n < items[k].nnames; n++) {
      const MsToken *t = &c->tok[items[k].names[n]];
      fmt_put(&text, any ? ms_span_of_text(", ") : ms_span_of_text(""));
      fmt_put(&text, fmt_slice(c->text, t->lo, t->hi));
      any = true;
    }
  }
  fmt_put(&text, ms_span_of_text(" "));
  fmt_put(&text, fmt_slice(c->text, items[first].rest_lo, items[first].rest_hi));
  name_edit_list_push(&c->edits, (NameEdit){items[first].lo, items[last].hi, fmt_take(c->f, &text)});
}

static void join_items(Ctx *c, const ItemList *items, bool list) {
  size_t first = 0;
  for (size_t k = 1; k <= items->len; k++) {
    if (k < items->len && mergeable(c, &items->ptr[k - 1], &items->ptr[k], list)) {
      continue;
    }
    join_run(c, items->ptr, first, k - 1);
    first = k;
  }
}

/* Adds one comma-separated segment [a, b] of a list: a lone name waits for the typed segment that follows
 * it, which then covers it. */
static void add_segment(const Ctx *c, ItemList *items, Item *pending, size_t a, size_t b) {
  Item item;
  if (a == b && c->tok[a].kind == MS_T_Name) {
    if (pending->nnames < GROUP_LIMIT) {
      if (pending->nnames == 0) {
        pending->lo = c->tok[a].lo;
      }
      pending->names[pending->nnames++] = a;
    }
    return;
  }
  const bool typed = read_item(c, a, b, &item);
  if (typed && pending->nnames != 0 && item.mod_hi == item.mod_lo &&
      pending->nnames + item.nnames <= GROUP_LIMIT) {
    for (size_t n = 0; n < item.nnames; n++) {
      pending->names[pending->nnames++] = item.names[n];
    }
    item.nnames = pending->nnames;
    memcpy(item.names, pending->names, item.nnames * sizeof item.names[0]);
    item.lo = pending->lo;
  } else if (typed && pending->nnames != 0) {
    pending->nnames = 0;
    return;
  }
  pending->nnames = 0;
  if (typed) {
    item_list_push(items, item);
  }
}

/* The parameter or payload list opened by the `(` at token `open`; returns the matching `)`. */
static size_t join_list(Ctx *c, size_t open) {
  ItemList items = {0};
  Item pending = {0};
  size_t depth = 0, seg = open + 1, i = open + 1;
  for (; i < c->ntok; i++) {
    const MsTok k = (MsTok)c->tok[i].kind;
    if (opens(k)) {
      depth++;
    } else if (closes(k) && depth > 0) {
      depth--;
    } else if ((k == MS_T_Comma && depth == 0) || (closes(k) && depth == 0)) {
      if (i > seg) {
        add_segment(c, &items, &pending, seg, i - 1);
      }
      seg = i + 1;
      if (k != MS_T_Comma) {
        break;
      }
    } else if (k == MS_T_Newline || k == MS_T_Eof) {
      break;
    }
  }
  join_items(c, &items, true);
  item_list_free(&items);
  return i;
}

/* A `{` block of statements, each a field or payload line, from token `open`; returns its `}`. */
static size_t join_block(Ctx *c, size_t open, bool payloads) {
  ItemList items = {0};
  size_t depth = 0, seg = open + 1, i = open + 1;
  for (; i < c->ntok; i++) {
    const MsTok k = (MsTok)c->tok[i].kind;
    if (k == MS_T_Newline && depth == 0) {
      seg = i + 1;
      continue;
    }
    if (payloads && depth == 0 && i > seg && k == MS_T_LParen && i == seg + 1 && c->tok[seg].kind == MS_T_Name &&
        c->tok[i].lo == c->tok[seg].hi) {
      i = join_list(c, i);
      continue;
    }
    if (opens(k)) {
      depth++;
      continue;
    }
    if (closes(k) && depth > 0) {
      depth--;
      continue;
    }
    if (k == MS_T_BlockClose && depth == 0) {
      break;
    }
    const bool at_line_end = i + 1 < c->ntok && (c->tok[i + 1].kind == MS_T_Newline || c->tok[i + 1].kind == MS_T_BlockClose);
    if (depth == 0 && i > seg && at_line_end && !payloads) {
      Item item;
      if (read_item(c, seg, i, &item)) {
        item_list_push(&items, item);
      }
    }
  }
  if (!payloads) {
    join_items(c, &items, false);
  }
  item_list_free(&items);
  return i;
}

static int by_start(const void *a, const void *b) {
  const NameEdit *x = a, *y = b;
  return x->lo < y->lo ? -1 : x->lo > y->lo;
}

static bool at_statement_start(const Ctx *c, size_t i) {
  if (i == 0) {
    return true;
  }
  const MsTok p = (MsTok)c->tok[i - 1].kind;
  return p == MS_T_Newline || p == MS_T_BlockOpen || p == MS_T_BlockClose || p == MS_T_Export;
}

/* The `(` of the parameters of the `fn` at token `i`, or FMT_NONE. */
static size_t params_open(const Ctx *c, size_t i) {
  size_t depth = 0;
  for (size_t j = i + 1; j < c->ntok; j++) {
    const MsTok k = (MsTok)c->tok[j].kind;
    if (k == MS_T_LBracket) {
      depth++;
    } else if (k == MS_T_RBracket && depth > 0) {
      depth--;
    } else if (depth == 0 && k == MS_T_LParen) {
      return j;
    } else if (depth == 0 && k != MS_T_Name && k != MS_T_Dot && k != MS_T_Var) {
      return FMT_NONE;
    }
  }
  return FMT_NONE;
}

/* The `{` that opens the body of the `type` or `enum` at token `i`, or FMT_NONE. */
static size_t body_open(const Ctx *c, size_t i) {
  size_t depth = 0;
  for (size_t j = i + 1; j < c->ntok; j++) {
    const MsTok k = (MsTok)c->tok[j].kind;
    if (k == MS_T_BlockOpen && depth == 0) {
      return j;
    }
    if (k == MS_T_LBracket) {
      depth++;
    } else if (k == MS_T_RBracket && depth > 0) {
      depth--;
    } else if (k == MS_T_Newline || k == MS_T_Eof || k == MS_T_Assign) {
      return FMT_NONE;
    }
  }
  return FMT_NONE;
}

bool fmt_group_names(Fmt *f, MsSpan text, const MsToken *tokens, size_t ntokens, MsSpan *out) {
  Ctx c = {.f = f, .text = text, .tok = tokens, .ntok = ntokens};
  for (size_t i = 0; i < ntokens; i++) {
    const MsTok k = (MsTok)tokens[i].kind;
    if (k == MS_T_Fn) {
      const size_t open = params_open(&c, i);
      if (open != FMT_NONE) {
        join_list(&c, open);
      }
    } else if ((k == MS_T_Type || k == MS_T_Enum) && at_statement_start(&c, i)) {
      const size_t open = body_open(&c, i);
      if (open != FMT_NONE) {
        join_block(&c, open, k == MS_T_Enum);
      }
    }
  }
  if (c.edits.len == 0) {
    name_edit_list_free(&c.edits);
    return false;
  }
  qsort(c.edits.ptr, c.edits.len, sizeof(NameEdit), by_start);
  MsStrBuild result = {0};
  size_t copied = 0;
  for (size_t e = 0; e < c.edits.len; e++) {
    if (c.edits.ptr[e].lo < copied) {
      continue;
    }
    fmt_put(&result, fmt_slice(text, copied, c.edits.ptr[e].lo));
    fmt_put(&result, c.edits.ptr[e].text);
    copied = c.edits.ptr[e].hi;
  }
  fmt_put(&result, fmt_slice(text, copied, text.len));
  name_edit_list_free(&c.edits);
  *out = fmt_take(f, &result);
  return true;
}
