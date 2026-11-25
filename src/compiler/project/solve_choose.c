/* Owns the picks of one resolver round (solve.h): the tag that satisfies each bucket, the commit of each pin, and the
 * downloads of what was picked. */
#include "base/message.h"
#include "base/sort.h"
#include "compiler/project/package.h"
#include "compiler/project/solve_internal.h"

static bool satisfies(const MsDependency *dep, const MsVersion *version) {
  return version != NULL && dep->kind == MS_SOURCE_VERSION && ms_requirement_matches(&dep->requirement, version);
}

static bool tag_satisfies(Solver *s, const AskPointerList *members, MsSpan tag) {
  MsVersion version = {0};
  if (!ms_version_of_tag(s->arena, tag, &version)) {
    return false;
  }
  for (size_t i = 0; i < members->len; i++) {
    if (!satisfies(members->ptr[i]->dep, &version)) {
      return false;
    }
  }
  return true;
}

/* ---- tags ---- */

static int64_t compare_version_tags(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const VersionTag *x = (const VersionTag *)(const void *)a;
  const VersionTag *y = (const VersionTag *)(const void *)b;
  const int by_version = ms_version_compare(&x->version, &y->version);
  return by_version != 0 ? by_version : ms_span_compare(x->tag, y->tag);
}

static MsSpan version_name(Solver *s, const MsVersion *version) {
  MsStrBuild text = ms_strbuild_new();
  ms_version_append(&text, version);
  const MsSpan copy = ms_message_from_builder(s->arena, &text);
  ms_strbuild_free(&text);
  return copy;
}

/* Adds `tag` to the sorted-later list `found`, or fails when another tag already names its version. */
static bool add_tag(Solver *s, MsSpan url, MsSpan tag, VersionTag *found, size_t *count) {
  VersionTag entry = {.tag = tag};
  if (!ms_version_of_tag(s->arena, tag, &entry.version)) {
    return true;
  }
  for (size_t i = 0; i < *count; i++) {
    if (ms_version_compare(&found[i].version, &entry.version) == 0) {
      return solver_fail(s, ms_message_format(s->arena, "%S has both %S and %S for version %S; delete one of the tags",
                                              url, found[i].tag, tag, version_name(s, &entry.version)));
    }
  }
  found[(*count)++] = entry;
  return true;
}

static const TagSet *tags_of(Solver *s, MsSpan url) {
  const MsSpan repo = ms_lock_repo_key(s->arena, url);
  for (size_t i = 0; i < s->tags.len; i++) {
    if (ms_span_equal(s->tags.ptr[i].repo, repo)) {
      return &s->tags.ptr[i];
    }
  }
  MsSpan *names = NULL;
  size_t n = 0;
  if (!s->request->remote->tags(s->request->remote->self, s->arena, url, &names, &n, s->error)) {
    return NULL;
  }
  TagSet set = {.repo = repo, .tags = MS_ARENA_NEW_ARRAY(s->arena, VersionTag, n + 1)};
  for (size_t i = 0; i < n; i++) {
    if (!add_tag(s, url, names[i], set.tags, &set.count)) {
      return NULL;
    }
  }
  ms_sort((uint8_t *)set.tags, set.count, sizeof(VersionTag), compare_version_tags, NULL);
  tag_set_list_push(&s->tags, set);
  return &s->tags.ptr[s->tags.len - 1];
}

/* ---- best ---- */

static MsSpan joined(Solver *s, const MsSpan *parts, size_t count, const char *separator) {
  MsStrBuild text = ms_strbuild_new();
  for (size_t i = 0; i < count; i++) {
    if (i > 0) {
      ms_strbuild_append_text(&text, separator);
    }
    ms_strbuild_append(&text, parts[i]);
  }
  const MsSpan copy = ms_message_from_builder(s->arena, &text);
  ms_strbuild_free(&text);
  return copy;
}

