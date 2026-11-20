/* Dependency resolution (resolve.h). Maps and sets of the Rust version are sorted arrays here: a project has a handful of
 * repositories, and sorted order is what the Rust BTreeMaps iterated in, so errors and picks come out the same. */
#include <stdlib.h>
#include <string.h>

#include "ms/resolve.h"

/* The most rounds before the resolver gives up on a graph whose picks keep changing. */
enum { SOLVE_MAX_ROUNDS = 64 };

/* ---- dependencies ---- */

const char *ms_dependency_describe(MsArena *a, const MsDependency *d) {
    return d->kind == MS_DEP_VERSION ? ms_requirement_text(a, &d->requirement) : d->reference;
}

const char *ms_dependency_spec(MsArena *a, const MsDependency *d) {
    return d->kind == MS_DEP_VERSION ? NULL : ms_arena_fmt(a, "%s#%s", d->url, d->reference).ptr;
}

/* A requirement that names the release before `v`, as a hint in an error. */
static const char *solve_earlier(MsArena *a, const MsVersion *v) {
    const unsigned long long major = v->major, minor = v->minor, patch = v->patch;
    if (v->patch > 0) {
        return ms_arena_fmt(a, "%llu.%llu.%llu", major, minor, patch - 1).ptr;
    }
    if (v->minor > 0) {
        return ms_arena_fmt(a, "%llu.%llu", major, minor - 1).ptr;
    }
    return ms_arena_fmt(a, "%llu", v->major > 0 ? major - 1 : 0ULL).ptr;
}

const char *ms_check_version_agrees(MsArena *a, const char *what, const char *url, const char *reference, const MsPackageManifest *manifest) {
    MsVersion tagged;
    if (!ms_version_of_tag(a, reference, &tagged) || !manifest->has_version || ms_version_compare(&tagged, &manifest->version) == 0) {
        return NULL;
    }
    return ms_arena_fmt(a, "%s tag %s of %s holds ms.toml version %s, not %s; ask the author to fix the tag, or require an earlier version such as =%s",
                        what, reference, url, ms_version_text(a, &manifest->version), ms_version_text(a, &tagged), solve_earlier(a, &tagged)).ptr;
}

/* ---- state ---- */

/* A requirement some manifest makes of a repository. */
typedef struct SolveAsk {
    const char *asker; /* `the project` or a copy's id */
    const MsDependency *dep;
    const char *repo;
    bool nested;
} SolveAsk;

/* A copy to build: the repository and bucket (or pin) it stands for. */
typedef struct SolveGroup {
    const char *repo;
    bool has_bucket;
    MsBucket bucket;
} SolveGroup;

typedef struct SolveChoice {
    SolveGroup group;
    const char *url, *reference;
} SolveChoice;

typedef struct SolveDownload {
    const char *url, *reference;
    MsFetched fetched;
} SolveDownload;

typedef struct SolveTags {
    const char *repo;
    MsVersion *versions;
    const char **tags;
    uint32_t count;
} SolveTags;

typedef struct SolveState {
    MsArena *arena;
    const MsLock *old;
    const char *const *update;
    uint32_t nupdate;
    const MsRemote *remote;
    MsBuf downloads; /* SolveDownload */
    MsBuf tag_lists; /* SolveTags */
    const char *error;
} SolveState;

static bool solve_fail(SolveState *s, const char *message) {
    s->error = message;
    return false;
}

static bool solve_updating(const SolveState *s, const char *alias) {
    for (uint32_t i = 0; i < s->nupdate; i++) {
        if (strcmp(s->update[i], alias) == 0) {
            return true;
        }
    }
    return false;
}

static int solve_group_compare(const SolveGroup *x, const SolveGroup *y) {
    const int repo = strcmp(x->repo, y->repo);
    if (repo != 0) {
        return repo;
    }
    if (x->has_bucket != y->has_bucket) {
        return x->has_bucket ? 1 : -1;
    }
    return x->has_bucket ? ms_bucket_compare(x->bucket, y->bucket) : 0;
}

static int solve_choice_order(const void *x, const void *y) { return solve_group_compare(&((const SolveChoice *)x)->group, &((const SolveChoice *)y)->group); }

