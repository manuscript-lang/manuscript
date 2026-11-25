/* compiler/own/borrows_judge.c: decides which changes a borrow outlives, and reports them (see borrows.h). */
#include "compiler/own/borrows_internal.h"

#include "compiler/check/methods.h"
#include "compiler/own/look_fields.h"

/* Whether the changed place belongs to a resource: a promise that captured one at its last use owns it. */
static bool changes_resource(const Borrows *pass, const Change *change) {
  const MsExpr *at = change->place;
  for (;;) {
    MsExpr *left = NULL;
    MsExpr *index = NULL;
    if (at != NULL && at->kind == MS_E_MEMBER) {
      at = at->u.member.left;
    } else if (at != NULL && ms_expr_index(at, &left, &index)) {
      at = left;
    } else {
      break;
    }
  }
  return at != NULL && ms_check_holds_resource(pass->program, ms_facts_type(pass->facts, at->id));
}

/* Whether an exit the change runs into (`xs.append(1); break`) leaves `use` unreachable: the exit ends the loop (or the
 * function), so a use before the change in the next round, or after the exit inside the loop, never runs. A loop that
 * ends inside the exit's block runs the change again, so it keeps the use reachable. */
static bool cut_by_exit(const Borrows *pass, uint32_t change, const Use *later) {
  const uint32_t use = later->offset;
  for (size_t index = 0; index < pass->exits.len; index++) {
    const Exit *exit = &pass->exits.ptr[index];
    if (change < exit->lo || change >= exit->at || (use > change && use < exit->at)) {
      continue;
    }
    bool straight = true;
    const Range *loop = NULL; /* the innermost loop around the exit */
    for (size_t at = 0; at < pass->ranges.len; at++) {
      const Range *range = &pass->ranges.ptr[at];
      if (!range->loop) {
        continue;
      }
      straight = straight && !(change >= range->lo && change <= range->hi && exit->at > range->hi);
      if (exit->at >= range->lo && exit->at <= range->hi && (loop == NULL || range->lo > loop->lo)) {
        loop = range;
      }
    }
    if (straight && (exit->is_return || (loop != NULL && use >= loop->lo && use <= loop->hi && (later->loop == 0 || later->loop > loop->lo)))) {
      return true;
    }
  }
  return false;
}

/* Whether a use at `use` can run after a change at `change`: later in the source, unless the two sit in
 * different arms of one branch; or anywhere in a loop that holds the change and not the borrow's binding. */
static bool runs_after(const Borrows *pass, const Borrow *borrow, uint32_t change, const Use *later, bool in_lambda) {
  const uint32_t use = later->offset;
  if (!in_lambda && cut_by_exit(pass, change, later)) {
    return false;
  }
  for (size_t index = 0; index < pass->ranges.len; index++) {
    const Range *range = &pass->ranges.ptr[index];
    if (range->loop) {
      if (change >= range->lo && change <= range->hi && use >= range->lo && use <= range->hi &&
          borrow->after < range->lo) {
        return true;
      }
      continue;
    }
    const bool change_then = change >= range->lo && change < range->split;
    const bool change_else = change >= range->split && change <= range->hi;
    const bool use_then = use >= range->lo && use < range->split;
    const bool use_else = use >= range->split && use <= range->hi;
    if ((change_then && use_else) || (change_else && use_then)) {
      return false;
    }
  }
  return use > change;
}

static bool used_after(const Borrows *pass, const Borrow *borrow, uint32_t offset, bool in_lambda) {
  for (size_t index = 0; index < pass->uses.len; index++) {
    if (pass->uses.ptr[index].binding == borrow->binding &&
        runs_after(pass, borrow, offset, &pass->uses.ptr[index], in_lambda)) {
      return true;
    }
  }
  return false;
}

static void append_name(const Borrows *pass, MsStrBuild *text, MsName name) {
  ms_strbuild_append(text, ms_names_span(pass->program->names, name));
}

static MsSpan source_text(const Borrows *pass, const MsExpr *expr) {
  const MsPos start = ms_expr_start(expr);
  return (MsSpan){pass->source.ptr + start.offset, expr->end.offset - start.offset};
}