static bool fail_no_tag(Solver *s, MsSpan repo, const AskPointerList *members, const TagSet *listed, MsBucket bucket) {
  MsSpan *asked = MS_ARENA_NEW_ARRAY(s->arena, MsSpan, members->len + 1);
  bool by_one = false;
  for (size_t i = 0; i < members->len; i++) {
    const Ask *ask = members->ptr[i];
    asked[i] = ms_message_format(s->arena, "%S asks %S", ask->asker, ms_dependency_describe(s->arena, ask->dep));
    for (size_t j = 0; j < listed->count; j++) {
      const VersionTag *entry = &listed->tags[j];
      const MsBucket own = ms_version_bucket(&entry->version);
      by_one = by_one || (ms_bucket_equal(own, bucket) && satisfies(ask->dep, &entry->version));
    }
  }
  MsSpan *available = MS_ARENA_NEW_ARRAY(s->arena, MsSpan, listed->count + 1);
  for (size_t i = 0; i < listed->count; i++) {
    available[i] = version_name(s, &listed->tags[i].version);
  }
  const MsSpan asked_text = joined(s, asked, members->len, " and ");
  if (members->len > 1 && by_one) {
    return solver_fail(s, ms_message_format(s->arena, "%S: %S; no tag satisfies all of them (tags: %S)", repo,
                                            asked_text, joined(s, available, listed->count, ", ")));
  }
  const MsSpan names = listed->count == 0 ? ms_span_of_text("none") : joined(s, available, listed->count, ", ");
  return solver_fail(s, ms_message_format(s->arena, "no tag of %S satisfies %S (tags: %S)", repo, asked_text, names));
}

/* The highest tag in `bucket` that satisfies every requirement. */
static bool best(Solver *s, MsSpan repo, MsBucket bucket, const AskPointerList *members, const TagSet *listed,
                 MsSpan *tag) {
  for (size_t i = listed->count; i > 0; i--) {
    const VersionTag *entry = &listed->tags[i - 1];
    if (!ms_bucket_equal(ms_version_bucket(&entry->version), bucket)) {
      continue;
    }
    bool all = true;
    for (size_t j = 0; j < members->len; j++) {
      all = all && satisfies(members->ptr[j]->dep, &entry->version);
    }
    if (all) {
      *tag = entry->tag;
      return true;
    }
  }
  return fail_no_tag(s, repo, members, listed, bucket);
}

/* ---- downloads ---- */

static const MsLockEntry *locked_for(const Solver *s, MsSpan url, MsSpan reference) {
  const MsSpan spec = ms_message_format(s->arena, "%S#%S", url, reference);
  for (size_t i = 0; i < s->request->nold; i++) {
    if (ms_span_equal(s->request->old[i].spec, spec)) {
      return &s->request->old[i];
    }
  }
  return NULL;
}

static bool download(Solver *s, MsSpan url, MsSpan reference, const MsLockEntry *locked, bool nested) {
  Download entry = {.url = url, .reference = reference};
  if (!s->request->remote->fetch(s->request->remote->self, s->arena, url, reference, locked, nested, &entry.fetched,
                                 s->error)) {
    return false;
  }
  if (!ms_resolve_check_version(s->arena, "package", url, reference, entry.fetched.manifest, s->error)) {
    return false;
  }
  download_list_push(&s->downloads, entry);
  return true;
}

static bool nested_ask_of(const Solver *s, MsSpan repo) {
  for (size_t i = 0; i < s->asks.len; i++) {
    if (s->asks.ptr[i].nested && ms_span_equal(ms_lock_repo_key(s->arena, s->asks.ptr[i].dep->url), repo)) {
      return true;
    }
  }
  return false;
}

/* Every choice is downloaded, and its manifest agrees with its tag. */
static bool download_choices(Solver *s, const ChoiceList *next) {
  for (size_t i = 0; i < next->len; i++) {
    const Choice *choice = &next->ptr[i];
    if (find_download(s, choice->url, choice->reference) != NULL) {
      continue;
    }
    const MsLockEntry *locked = locked_for(s, choice->url, choice->reference);
    const bool nested = nested_ask_of(s, ms_lock_repo_key(s->arena, choice->url));
    if (!download(s, choice->url, choice->reference, locked, nested)) {
      return false;
    }
  }
  return true;
}

/* ---- pins ---- */

static bool is_commit(MsSpan text) {
  return ms_package_is_hex(text, 40);
}

static bool better_name(MsSpan current, MsSpan candidate) {
  /* Rust compares (is_commit(current), candidate) > (is_commit(candidate), current). */
  const bool a = is_commit(current);
  const bool b = is_commit(candidate);
  return a != b ? a : ms_span_compare(candidate, current) > 0;
}