static int solve_ask_order(const void *x, const void *y) {
    const SolveAsk *left = x, *right = y;
    const int asker = strcmp(left->asker, right->asker);
    return asker != 0 ? asker : strcmp(left->dep->alias, right->dep->alias);
}

static SolveDownload *solve_download(SolveState *s, const char *url, const char *reference) {
    for (size_t i = 0; i < MS_VEC_LEN(s->downloads, SolveDownload); i++) {
        SolveDownload *d = &MS_VEC_AT(s->downloads, SolveDownload, i);
        if (strcmp(d->url, url) == 0 && strcmp(d->reference, reference) == 0) {
            return d;
        }
    }
    return NULL;
}

/* The first old lock entry whose spec is `url#reference`. */
static const MsLockEntry *solve_locked_spec(const SolveState *s, const char *url, const char *reference) {
    const char *spec = ms_arena_fmt(s->arena, "%s#%s", url, reference).ptr;
    for (uint32_t i = 0; i < s->old->count; i++) {
        if (strcmp(s->old->entries[i].spec, spec) == 0) {
            return &s->old->entries[i];
        }
    }
    return NULL;
}

/* Fetches a copy once and checks that its manifest agrees with its tag. */
static bool solve_fetch(SolveState *s, const char *url, const char *reference, const MsLockEntry *locked, bool nested) {
    MsFetched fetched;
    const char *error;
    if (!s->remote->fetch(s->remote->user, s->arena, url, reference, locked, nested, &fetched, &error)) {
        return solve_fail(s, error);
    }
    const char *mismatch = ms_check_version_agrees(s->arena, "package", url, reference, &fetched.manifest);
    if (mismatch != NULL) {
        return solve_fail(s, mismatch);
    }
    SolveDownload d = {.url = url, .reference = reference, .fetched = fetched};
    MS_VEC_PUSH(s->downloads, SolveDownload, d);
    return true;
}

/* ---- asks ---- */

static void solve_add_asks(SolveState *s, MsBuf *asks, const char *asker, const MsPackageManifest *manifest, bool nested) {
    for (uint32_t i = 0; i < manifest->ndeps; i++) {
        const MsDependency *dep = &manifest->deps[i];
        const SolveAsk ask = {.asker = asker, .dep = dep, .repo = ms_repo_key(s->arena, dep->url), .nested = nested};
        MS_VEC_PUSH(*asks, SolveAsk, ask);
    }
}

/* Every requirement of the roots and of the copies picked so far, sorted by asker and name. */
static void solve_collect(SolveState *s, const MsRoot *roots, uint32_t nroots, const MsBuf *chosen, MsBuf *asks) {
    for (uint32_t i = 0; i < nroots; i++) {
        solve_add_asks(s, asks, roots[i].name, &roots[i].manifest, false);
    }
    /* A copy is a node once, however many ask for it; its own requirements count while it is picked. */
    const size_t count = MS_VEC_LEN(*chosen, SolveChoice);
    for (size_t i = 0; i < count; i++) {
        const SolveChoice *choice = &MS_VEC_AT(*chosen, SolveChoice, i);
        bool seen = false;
        for (size_t k = 0; k < i && !seen; k++) {
            const SolveChoice *earlier = &MS_VEC_AT(*chosen, SolveChoice, k);
            seen = strcmp(earlier->url, choice->url) == 0 && strcmp(earlier->reference, choice->reference) == 0;
        }
        const SolveDownload *d = seen ? NULL : solve_download(s, choice->url, choice->reference);
        if (d != NULL) {
            solve_add_asks(s, asks, ms_copy_id(s->arena, choice->url, choice->reference), &d->fetched.manifest, true);
        }
    }
    const size_t n = MS_VEC_LEN(*asks, SolveAsk);
    if (n > 1) {
        qsort(asks->data, n, sizeof(SolveAsk), solve_ask_order);
    }
}

/* ---- tags ---- */

