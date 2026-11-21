/* Unit test of dependency resolution (src/compiler/src/project/solve.c) against a table of tags, with the cases of
 * crates/ms-driver/src/project/resolve.rs. */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/resolve.h"

static int failures;
static MsArena arena;

#define CHECK(cond)                                                                                \
    do {                                                                                           \
        if (!(cond)) {                                                                             \
            fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #cond);              \
            failures++;                                                                            \
        }                                                                                          \
    } while (0)

#define WIRE "https://github.com/acme/wire.git"

/* ---- the table of repositories ---- */

typedef struct Tag {
    const char *url, *tag, *commit;
    MsPackageManifest manifest;
} Tag;

typedef struct Table {
    Tag tags[64];
    int count;
    int listed;
} Table;

static const MsDependency *dep_list(const char *spec) {
    /* "alias url kind value; ..." where kind is version, tag or sha. */
    MsDependency *deps = MS_NEW_N(&arena, MsDependency, 8);
    char *copy = ms_arena_strndup(&arena, spec, strlen(spec));
    int n = 0;
    char *outer;
    for (char *part = strtok_r(copy, ";", &outer); part != NULL; part = strtok_r(NULL, ";", &outer)) {
        char *inner;
        char *alias = strtok_r(part, " ", &inner);
        char *url = strtok_r(NULL, " ", &inner);
        char *kind = strtok_r(NULL, " ", &inner);
        char *value = strtok_r(NULL, " ", &inner);
        deps[n] = (MsDependency){.alias = alias, .url = url};
        if (strcmp(kind, "version") == 0) {
            const char *error;
            deps[n].kind = MS_DEP_VERSION;
            CHECK(ms_requirement_parse(&arena, value, &deps[n].requirement, &error));
        } else {
            deps[n].kind = strcmp(kind, "tag") == 0 ? MS_DEP_TAG : MS_DEP_SHA;
            deps[n].reference = value;
        }
        n++;
    }
    return deps;
}

static MsPackageManifest manifest(const char *version, const char *deps) {
    MsPackageManifest m = {0};
    if (version != NULL) {
        const char *error;
        m.has_version = true;
        CHECK(ms_version_parse(&arena, version, &m.version, &error));
    }
    if (deps != NULL && deps[0] != 0) {
        m.deps = dep_list(deps);
        for (const char *c = deps; *c != 0; c++) {
            m.ndeps += *c == ';';
        }
        m.ndeps++;
    }
    return m;
}

static void tag(Table *t, const char *url, const char *name, MsPackageManifest m) {
    t->tags[t->count] = (Tag){.url = url, .tag = name, .commit = ms_arena_fmt(&arena, "%040x", t->count + 1).ptr, .manifest = m};
    t->count++;
}

static void plain(Table *t, const char *url, const char *names) {
    char *copy = ms_arena_strndup(&arena, names, strlen(names));
    char *rest;
    for (char *name = strtok_r(copy, " ", &rest); name != NULL; name = strtok_r(NULL, " ", &rest)) {
        tag(t, url, name, manifest(NULL, NULL));
    }
}

static bool table_tags(void *user, MsArena *a, const char *url, const char *const **out, uint32_t *count, const char **error) {
    Table *t = user;
    t->listed++;
    const char **names = MS_NEW_N(a, const char *, 64);
    *count = 0;
    bool found = false;
    for (int i = 0; i < t->count; i++) {
        if (strcmp(ms_repo_key(a, t->tags[i].url), ms_repo_key(a, url)) == 0) {
            names[(*count)++] = t->tags[i].tag;
            found = true;
        }
    }
    if (!found) {
        *error = ms_arena_fmt(a, "no repository %s", url).ptr;
        return false;
    }
    *out = names;
    return true;
}

