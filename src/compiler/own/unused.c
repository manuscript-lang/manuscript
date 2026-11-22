/* compiler/own/unused.c: bindings that are never read (see unused.h). */
#include "compiler/own/unused.h"

#include "compiler/check/names.h"
#include "compiler/check/scope_walk.h"

typedef struct Candidate {
  MsName name;
  MsPos pos;
  int64_t reads;
  bool fed; /* read only to compute its own next value */
} Candidate;

MS_LIST_DEFINE(CandidateList, candidate_list, Candidate)
MS_MAP_DEFINE(OffsetMap, offset_map, uint32_t, uint32_t, ms_hash_u32_key, ms_equal_u32_key)

/* The source range of an assignment to a binding: reads of it inside only feed it. */
typedef struct Feed {
  uint32_t candidate, start, end;
} Feed;

MS_LIST_DEFINE(FeedList, feed_list, Feed)

typedef struct Unused {
  MsCheckProgram *program;
  uint32_t module;
  CandidateList candidates;
  OffsetMap by_offset; /* declaration offset -> candidate index */
  FeedList feeds;
} Unused;

static bool is_exempt(const Unused *pass, const MsBinding *binding) {
  const MsSpan text = ms_names_span(pass->program->names, binding->name);
  if (text.len != 0 && text.ptr[0] == '_') {
    return true;
  }
  if (binding->origin == MS_BIND_NARROWED && binding->mutable_) {
    return true;
  }
  /* A payload name that shadows a declaration is explained by a lint, not reported here. */
  return binding->origin == MS_BIND_PAYLOAD &&
         (ms_scope_has(&pass->program->modules.ptr[pass->module].scope, binding->name) ||
          ms_check_is_case_name(pass->program, binding->name));
}

static void declared(void *context, const MsBinding *binding, const MsBindingList *scope) {
  (void)scope;
  Unused *pass = context;
  if (binding->origin == MS_BIND_OTHER || is_exempt(pass, binding)) {
    return;
  }
  offset_map_put(&pass->by_offset, binding->decl.offset, (uint32_t)pass->candidates.len);
  candidate_list_push(&pass->candidates, (Candidate){.name = binding->name, .pos = binding->decl});
}

static Candidate *candidate_of(Unused *pass, const MsBinding *binding, uint32_t *index) {
  const uint32_t *found = offset_map_get(&pass->by_offset, binding->decl.offset);
  if (found == NULL) {
    return NULL;
  }
  *index = *found;
  return &pass->candidates.ptr[*found];
}

static void read_name(void *context, const MsExpr *expr, const MsBindingList *scope, const MsScopeSite *site) {
  (void)site;
  Unused *pass = context;
  const MsBinding *binding = ms_scope_lookup(scope, expr->u.sym);
  uint32_t index = 0;
  Candidate *candidate = binding == NULL ? NULL : candidate_of(pass, binding, &index);
  if (candidate == NULL) {
    return;
  }
  for (size_t at = 0; at < pass->feeds.len; at++) {
    const Feed *feed = &pass->feeds.ptr[at];
    if (feed->candidate == index && expr->pos.offset >= feed->start && expr->pos.offset < feed->end) {
      candidate->fed = true;
      return;
    }
  }
  candidate->reads++;
}

static void assign_name(void *context, const MsStmt *stmt, const MsBindingList *scope, const MsScopeSite *site) {
  (void)site;
  Unused *pass = context;
  const MsBinding *binding = ms_scope_lookup(scope, stmt->u.assign.name);
  uint32_t index = 0;
  if (binding != NULL && candidate_of(pass, binding, &index) != NULL) {
    feed_list_push(&pass->feeds, (Feed){.candidate = index, .start = stmt->pos.offset, .end = stmt->u.assign.value->end.offset});
  }
}

static void report(Unused *pass, const Candidate *candidate) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "local binding ");
  ms_strbuild_append(&text, ms_names_span(pass->program->names, candidate->name));
  if (candidate->fed) {
    ms_strbuild_append_text(&text, " is never read: it is only read to compute its own next value, so nothing observes it; "
                                   "remove it, use it elsewhere, or name it with a leading '_' to ignore it");
  } else {
    ms_strbuild_append_text(&text, " is never read; remove it, use it, or name it with a leading '_' to ignore it");
  }
  ms_check_report(pass->program, pass->module, candidate->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

static void check_module(MsCheckProgram *program, uint32_t module) {
  Unused pass = {.program = program, .module = module};
  const MsScopeVisitor visitor = {.context = &pass, .declared = declared, .name = read_name, .assign = assign_name};
  ms_scope_walk_module(program->modules.ptr[module].tree, &visitor, program->names);
  for (size_t index = 0; index < pass.candidates.len; index++) {
    if (pass.candidates.ptr[index].reads == 0) {
      report(&pass, &pass.candidates.ptr[index]);
    }
  }
  candidate_list_free(&pass.candidates);
  offset_map_free(&pass.by_offset);
  feed_list_free(&pass.feeds);
}

void ms_own_unused(MsCheckProgram *program) {
  if (program->diagnostics.len != 0) {
    return;
  }
  for (uint32_t module = 0; module < program->user_modules; module++) {
    check_module(program, module);
  }
}
