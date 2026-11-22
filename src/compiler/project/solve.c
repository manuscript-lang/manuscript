/* Owns the rounds of the resolver (solve.h): collecting the requirements, comparing picks, and the final copies. */
#include "compiler/project/solve_internal.h"

#include "base/message.h"
#include "base/sort.h"

/* The most rounds before the resolver gives up on a graph whose picks keep changing. */
enum { kMaxRounds = 64 };

int span_compare(MsSpan a, MsSpan b) {
  const size_t common = a.len < b.len ? a.len : b.len;
  for (size_t i = 0; i < common; i++) {
    if (a.ptr[i] != b.ptr[i]) {
      return a.ptr[i] < b.ptr[i] ? -1 : 1;
    }
  }
  return a.len == b.len ? 0 : (a.len < b.len ? -1 : 1);
}

bool solver_fail(Solver *s, MsSpan message) {
  *s->error = message;
  return false;
}

bool group_equal(const Group *a, const Group *b) {
  return ms_span_equal(a->repo, b->repo) && a->has_bucket == b->has_bucket &&
         (!a->has_bucket || ms_bucket_equal(a->bucket, b->bucket));
}

MsSpan choice_id(Solver *s, const Choice *choice) {
  return ms_lock_copy_id(s->arena, choice->url, choice->reference);
}

const Download *find_download(const Solver *s, MsSpan url, MsSpan reference) {
  for (size_t i = 0; i < s->downloads.len; i++) {
    const Download *d = &s->downloads.ptr[i];
    if (ms_span_equal(d->url, url) && ms_span_equal(d->reference, reference)) {
      return d;
    }
  }
  return NULL;
}