static bool table_fetch(void *user, MsArena *a, const char *url, const char *reference, const MsLockEntry *locked, bool nested, MsFetched *out, const char **error) {
    Table *t = user;
    (void)locked;
    (void)nested;
    for (int i = 0; i < t->count; i++) {
        if (strcmp(ms_repo_key(a, t->tags[i].url), ms_repo_key(a, url)) == 0 && (strcmp(t->tags[i].tag, reference) == 0 || strcmp(t->tags[i].commit, reference) == 0)) {
            out->entry = (MsLockEntry){.key = "", .spec = ms_arena_fmt(a, "%s#%s", url, reference).ptr, .revision = t->tags[i].commit,
                                       .sha256 = "0000000000000000000000000000000000000000000000000000000000000000"};
            out->manifest = t->tags[i].manifest;
            return true;
        }
    }
    *error = ms_arena_fmt(a, "%s has no %s", url, reference).ptr;
    return false;
}

static bool run(Table *t, const char *deps, const MsLock *old, const char *const *update, uint32_t nupdate, MsResolved *out, const char **error) {
    const MsRemote remote = {.user = t, .tags = table_tags, .fetch = table_fetch};
    const MsRoot root = {.name = "the project", .manifest = manifest(NULL, deps)};
    return ms_resolve(&arena, &root, 1, old, update, nupdate, &remote, out, error);
}

static const MsLock no_lock = {0};

static bool resolve_plain(Table *t, const char *deps, MsResolved *out, const char **error) { return run(t, deps, &no_lock, NULL, 0, out, error); }

static bool has_copy(const MsResolved *r, const char *id) {
    for (uint32_t i = 0; i < r->ncopies; i++) {
        if (strcmp(r->copies[i].id, id) == 0) {
            return true;
        }
    }
    return false;
}

static const char *root_id(const MsResolved *r, const char *alias) {
    for (uint32_t i = 0; i < r->nroots; i++) {
        if (strcmp(r->roots[i].alias, alias) == 0) {
            return r->roots[i].id;
        }
    }
    return "";
}

static const char *ids(const MsResolved *r) {
    MsBuf text = {0};
    for (uint32_t i = 0; i < r->ncopies; i++) {
        ms_buf_printf(&text, "%s%s", i > 0 ? " " : "", r->copies[i].id);
    }
    char *s = ms_arena_strndup(&arena, text.data == NULL ? "" : text.data, text.len);
    ms_buf_free(&text);
    return s;
}

/* `@a` and `@b` both need wire. */
static void diamond(Table *t, const char *a_wants, const char *b_wants, const char **deps) {
    *t = (Table){0};
    plain(t, WIRE, "v1.2.0 v1.4.2 v1.5.0 v2.0.1");
    tag(t, "https://h/a.git", "v1.0.0", manifest(NULL, ms_arena_fmt(&arena, "@wire " WIRE " version %s", a_wants).ptr));
    tag(t, "https://h/b.git", "v1.0.0", manifest(NULL, ms_arena_fmt(&arena, "@wire " WIRE " version %s", b_wants).ptr));
    *deps = "@a https://h/a.git version 1;@b https://h/b.git version 1";
}

/* ---- tests ---- */

static void test_ranges(void) {
    Table t;
    const char *deps, *error;
    MsResolved r;
    diamond(&t, "^1.2", "^1.4", &deps);
    CHECK(resolve_plain(&t, deps, &r, &error));
    CHECK(strcmp(ids(&r), "github.com/acme/wire@v1.5.0 h/a@v1.0.0 h/b@v1.0.0") == 0);
    CHECK(strcmp(root_id(&r, "@a"), "h/a@v1.0.0") == 0);
    diamond(&t, "^1.2", "=1.4.2", &deps);
    CHECK(resolve_plain(&t, deps, &r, &error) && has_copy(&r, "github.com/acme/wire@v1.4.2") && r.ncopies == 3);
    diamond(&t, "^1.2", "^2", &deps);
    CHECK(resolve_plain(&t, deps, &r, &error));
    CHECK(strcmp(ids(&r), "github.com/acme/wire@v1.5.0 github.com/acme/wire@v2.0.1 h/a@v1.0.0 h/b@v1.0.0") == 0);
}