static const MsLockEntry *locked_pin(const Solver *s, const Ask *ask) {
  if (span_in_list(s->request->update, s->request->nupdate, ask->alias)) {
    return NULL;
  }
  return locked_for(s, ask->dep->url, ask->dep->reference);
}

static bool pin_conflict(Solver *s, MsSpan repo, const Ask *first, const Ask *ask) {
  return solver_fail(s, ms_message_format(s->arena, "%S is pinned to %S by %S and to %S by %S, which are different "
                                                    "commits; pin one",
                                          repo, ms_dependency_describe(s->arena, first->dep), first->asker,
                                          ms_dependency_describe(s->arena, ask->dep), ask->asker));
}

/* One copy for all pins of a repository, which must name one commit. */
static bool pick_pin(Solver *s, MsSpan repo, const AskPointerList *pins, Choice *out) {
  const Ask *by = NULL;
  MsSpan commit = {0};
  for (size_t i = 0; i < pins->len; i++) {
    const Ask *ask = pins->ptr[i];
    const MsSpan reference = ask->dep->reference;
    if (find_download(s, ask->dep->url, reference) == NULL &&
        !download(s, ask->dep->url, reference, locked_pin(s, ask), ask->nested)) {
      return false;
    }
    const MsSpan found = find_download(s, ask->dep->url, reference)->fetched.entry.revision;
    if (by == NULL) {
      *out = (Choice){.group = {.repo = repo}, .url = ask->dep->url, .reference = reference};
      by = ask;
      commit = found;
      continue;
    }
    if (!ms_span_equal(commit, found)) {
      return pin_conflict(s, repo, by, ask);
    }
    if (better_name(out->reference, reference)) {
      *out = (Choice){.group = {.repo = repo}, .url = ask->dep->url, .reference = reference};
      by = ask;
    }
  }
  return true;
}

/* ---- one repository ---- */

static bool has_nested_non_https(Solver *s, const AskPointerList *list) {
  for (size_t i = 0; i < list->len; i++) {
    const Ask *ask = list->ptr[i];
    if (ask->nested && !ms_span_starts_with_text(ask->dep->url, "https://")) {
      return solver_fail(s, ms_message_format(s->arena,
                                              "%S depends on %S = %S; a package's own dependencies must use "
                                              "https:// URLs, because file:// reads the machine running ms install",
                                              ask->asker, ask->alias, ask->dep->url));
    }
  }
  return false;
}

static bool locked_tag(Solver *s, MsSpan repo, MsBucket bucket, const AskPointerList *members, MsSpan *tag) {
  const MsSpan prefix = ms_message_format(s->arena, "%S@", repo);
  for (size_t i = 0; i < s->request->nold; i++) {
    const MsLockEntry *entry = &s->request->old[i];
    MsSpan id = {0};
    MsVersion version = {0};
    if (!ms_lock_id_of_spec(s->arena, entry->spec, &id) || !ms_span_starts_with(id, prefix) ||
        !ms_lock_entry_version(s->arena, entry, &version) || !ms_bucket_equal(ms_version_bucket(&version), bucket)) {
      continue;
    }
    size_t hash = 0;
    while (hash < entry->spec.len && entry->spec.ptr[hash] != '#') {
      hash++;
    }
    const MsSpan candidate = ms_span_of(entry->spec.ptr + hash + 1, entry->spec.len - hash - 1);
    if (tag_satisfies(s, members, candidate)) {
      *tag = candidate;
      return true;
    }
  }
  return false;
}

static bool pick_bucket(Solver *s, MsSpan repo, MsBucket bucket, const AskPointerList *wants, ChoiceList *next) {
  AskPointerList members = {0};
  bool updating = false;
  for (size_t i = 0; i < wants->len; i++) {
    if (ms_bucket_equal(ms_requirement_bucket(&wants->ptr[i]->dep->requirement), bucket)) {
      ask_pointer_list_push(&members, wants->ptr[i]);
      updating = updating || span_in_list(s->request->update, s->request->nupdate, wants->ptr[i]->alias);
    }
  }
  const MsSpan url = wants->ptr[0]->dep->url;
  MsSpan reference = {0};
  bool ok = true;
  if (updating || !locked_tag(s, repo, bucket, &members, &reference)) {
    const TagSet *listed = tags_of(s, url);
    ok = listed != NULL && best(s, repo, bucket, &members, listed, &reference);
  }
  if (ok) {
    choice_list_push(next, (Choice){.group = {.repo = repo, .has_bucket = true, .bucket = bucket}, .url = url,
                                    .reference = reference});
  }
  ask_pointer_list_free(&members);
  return ok;
}