static const SolveTags *solve_tags_of(SolveState *s, const char *url) {
    const char *repo = ms_repo_key(s->arena, url);
    for (size_t i = 0; i < MS_VEC_LEN(s->tag_lists, SolveTags); i++) {
        if (strcmp(MS_VEC_AT(s->tag_lists, SolveTags, i).repo, repo) == 0) {
            return &MS_VEC_AT(s->tag_lists, SolveTags, i);
        }
    }
    const char *const *names;
    uint32_t count;
    const char *error;
    if (!s->remote->tags(s->remote->user, s->arena, url, &names, &count, &error)) {
        solve_fail(s, error);
        return NULL;
    }
    SolveTags list = {.repo = repo, .versions = MS_NEW_N(s->arena, MsVersion, count + 1), .tags = MS_NEW_N(s->arena, const char *, count + 1)};
    for (uint32_t i = 0; i < count; i++) {
        MsVersion version;
        if (!ms_version_of_tag(s->arena, names[i], &version)) {
            continue;
        }
        for (uint32_t k = 0; k < list.count; k++) {
            if (ms_version_compare(&list.versions[k], &version) == 0) {
                solve_fail(s, ms_arena_fmt(s->arena, "%s has both %s and %s for version %s; delete one of the tags", url, list.tags[k], names[i], ms_version_text(s->arena, &version)).ptr);
                return NULL;
            }
        }
        list.versions[list.count] = version;
        list.tags[list.count] = names[i];
        list.count++;
    }
    /* Sorted by version, then tag (insertion sort: the lists are short). */
    for (uint32_t i = 1; i < list.count; i++) {
        for (uint32_t k = i; k > 0; k--) {
            int order = ms_version_compare(&list.versions[k - 1], &list.versions[k]);
            if (order == 0) {
                order = strcmp(list.tags[k - 1], list.tags[k]);
            }
            if (order <= 0) {
                break;
            }
            const MsVersion v = list.versions[k];
            list.versions[k] = list.versions[k - 1];
            list.versions[k - 1] = v;
            const char *t = list.tags[k];
            list.tags[k] = list.tags[k - 1];
            list.tags[k - 1] = t;
        }
    }
    MS_VEC_PUSH(s->tag_lists, SolveTags, list);
    return &MS_VEC_AT(s->tag_lists, SolveTags, MS_VEC_LEN(s->tag_lists, SolveTags) - 1);
}

/* ---- picking ---- */

static bool solve_satisfies(const MsDependency *dep, const MsVersion *version) {
    return dep->kind == MS_DEP_VERSION && version != NULL && ms_requirement_matches(&dep->requirement, version);
}

static bool solve_all_satisfy(const SolveAsk *const *members, uint32_t count, const MsVersion *version) {
    for (uint32_t i = 0; i < count; i++) {
        if (!solve_satisfies(members[i]->dep, version)) {
            return false;
        }
    }
    return true;
}

static const char *solve_join(MsArena *a, const char *const *parts, uint32_t count, const char *separator) {
    MsBuf text = {0};
    for (uint32_t i = 0; i < count; i++) {
        if (i > 0) {
            ms_buf_puts(&text, separator);
        }
        ms_buf_puts(&text, parts[i]);
    }
    char *joined = ms_arena_strndup(a, text.data == NULL ? "" : text.data, text.len);
    ms_buf_free(&text);
    return joined;
}

/* The highest tag in `bucket` that satisfies every requirement. */
static const char *solve_best(SolveState *s, const char *repo, MsBucket bucket, const SolveAsk *const *members, uint32_t nmembers, const SolveTags *listed) {
    MsArena *a = s->arena;
    bool by_one = false;
    for (uint32_t i = listed->count; i-- > 0;) {
        const MsVersion *v = &listed->versions[i];
        if (ms_bucket_equal(ms_version_bucket(v), bucket) && solve_all_satisfy(members, nmembers, v)) {
            return listed->tags[i];
        }
    }
    const char **asked = MS_NEW_N(a, const char *, nmembers + 1);
    for (uint32_t i = 0; i < nmembers; i++) {
        asked[i] = ms_arena_fmt(a, "%s asks %s", members[i]->asker, ms_dependency_describe(a, members[i]->dep)).ptr;
        for (uint32_t k = 0; k < listed->count && !by_one && nmembers > 1; k++) {
            by_one = ms_bucket_equal(ms_version_bucket(&listed->versions[k]), bucket) && solve_satisfies(members[i]->dep, &listed->versions[k]);
        }
    }
    const char **available = MS_NEW_N(a, const char *, listed->count + 1);
    for (uint32_t i = 0; i < listed->count; i++) {
        available[i] = ms_version_text(a, &listed->versions[i]);
    }
    const char *who = solve_join(a, asked, nmembers, " and ");
    const char *tags = solve_join(a, available, listed->count, ", ");
    if (by_one) {
        solve_fail(s, ms_arena_fmt(a, "%s: %s; no tag satisfies all of them (tags: %s)", repo, who, tags).ptr);
    } else {
        solve_fail(s, ms_arena_fmt(a, "no tag of %s satisfies %s (tags: %s)", repo, who, listed->count == 0 ? "none" : tags).ptr);
    }
    return NULL;
}