MsSpan ms_dependency_describe(MsArena *arena, const MsDependency *dependency) {
  if (dependency->kind != MS_SOURCE_VERSION) {
    return dependency->reference;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_requirement_append(&text, &dependency->requirement);
  const MsSpan copy = ms_message_from_builder(arena, &text);
  ms_strbuild_free(&text);
  return copy;
}

/* A requirement that names the release before `v`, as a hint in an error. */
static MsSpan earlier(MsArena *arena, const MsVersion *v) {
  MsStrBuild text = ms_strbuild_new();
  if (v->patch > 0) {
    ms_strbuild_printf(&text, "%llu.%llu.%llu", (unsigned long long)v->major, (unsigned long long)v->minor,
                       (unsigned long long)(v->patch - 1));
  } else if (v->minor > 0) {
    ms_strbuild_printf(&text, "%llu.%llu", (unsigned long long)v->major, (unsigned long long)(v->minor - 1));
  } else {
    ms_strbuild_printf(&text, "%llu", (unsigned long long)(v->major > 0 ? v->major - 1 : 0));
  }
  const MsSpan copy = ms_message_from_builder(arena, &text);
  ms_strbuild_free(&text);
  return copy;
}

static MsSpan version_text(MsArena *arena, const MsVersion *version) {
  MsStrBuild text = ms_strbuild_new();
  ms_version_append(&text, version);
  const MsSpan copy = ms_message_from_builder(arena, &text);
  ms_strbuild_free(&text);
  return copy;
}

bool ms_resolve_check_version(MsArena *arena, const char *what, MsSpan url, MsSpan reference,
                              const MsManifest *manifest, MsSpan *error) {
  MsVersion tagged = {0};
  if (!ms_version_of_tag(arena, reference, &tagged) || !manifest->has_version ||
      ms_version_compare(&tagged, &manifest->version) == 0) {
    return true;
  }
  *error = ms_message_format(arena,
                             "%s tag %S of %S holds ms.toml version %S, not %S; ask the author to fix the tag, or "
                             "require an earlier version such as =%S",
                             what, reference, url, version_text(arena, &manifest->version),
                             version_text(arena, &tagged), earlier(arena, &tagged));
  return false;
}

/* ---- collecting ---- */

static void add_asks(Solver *s, MsSpan asker, const MsManifest *manifest, bool nested) {
  for (size_t i = 0; i < manifest->dependencies.len; i++) {
    const MsDependency *dep = &manifest->dependencies.ptr[i];
    ask_list_push(&s->asks, (Ask){.asker = asker, .alias = dep->name, .dep = dep,
                                  .repo = ms_lock_repo_key(s->arena, dep->url), .nested = nested});
  }
}

static int64_t compare_asks(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const Ask *x = (const Ask *)(const void *)a;
  const Ask *y = (const Ask *)(const void *)b;
  const int by_asker = span_compare(x->asker, y->asker);
  return by_asker != 0 ? by_asker : span_compare(x->alias, y->alias);
}

/* Every requirement of the roots and of the copies picked so far. A copy counts once, however many ask for it. */
static void collect(Solver *s) {
  ask_list_free(&s->asks);
  for (size_t i = 0; i < s->request->nroots; i++) {
    add_asks(s, s->request->roots[i].name, s->request->roots[i].manifest, false);
  }
  for (size_t i = 0; i < s->chosen.len; i++) {
    const Choice *choice = &s->chosen.ptr[i];
    bool seen = false;
    for (size_t j = 0; j < i; j++) {
      seen = seen || (ms_span_equal(s->chosen.ptr[j].url, choice->url) &&
                      ms_span_equal(s->chosen.ptr[j].reference, choice->reference));
    }
    const Download *download = seen ? NULL : find_download(s, choice->url, choice->reference);
    if (download != NULL) {
      add_asks(s, choice_id(s, choice), download->fetched.manifest, true);
    }
  }
  ms_sort((uint8_t *)s->asks.ptr, s->asks.len, sizeof(Ask), compare_asks, NULL);
}

bool span_in_list(const MsSpan *names, size_t count, MsSpan name) {
  for (size_t i = 0; i < count; i++) {
    if (ms_span_equal(names[i], name)) {
      return true;
    }
  }
  return false;
}

static bool choices_equal(const ChoiceList *a, const ChoiceList *b) {
  if (a->len != b->len) {
    return false;
  }
  for (size_t i = 0; i < a->len; i++) {
    if (!group_equal(&a->ptr[i].group, &b->ptr[i].group) || !ms_span_equal(a->ptr[i].url, b->ptr[i].url) ||
        !ms_span_equal(a->ptr[i].reference, b->ptr[i].reference)) {
      return false;
    }
  }
  return true;
}

/* ---- the result ---- */

static int64_t compare_copies(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  return span_compare(((const MsCopy *)(const void *)a)->id, ((const MsCopy *)(const void *)b)->id);
}

static int64_t compare_names(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  return span_compare(((const MsRootName *)(const void *)a)->alias, ((const MsRootName *)(const void *)b)->alias);
}

static const Choice *choice_of(const Solver *s, const Ask *ask) {
  Group group = {.repo = ask->repo};
  if (ask->dep->kind == MS_SOURCE_VERSION) {
    group.has_bucket = true;
    group.bucket = ms_requirement_bucket(&ask->dep->requirement);
  }
  for (size_t i = 0; i < s->chosen.len; i++) {
    if (group_equal(&s->chosen.ptr[i].group, &group)) {
      return &s->chosen.ptr[i];
    }
  }
  return NULL;
}

static void add_copy(Solver *s, MsResolved *out, size_t *count, const Choice *choice) {
  const Download *download = find_download(s, choice->url, choice->reference);
  if (download == NULL) {
    return;
  }
  MsCopy copy = {.id = choice_id(s, choice), .url = choice->url, .reference = choice->reference,
                 .entry = download->fetched.entry, .manifest = download->fetched.manifest};
  copy.entry.id = copy.id;
  copy.entry.spec = ms_message_format(s->arena, "%S#%S", choice->url, choice->reference);
  for (size_t i = 0; i < *count; i++) {
    if (ms_span_equal(out->copies[i].id, copy.id)) {
      out->copies[i] = copy;
      return;
    }
  }
  out->copies[(*count)++] = copy;
}

static bool is_root(const Solver *s, MsSpan asker) {
  for (size_t i = 0; i < s->request->nroots; i++) {
    if (ms_span_equal(s->request->roots[i].name, asker)) {
      return true;
    }
  }
  return false;
}

static bool add_names(Solver *s, MsResolved *out) {
  out->roots = MS_ARENA_NEW_ARRAY(s->arena, MsRootName, s->asks.len + 1);
  for (size_t i = 0; i < s->asks.len; i++) {
    const Ask *ask = &s->asks.ptr[i];
    if (!is_root(s, ask->asker)) {
      continue;
    }
    const Choice *choice = choice_of(s, ask);
    if (choice == NULL) {
      return solver_fail(s, ms_message_format(s->arena, "%S was not resolved", ask->alias));
    }
    const MsRootName name = {.alias = ask->alias, .id = choice_id(s, choice)};
    bool replaced = false;
    for (size_t j = 0; j < out->nroots; j++) {
      if (ms_span_equal(out->roots[j].alias, name.alias)) {
        out->roots[j] = name;
        replaced = true;
      }
    }
    if (!replaced) {
      out->roots[out->nroots++] = name;
    }
  }
  ms_sort((uint8_t *)out->roots, out->nroots, sizeof(MsRootName), compare_names, NULL);
  return true;
}

static bool finish(Solver *s, MsResolved *out) {
  out->copies = MS_ARENA_NEW_ARRAY(s->arena, MsCopy, s->chosen.len + 1);
  for (size_t i = 0; i < s->chosen.len; i++) {
    add_copy(s, out, &out->ncopies, &s->chosen.ptr[i]);
  }
  ms_sort((uint8_t *)out->copies, out->ncopies, sizeof(MsCopy), compare_copies, NULL);
  return add_names(s, out);
}

/* ---- the rounds ---- */

static void free_solver(Solver *s) {
  ask_list_free(&s->asks);
  choice_list_free(&s->chosen);
  download_list_free(&s->downloads);
  tag_set_list_free(&s->tags);
}

/* The name of an --update that matched no dependency, or an empty span. */
static MsSpan unmatched_update(const Solver *s) {
  for (size_t i = 0; i < s->request->nupdate; i++) {
    bool matched = false;
    for (size_t j = 0; j < s->asks.len; j++) {
      matched = matched || ms_span_equal(s->asks.ptr[j].alias, s->request->update[i]);
    }
    if (!matched) {
      return s->request->update[i];
    }
  }
  return (MsSpan){0};
}

static bool settled(Solver *s, MsResolved *out) {
  const MsSpan missing = unmatched_update(s);
  if (missing.len != 0) {
    return solver_fail(s, ms_message_format(s->arena, "--update %S: no such dependency", missing));
  }
  return finish(s, out);
}

static bool run_rounds(Solver *s, MsResolved *out) {
  for (size_t round = 0; round < kMaxRounds; round++) {
    collect(s);
    ChoiceList next = {0};
    if (!solver_choose(s, &next)) {
      choice_list_free(&next);
      return false;
    }
    if (choices_equal(&next, &s->chosen)) {
      choice_list_free(&next);
      return settled(s, out);
    }
    choice_list_free(&s->chosen);
    s->chosen = next;
  }
  const MsSpan moving = s->chosen.len > 0 ? s->chosen.ptr[0].group.repo : ms_span_of_text("a repository");
  return solver_fail(s, ms_message_format(s->arena,
                                          "dependencies do not settle after %u rounds; the picks for %S keep "
                                          "changing, so pin one version with tag or sha",
                                          (unsigned)kMaxRounds, moving));
}

bool ms_resolve(MsArena *arena, const MsResolveRequest *request, MsResolved *out, MsSpan *error) {
  Solver solver = {.arena = arena, .request = request, .error = error};
  *out = (MsResolved){0};
  const bool ok = run_rounds(&solver, out);
  free_solver(&solver);
  return ok;
}