static void test_buckets(void) {
    Table t = {0};
    MsResolved r;
    const char *error;
    plain(&t, WIRE, "v0.4.1 v0.4.5 v0.5.0");
    CHECK(resolve_plain(&t, "@x " WIRE " version ^0.4.1;@y " WIRE " version ^0.4.3;@z " WIRE " version ^0.5", &r, &error));
    CHECK(strcmp(ids(&r), "github.com/acme/wire@v0.4.5 github.com/acme/wire@v0.5.0") == 0);
    CHECK(strcmp(root_id(&r, "@x"), root_id(&r, "@y")) == 0);

    t = (Table){0};
    plain(&t, WIRE, "2026.11.0 2026.12.0 2027.1.0");
    CHECK(resolve_plain(&t, "@w " WIRE " version 2026.11", &r, &error));
    CHECK(strcmp(ids(&r), "github.com/acme/wire@2026.12.0") == 0);

    t = (Table){0};
    plain(&t, WIRE, "v1.2.0");
    CHECK(resolve_plain(&t, "@pg " WIRE " version 1;@postgres http://github.com/acme/wire/ version ^1.2", &r, &error));
    CHECK(r.ncopies == 1 && strcmp(root_id(&r, "@pg"), root_id(&r, "@postgres")) == 0);
}

static void test_withdrawn_picks(void) {
    Table t = {0};
    MsResolved r;
    const char *error;
    plain(&t, WIRE, "v1.0.5");
    tag(&t, "https://h/x.git", "v1.0.0", manifest(NULL, "@wire " WIRE " version =1.0.5"));
    tag(&t, "https://h/x.git", "v1.1.0", manifest(NULL, NULL));
    tag(&t, "https://h/w.git", "v1.0.0", manifest(NULL, NULL));
    tag(&t, "https://h/w.git", "v1.1.0", manifest(NULL, "@x https://h/x.git version =1.0.0"));
    CHECK(resolve_plain(&t, "@x https://h/x.git version 1;@w https://h/w.git version 1", &r, &error));
    CHECK(has_copy(&r, "h/x@v1.0.0") && !has_copy(&r, "h/x@v1.1.0") && has_copy(&r, "github.com/acme/wire@v1.0.5"));

    t = (Table){0};
    tag(&t, "https://h/x.git", "v1.0.0", manifest(NULL, NULL));
    tag(&t, "https://h/x.git", "v1.1.0", manifest(NULL, "@y https://h/y.git version =1.0.0"));
    tag(&t, "https://h/y.git", "v1.0.0", manifest(NULL, NULL));
    tag(&t, "https://h/y.git", "v1.1.0", manifest(NULL, "@x https://h/x.git version =1.0.0"));
    CHECK(!resolve_plain(&t, "@x https://h/x.git version 1;@y https://h/y.git version 1", &r, &error));
    CHECK(strstr(error, "do not settle") != NULL);
}

static void test_conflicts(void) {
    Table t;
    const char *deps, *error;
    MsResolved r;
    diamond(&t, "^1.2", "=1.1.0", &deps);
    CHECK(!resolve_plain(&t, deps, &r, &error));
    CHECK(strstr(error, "h/a@v1.0.0 asks ^1.2 and h/b@v1.0.0 asks =1.1.0") != NULL && strstr(error, "no tag satisfies all of them") != NULL);
    diamond(&t, "^3.0", "^3.0", &deps);
    CHECK(!resolve_plain(&t, deps, &r, &error));
    CHECK(strstr(error, "no tag of github.com/acme/wire satisfies") != NULL && strstr(error, "tags: 1.2.0, 1.4.2, 1.5.0, 2.0.1") != NULL);

    t = (Table){0};
    plain(&t, WIRE, "v1.2.0");
    tag(&t, "https://h/a.git", "v1.0.0", manifest(NULL, "@wire " WIRE " tag v1.2.0"));
    CHECK(!resolve_plain(&t, "@a https://h/a.git version 1;@wire " WIRE " version ^1.2", &r, &error));
    CHECK(strstr(error, "v1.2.0 by h/a@v1.0.0") != NULL && strstr(error, "^1.2 by the project") != NULL);

    t = (Table){0};
    plain(&t, WIRE, "v1.2.0 v1.3.0");
    CHECK(resolve_plain(&t, "@a " WIRE " tag v1.2.0;@b https://GitHub.com/acme/wire tag v1.2.0", &r, &error));
    CHECK(strcmp(ids(&r), "github.com/acme/wire@v1.2.0") == 0);
    CHECK(!resolve_plain(&t, "@a " WIRE " tag v1.2.0;@b " WIRE " tag v1.3.0", &r, &error) && strstr(error, "different commits") != NULL);

    t = (Table){0};
    tag(&t, "https://h/a.git", "v1.0.0", manifest(NULL, "@w file:///tmp/w tag v1"));
    CHECK(!resolve_plain(&t, "@a https://h/a.git version 1", &r, &error));
    CHECK(strstr(error, "a package's own dependencies must use https:// URLs") != NULL);
}