/* One copy for all pins of a repository, which must name one commit. */
static bool solve_pick_pin(SolveState *s, const char *repo, const SolveAsk *const *pins, uint32_t npins, SolveChoice *out) {
    MsArena *a = s->arena;
    const SolveAsk *chosen_by = NULL;
    const char *chosen_url = NULL, *chosen_reference = NULL, *first_commit = NULL;
    for (uint32_t i = 0; i < npins; i++) {
        const SolveAsk *ask = pins[i];
        const char *reference = ask->dep->reference;
        if (solve_download(s, ask->dep->url, reference) == NULL) {
            const MsLockEntry *locked = solve_updating(s, ask->dep->alias) ? NULL : solve_locked_spec(s, ask->dep->url, reference);
            if (!solve_fetch(s, ask->dep->url, reference, locked, ask->nested)) {
                return false;
            }
        }
        const char *commit = solve_download(s, ask->dep->url, reference)->fetched.entry.revision;
        if (chosen_by == NULL) {
            chosen_by = ask;
            chosen_url = ask->dep->url;
            chosen_reference = reference;
            first_commit = commit;
            continue;
        }
        if (strcmp(first_commit, commit) != 0) {
            return solve_fail(s, ms_arena_fmt(a, "%s is pinned to %s by %s and to %s by %s, which are different commits; pin one", repo,
                                              ms_dependency_describe(a, chosen_by->dep), chosen_by->asker, ms_dependency_describe(a, ask->dep), ask->asker).ptr);
        }
        /* Prefer a tag over a commit as the copy's name, then the smaller spelling. */
        const int left_hex = ms_is_hex(chosen_reference, 40), right_hex = ms_is_hex(reference, 40);
        int order = left_hex - right_hex;
        if (order == 0) {
            order = strcmp(reference, chosen_reference);
        }
        if (order > 0) {
            chosen_by = ask;
            chosen_url = ask->dep->url;
            chosen_reference = reference;
        }
    }
    if (chosen_by == NULL) {
        return solve_fail(s, ms_arena_fmt(a, "%s has no pin", repo).ptr);
    }
    *out = (SolveChoice){.group = {.repo = repo}, .url = chosen_url, .reference = chosen_reference};
    return true;
}

/* The old lock's tag for `repo` in `bucket` that every member still accepts, or NULL. */
static const char *solve_locked_tag(SolveState *s, const char *repo, MsBucket bucket, const SolveAsk *const *members, uint32_t nmembers) {
    const char *prefix = ms_arena_fmt(s->arena, "%s@", repo).ptr;
    for (uint32_t i = 0; i < s->old->count; i++) {
        const MsLockEntry *entry = &s->old->entries[i];
        const char *id = ms_spec_id(s->arena, entry->spec);
        const char *hash = strchr(entry->spec, '#');
        MsVersion version;
        if (id == NULL || strncmp(id, prefix, strlen(prefix)) != 0 || !ms_version_of_tag(s->arena, hash + 1, &version)) {
            continue;
        }
        if (ms_bucket_equal(ms_version_bucket(&version), bucket) && solve_all_satisfy(members, nmembers, &version)) {
            return hash + 1;
        }
    }
    return NULL;
}