static bool pick_buckets(Solver *s, MsSpan repo, const AskPointerList *wants, ChoiceList *next) {
  MsBucket seen[64];
  size_t count = 0;
  for (size_t i = 0; i < wants->len; i++) {
    const MsBucket bucket = ms_requirement_bucket(&wants->ptr[i]->dep->requirement);
    bool known = false;
    for (size_t j = 0; j < count; j++) {
      known = known || ms_bucket_equal(seen[j], bucket);
    }
    if (!known && count < 64) {
      seen[count++] = bucket;
    }
  }
  /* Buckets in order: kind, then number. */
  for (size_t i = 1; i < count; i++) {
    for (size_t j = i; j > 0 && (seen[j].kind < seen[j - 1].kind ||
                                 (seen[j].kind == seen[j - 1].kind && seen[j].number < seen[j - 1].number));
         j--) {
      const MsBucket swap = seen[j];
      seen[j] = seen[j - 1];
      seen[j - 1] = swap;
    }
  }
  for (size_t i = 0; i < count; i++) {
    if (!pick_bucket(s, repo, seen[i], wants, next)) {
      return false;
    }
  }
  return true;
}

static bool pick_repo(Solver *s, MsSpan repo, const AskPointerList *list, ChoiceList *next) {
  if (has_nested_non_https(s, list)) {
    return false;
  }
  AskPointerList pins = {0};
  AskPointerList wants = {0};
  for (size_t i = 0; i < list->len; i++) {
    ask_pointer_list_push(list->ptr[i]->dep->kind == MS_SOURCE_VERSION ? &wants : &pins, list->ptr[i]);
  }
  bool ok = true;
  if (pins.len > 0 && wants.len > 0) {
    ok = solver_fail(s, ms_message_format(s->arena,
                                          "%S is needed at %S by %S and at %S by %S; use one kind of dependency for "
                                          "a repository, either pinned with tag or sha or by version",
                                          repo, ms_dependency_describe(s->arena, pins.ptr[0]->dep),
                                          pins.ptr[0]->asker, ms_dependency_describe(s->arena, wants.ptr[0]->dep),
                                          wants.ptr[0]->asker));
  } else if (pins.len > 0) {
    Choice pinned = {0};
    ok = pick_pin(s, repo, &pins, &pinned);
    if (ok) {
      choice_list_push(next, pinned);
    }
  } else {
    ok = pick_buckets(s, repo, &wants, next);
  }
  ask_pointer_list_free(&pins);
  ask_pointer_list_free(&wants);
  return ok;
}

static int64_t compare_repo_spans(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  return ms_span_compare(*(const MsSpan *)(const void *)a, *(const MsSpan *)(const void *)b);
}

bool solver_choose(Solver *s, ChoiceList *next) {
  MsSpan *repos = MS_ARENA_NEW_ARRAY(s->arena, MsSpan, s->asks.len + 1);
  size_t count = 0;
  for (size_t i = 0; i < s->asks.len; i++) {
    if (!span_in_list(repos, count, s->asks.ptr[i].repo)) {
      repos[count++] = s->asks.ptr[i].repo;
    }
  }
  ms_sort((uint8_t *)repos, count, sizeof(MsSpan), compare_repo_spans, NULL);
  for (size_t r = 0; r < count; r++) {
    AskPointerList list = {0};
    for (size_t i = 0; i < s->asks.len; i++) {
      if (ms_span_equal(s->asks.ptr[i].repo, repos[r])) {
        ask_pointer_list_push(&list, &s->asks.ptr[i]);
      }
    }
    const bool ok = pick_repo(s, repos[r], &list, next);
    ask_pointer_list_free(&list);
    if (!ok) {
      return false;
    }
  }
  return download_choices(s, next);
}