/* The name a call is written with. */
static MsName call_name(const MsExpr *call) {
  const MsExpr *callee = call->u.call.callee;
  return callee->kind == MS_E_MEMBER ? callee->u.member.name : callee->u.sym;
}

/* A `get` that reads an element of its receiver in place: the position would own an element the receiver keeps. */
static void report_kept_read(Borrows *pass, const MsExpr *kept) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "`");
  ms_own_expr_text(&text, pass->program->names, kept);
  ms_strbuild_append_text(&text, "` reads an element that `");
  ms_own_expr_text(&text, pass->program->names, kept->u.call.callee->u.member.left);
  ms_strbuild_append_text(&text, "` keeps, and this position would own it too; store `.clone()` of it, or use it in place");
  ms_check_report(pass->program, pass->module, kept->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

static void report_keep(Borrows *pass, const Keep *keep) {
  if (keep->returned) {
    MsStrBuild text = ms_strbuild_new();
    if (ms_borrows_describe_returned(pass, keep->kept, &text)) {
      ms_check_report(pass->program, pass->module, keep->kept->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
    } else {
      ms_strbuild_free(&text);
    }
    return;
  }
  if (!ms_borrows_lends_collection(pass, keep->source.call) && ms_own_native_get(pass->program, pass->facts, keep->kept) != MS_NATIVE_GET_NONE) {
    report_kept_read(pass, keep->kept);
    return;
  }
  const MsExpr *base = keep->source.call;
  const MsCall *fact = ms_facts_call(pass->facts, base->id);
  const bool native = fact != NULL && fact->callee.kind != MS_REF_METHOD && fact->callee.kind != MS_REF_FUNCTION;
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "`");
  append_name(pass, &text, native ? call_name(base) : call_name(keep->kept));
  ms_strbuild_append_text(&text, native ? "` borrows `" : "` returns a reference into `");
  ms_strbuild_append(&text, source_text(pass, keep->source.place));
  ms_strbuild_append_text(&text, "`, which this position would keep; store `.clone()` of it, or use it in place");
  ms_check_report(pass->program, pass->module, keep->kept->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

static void report(Borrows *pass, const Borrow *borrow, const Change *change, MsPos at) {
  const MsPos start = change->pos;
  if (change->end <= start.offset || change->end > pass->source.len) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, change->assign ? "cannot reassign `" : change->moved ? "cannot move `" : "cannot change `");
  ms_strbuild_append(&text, (MsSpan){pass->source.ptr + start.offset, change->end - start.offset});
  if (borrow->loop) {
    ms_strbuild_append_text(&text, "` while the loop at ");
    ms_strbuild_append_u64(&text, borrow->at.line);
    ms_strbuild_append_text(&text, ":");
    ms_strbuild_append_u64(&text, borrow->at.column);
    ms_strbuild_append_text(&text, " iterates it; apply the change after the loop, or loop over a `.clone()` of it");
    ms_check_report(pass->program, pass->module, at, MS_CHECK_TYPE, ms_strbuild_finish(&text));
    return;
  }
  ms_strbuild_append_text(&text, "` while `");
  append_name(pass, &text, borrow->name);
  ms_strbuild_append_text(&text, borrow->method_value ? "` borrows it (method value, at "
                                 : borrow->mutable_   ? "` borrows it (mutable borrow, at "
                                                      : "` borrows it (binding of a part of it, at ");
  ms_strbuild_append_u64(&text, borrow->at.line);
  ms_strbuild_append_text(&text, ":");
  ms_strbuild_append_u64(&text, borrow->at.column);
  ms_strbuild_append_text(&text, "); finish using `");
  append_name(pass, &text, borrow->name);
  if (borrow->method_value) {
    ms_strbuild_append_text(&text, "` before this, or build `");
    append_name(pass, &text, borrow->name);
    ms_strbuild_append_text(&text, "` from a clone: bind `.clone()` of the captured value first and capture that binding");
  } else {
    ms_strbuild_append_text(&text, "` before this, or give `");
    append_name(pass, &text, borrow->name);
    ms_strbuild_append_text(&text, "` its own value by ending its initializer with `.clone()`");
  }
  ms_check_report(pass->program, pass->module, at, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

/* Whether two places of one binding can share storage: unless both are plain field chains, and neither is a prefix of
 * the other (`self.data` and `self.at` are separate fields). */
static bool places_overlap(const MsExpr *a, const MsExpr *b) {
  const MsExpr *chain[2][16];
  size_t length[2] = {0, 0};
  const MsExpr *both[2] = {a, b};
  for (int side = 0; side < 2; side++) {
    const MsExpr *at = both[side];
    for (;;) {
      MsExpr *left = NULL;
      MsExpr *index = NULL;
      if (at != NULL && ms_expr_index(at, &left, &index)) {
        at = left; /* an element lies inside its collection's place */
        continue;
      }
      if (at == NULL || at->kind != MS_E_MEMBER) {
        break;
      }
      if (length[side] == 16) {
        return true;
      }
      chain[side][length[side]++] = at;
      at = at->u.member.left;
    }
    if (at == NULL || at->kind != MS_E_NAME) {
      return true;
    }
  }
  const size_t shared = length[0] < length[1] ? length[0] : length[1];
  for (size_t at = 0; at < shared; at++) { /* chains run from the leaf to the root, so compare from the root */
    if (chain[0][length[0] - 1 - at]->u.member.name != chain[1][length[1] - 1 - at]->u.member.name) {
      return false;
    }
  }
  return true;
}

/* Each borrow reports its first later change of the source when the borrower is still used after it. */
void ms_borrows_judge(Borrows *pass) {
  for (size_t at = 0; at < pass->keeps.len; at++) {
    report_keep(pass, &pass->keeps.ptr[at]);
  }
  for (size_t index = 0; index < pass->changes.len; index++) {
    const Change *change = &pass->changes.ptr[index];
    for (size_t at = 0; change->lambda != NULL && at < pass->kept.len; at++) {
      if (pass->kept.ptr[at] == change->lambda && !changes_resource(pass, change) && change->end > change->pos.offset && change->end <= pass->source.len) {
        MsStrBuild text = ms_strbuild_new();
        ms_strbuild_append_text(&text, "this closure is kept by the runtime (a promise), so it only reads what it captures, but it changes `");
        ms_strbuild_append(&text, (MsSpan){pass->source.ptr + change->pos.offset, change->end - change->pos.offset});
        ms_strbuild_append_text(&text, "`; clone the value inside the closure, or send changes through a pipe to one owner");
        ms_check_report(pass->program, pass->module, change->at, MS_CHECK_TYPE, ms_strbuild_finish(&text));
        break;
      }
    }
  }
  for (size_t at = 0; at < pass->borrows.len; at++) {
    const Borrow *borrow = &pass->borrows.ptr[at];
    for (size_t index = 0; index < pass->changes.len; index++) {
      const Change *change = &pass->changes.ptr[index];
      const uint32_t offset = change->pos.offset;
      if (borrow->alias && !change->moved) {
        continue;
      }
      if (change->value_write && borrow->parts != 0 && (borrow->parts & 2u) == 0) {
        continue; /* a view of a map's keys: changing a value in place leaves the keys alone */
      }
      if (change->root == borrow->root && offset >= borrow->after && used_after(pass, borrow, offset, change->lambda != NULL) &&
          (change->place == NULL || borrow->place == NULL || places_overlap(change->place, borrow->place))) {
        report(pass, borrow, change, change->at);
        if (change->lambda != NULL) { /* the closure that runs the change is itself a change of what it captured */
          report(pass, borrow, change, change->lambda->pos);
        }
        break;
      }
    }
  }
  borrow_list_clear(&pass->borrows);
  change_list_clear(&pass->changes);
  use_list_clear(&pass->uses);
  range_list_clear(&pass->ranges);
  exit_list_clear(&pass->exits);
  lambda_list_clear(&pass->kept);
  keep_list_clear(&pass->keeps);
}