/* The choices for the repository `repo`, whose asks are `list`. */
static bool solve_choose_repo(SolveState *s, const char *repo, const SolveAsk *const *list, uint32_t count, MsBuf *next) {
    MsArena *a = s->arena;
    const SolveAsk **pins = MS_NEW_N(a, const SolveAsk *, count + 1);
    const SolveAsk **wants = MS_NEW_N(a, const SolveAsk *, count + 1);
    uint32_t npins = 0, nwants = 0;
    for (uint32_t i = 0; i < count; i++) {
        const SolveAsk *ask = list[i];
        if (ask->nested && strncmp(ask->dep->url, "https://", 8) != 0) {
            return solve_fail(s, ms_arena_fmt(a, "%s depends on %s = %s; a package's own dependencies must use https:// URLs, because file:// reads the machine running ms install", ask->asker, ask->dep->alias, ask->dep->url).ptr);
        }
        if (ask->dep->kind == MS_DEP_VERSION) {
            wants[nwants++] = ask;
        } else {
            pins[npins++] = ask;
        }
    }
    if (npins > 0 && nwants > 0) {
        return solve_fail(s, ms_arena_fmt(a, "%s is needed at %s by %s and at %s by %s; use one kind of dependency for a repository, either pinned with tag or sha or by version", repo,
                                          ms_dependency_describe(a, pins[0]->dep), pins[0]->asker, ms_dependency_describe(a, wants[0]->dep), wants[0]->asker).ptr);
    }
    if (npins > 0) {
        SolveChoice pinned;
        if (!solve_pick_pin(s, repo, pins, npins, &pinned)) {
            return false;
        }
        MS_VEC_PUSH(*next, SolveChoice, pinned);
        return true;
    }
    /* One copy per compatibility bucket, in bucket order. */
    MsBucket *buckets = MS_NEW_N(a, MsBucket, nwants + 1);
    uint32_t nbuckets = 0;
    for (uint32_t i = 0; i < nwants; i++) {
        const MsBucket bucket = ms_requirement_bucket(&wants[i]->dep->requirement);
        uint32_t at = 0;
        while (at < nbuckets && ms_bucket_compare(buckets[at], bucket) < 0) {
            at++;
        }
        if (at < nbuckets && ms_bucket_equal(buckets[at], bucket)) {
            continue;
        }
        memmove(buckets + at + 1, buckets + at, (nbuckets - at) * sizeof(MsBucket));
        buckets[at] = bucket;
        nbuckets++;
    }
    const char *url = wants[0]->dep->url;
    for (uint32_t b = 0; b < nbuckets; b++) {
        const SolveAsk **members = MS_NEW_N(a, const SolveAsk *, nwants + 1);
        uint32_t nmembers = 0;
        bool updating = false;
        for (uint32_t i = 0; i < nwants; i++) {
            if (ms_bucket_equal(ms_requirement_bucket(&wants[i]->dep->requirement), buckets[b])) {
                members[nmembers++] = wants[i];
                updating |= solve_updating(s, wants[i]->dep->alias);
            }
        }
        const char *reference = updating ? NULL : solve_locked_tag(s, repo, buckets[b], members, nmembers);
        if (reference == NULL) {
            const SolveTags *listed = solve_tags_of(s, url);
            if (listed == NULL) {
                return false;
            }
            reference = solve_best(s, repo, buckets[b], members, nmembers, listed);
            if (reference == NULL) {
                return false;
            }
        }
        const SolveChoice choice = {.group = {.repo = repo, .has_bucket = true, .bucket = buckets[b]}, .url = url, .reference = reference};
        MS_VEC_PUSH(*next, SolveChoice, choice);
    }
    return true;
}