static void test_lock_and_update(void) {
    Table t;
    const char *deps, *error;
    MsResolved first, kept;
    diamond(&t, "^1.2", "^1.4", &deps);
    CHECK(resolve_plain(&t, deps, &first, &error));
    /* The lock holds wire 1.4.2 although 1.5.0 exists upstream. */
    MsLockEntry *entries = ms_resolved_lock(&arena, &first);
    for (uint32_t i = 0; i < first.ncopies; i++) {
        if (strcmp(entries[i].key, "github.com/acme/wire@v1.5.0") == 0) {
            entries[i].key = "github.com/acme/wire@v1.4.2";
            entries[i].spec = WIRE "#v1.4.2";
        }
    }
    MsLock old = {.entries = entries, .count = first.ncopies};
    t.listed = 0;
    CHECK(run(&t, deps, &old, NULL, 0, &kept, &error));
    CHECK(has_copy(&kept, "github.com/acme/wire@v1.4.2"));
    CHECK(t.listed == 0);
    const char *update[] = {"@wire"};
    MsResolved again;
    CHECK(run(&t, deps, &old, update, 1, &again, &error) && has_copy(&again, "github.com/acme/wire@v1.5.0"));
    const char *unknown[] = {"@nope"};
    CHECK(!run(&t, deps, &old, unknown, 1, &again, &error) && strstr(error, "no such dependency") != NULL);
}

static void test_version_agreement(void) {
    static const struct {
        const char *tag, *declared, *source;
        bool ok;
    } cases[] = {{"v1.4.2", "1.4.2", "version", true}, {"1.4.2", "1.4.2", "version", true}, {"v1.4.2", NULL, "version", true},
                 {"v1.4.2", "1.4.1", "version", false}, {"release-1", "9.9.9", "tag", true}};
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        Table t = {0};
        MsResolved r;
        const char *error = "";
        tag(&t, WIRE, cases[i].tag, manifest(cases[i].declared, NULL));
        const char *value = strcmp(cases[i].source, "tag") == 0 ? cases[i].tag : "1";
        const bool ok = resolve_plain(&t, ms_arena_fmt(&arena, "@wire " WIRE " %s %s", cases[i].source, value).ptr, &r, &error);
        if (ok != cases[i].ok) {
            fprintf(stderr, "%s %s: ok=%d\n", cases[i].tag, cases[i].declared != NULL ? cases[i].declared : "none", ok);
            failures++;
        }
        if (!ok) {
            CHECK(strstr(error, "holds ms.toml version 1.4.1, not 1.4.2") != NULL && strstr(error, "ask the author to fix the tag") != NULL && strstr(error, "=1.4.1") != NULL);
        }
    }
}

static void test_commit_pin(void) {
    Table t = {0};
    MsResolved r;
    const char *error;
    tag(&t, WIRE, "v1.0.0", manifest(NULL, NULL));
    const char *sha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    tag(&t, WIRE, sha, manifest("3.0.0", NULL));
    t.tags[1].commit = t.tags[0].commit;
    CHECK(resolve_plain(&t, ms_arena_fmt(&arena, "@wire " WIRE " sha %s", sha).ptr, &r, &error));
    CHECK(strcmp(ids(&r), ms_arena_fmt(&arena, "github.com/acme/wire@%s", sha).ptr) == 0);
}

int main(void) {
    test_ranges();
    test_buckets();
    test_withdrawn_picks();
    test_conflicts();
    test_lock_and_update();
    test_version_agreement();
    test_commit_pin();
    ms_arena_free(&arena);
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