/* The picks for every repository the asks reach; each is downloaded. */
static bool solve_choose(SolveState *s, const MsBuf *asks, MsBuf *next) {
    const size_t count = MS_VEC_LEN(*asks, SolveAsk);
    const SolveAsk *all = count > 0 ? ms_buf_items(asks) : NULL;
    /* Repositories in sorted order, each with its asks in the order they were sorted. */
    const char **repos = MS_NEW_N(s->arena, const char *, count + 1);
    uint32_t nrepos = 0;
    for (size_t i = 0; i < count; i++) {
        uint32_t at = 0;
        while (at < nrepos && strcmp(repos[at], all[i].repo) < 0) {
            at++;
        }
        if (at < nrepos && strcmp(repos[at], all[i].repo) == 0) {
            continue;
        }
        memmove(repos + at + 1, repos + at, (nrepos - at) * sizeof(const char *));
        repos[at] = all[i].repo;
        nrepos++;
    }
    for (uint32_t r = 0; r < nrepos; r++) {
        const SolveAsk **list = MS_NEW_N(s->arena, const SolveAsk *, count + 1);
        uint32_t n = 0;
        for (size_t i = 0; i < count; i++) {
            if (strcmp(all[i].repo, repos[r]) == 0) {
                list[n++] = &all[i];
            }
        }
        if (!solve_choose_repo(s, repos[r], list, n, next)) {
            return false;
        }
    }
    const size_t nchoices = MS_VEC_LEN(*next, SolveChoice);
    if (nchoices > 1) {
        qsort(next->data, nchoices, sizeof(SolveChoice), solve_choice_order);
    }
    /* Make sure every choice is downloaded and its manifest agrees with its tag. */
    for (size_t i = 0; i < nchoices; i++) {
        const SolveChoice *choice = &MS_VEC_AT(*next, SolveChoice, i);
        if (solve_download(s, choice->url, choice->reference) != NULL) {
            continue;
        }
        bool nested = false;
        const char *repo = ms_repo_key(s->arena, choice->url);
        for (size_t k = 0; k < count && !nested; k++) {
            nested = all[k].nested && strcmp(ms_repo_key(s->arena, all[k].dep->url), repo) == 0;
        }
        if (!solve_fetch(s, choice->url, choice->reference, solve_locked_spec(s, choice->url, choice->reference), nested)) {
            return false;
        }
    }
    return true;
}

static bool solve_same(const MsBuf *x, const MsBuf *y) {
    const size_t n = MS_VEC_LEN(*x, SolveChoice);
    if (n != MS_VEC_LEN(*y, SolveChoice)) {
        return false;
    }
    for (size_t i = 0; i < n; i++) {
        const SolveChoice *left = &MS_VEC_AT(*x, SolveChoice, i), *right = &MS_VEC_AT(*y, SolveChoice, i);
        if (solve_group_compare(&left->group, &right->group) != 0 || strcmp(left->url, right->url) != 0 || strcmp(left->reference, right->reference) != 0) {
            return false;
        }
    }
    return true;
}

/* ---- the result ---- */

static const SolveChoice *solve_group_of(const MsBuf *chosen, const SolveAsk *ask) {
    SolveGroup group = {.repo = ask->repo};
    if (ask->dep->kind == MS_DEP_VERSION) {
        group.has_bucket = true;
        group.bucket = ms_requirement_bucket(&ask->dep->requirement);
    }
    for (size_t i = 0; i < MS_VEC_LEN(*chosen, SolveChoice); i++) {
        if (solve_group_compare(&MS_VEC_AT(*chosen, SolveChoice, i).group, &group) == 0) {
            return &MS_VEC_AT(*chosen, SolveChoice, i);
        }
    }
    return NULL;
}

static int solve_copy_order(const void *x, const void *y) { return strcmp(((const MsCopy *)x)->id, ((const MsCopy *)y)->id); }

static int solve_root_order(const void *x, const void *y) { return strcmp(((const MsRootName *)x)->alias, ((const MsRootName *)y)->alias); }

static bool solve_finish(SolveState *s, const MsRoot *roots, uint32_t nroots, const MsBuf *asks, const MsBuf *chosen, MsResolved *out) {
    MsArena *a = s->arena;
    const size_t nchoices = MS_VEC_LEN(*chosen, SolveChoice);
    out->copies = MS_NEW_N(a, MsCopy, nchoices + 1);
    for (size_t i = 0; i < nchoices; i++) {
        const SolveChoice *choice = &MS_VEC_AT(*chosen, SolveChoice, i);
        const SolveDownload *d = solve_download(s, choice->url, choice->reference);
        if (d == NULL) {
            continue;
        }
        MsCopy copy = {.id = ms_copy_id(a, choice->url, choice->reference), .url = choice->url, .reference = choice->reference, .entry = d->fetched.entry, .manifest = d->fetched.manifest};
        copy.entry.key = copy.id;
        copy.entry.spec = ms_arena_fmt(a, "%s#%s", choice->url, choice->reference).ptr;
        out->copies[out->ncopies++] = copy;
    }
    qsort(out->copies, out->ncopies, sizeof(MsCopy), solve_copy_order);
    const size_t nasks = MS_VEC_LEN(*asks, SolveAsk);
    out->roots = MS_NEW_N(a, MsRootName, nasks + 1);
    for (size_t i = 0; i < nasks; i++) {
        const SolveAsk *ask = &MS_VEC_AT(*asks, SolveAsk, i);
        bool is_root = false;
        for (uint32_t r = 0; r < nroots && !is_root; r++) {
            is_root = strcmp(roots[r].name, ask->asker) == 0;
        }
        if (!is_root) {
            continue;
        }
        const SolveChoice *choice = solve_group_of(chosen, ask);
        if (choice == NULL) {
            return solve_fail(s, ms_arena_fmt(a, "%s was not resolved", ask->dep->alias).ptr);
        }
        const char *id = ms_copy_id(a, choice->url, choice->reference);
        uint32_t at = 0;
        while (at < out->nroots && strcmp(out->roots[at].alias, ask->dep->alias) != 0) {
            at++;
        }
        out->roots[at] = (MsRootName){.alias = ask->dep->alias, .id = id};
        out->nroots += at == out->nroots;
    }
    qsort(out->roots, out->nroots, sizeof(MsRootName), solve_root_order);
    return true;
}

bool ms_resolve(MsArena *a, const MsRoot *roots, uint32_t nroots, const MsLock *old, const char *const *update, uint32_t nupdate, const MsRemote *remote, MsResolved *out, const char **error) {
    *out = (MsResolved){0};
    SolveState s = {.arena = a, .old = old, .update = update, .nupdate = nupdate, .remote = remote};
    MsBuf chosen = {0};
    bool ok = false;
    bool done = false;
    MsBuf matched = {0}; /* the update names some ask carries */
    for (int round = 0; round < SOLVE_MAX_ROUNDS && !done; round++) {
        MsBuf asks = {0}, next = {0};
        solve_collect(&s, roots, nroots, &chosen, &asks);
        for (size_t i = 0; i < MS_VEC_LEN(asks, SolveAsk); i++) {
            const char *alias = MS_VEC_AT(asks, SolveAsk, i).dep->alias;
            if (solve_updating(&s, alias)) {
                MS_VEC_PUSH(matched, const char *, alias);
            }
        }
        if (!solve_choose(&s, &asks, &next)) {
            ms_buf_free(&asks);
            ms_buf_free(&next);
            break;
        }
        if (solve_same(&next, &chosen)) {
            done = true;
            ok = true;
            for (uint32_t i = 0; i < nupdate && ok; i++) {
                bool found = false;
                for (size_t k = 0; k < MS_VEC_LEN(matched, const char *) && !found; k++) {
                    found = strcmp(MS_VEC_AT(matched, const char *, k), update[i]) == 0;
                }
                if (!found) {
                    ok = solve_fail(&s, ms_arena_fmt(a, "--update %s: no such dependency", update[i]).ptr);
                }
            }
            ok = ok && solve_finish(&s, roots, nroots, &asks, &next, out);
        }
        ms_buf_free(&asks);
        ms_buf_free(&chosen);
        chosen = next;
    }
    if (!ok && s.error == NULL) {
        const char *moving = MS_VEC_LEN(chosen, SolveChoice) > 0 ? MS_VEC_AT(chosen, SolveChoice, 0).group.repo : "a repository";
        solve_fail(&s, ms_arena_fmt(a, "dependencies do not settle after %d rounds; the picks for %s keep changing, so pin one version with tag or sha", SOLVE_MAX_ROUNDS, moving).ptr);
    }
    ms_buf_free(&chosen);
    ms_buf_free(&matched);
    ms_buf_free(&s.downloads);
    ms_buf_free(&s.tag_lists);
    if (!ok) {
        *error = s.error;
    }
    return ok;
}

MsLockEntry *ms_resolved_lock(MsArena *a, const MsResolved *resolved) {
    MsLockEntry *entries = MS_NEW_N(a, MsLockEntry, resolved->ncopies + 1);
    for (uint32_t i = 0; i < resolved->ncopies; i++) {
        entries[i] = resolved->copies[i].entry;
    }
    return entries;
}
