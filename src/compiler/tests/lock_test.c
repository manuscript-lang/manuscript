/* Unit test of ms.lock and dependency specs (src/compiler/src/project/lock.c), with the cases of
 * crates/ms-driver/src/project/{packages,resolve}.rs. */
#include <stdio.h>
#include <string.h>

#include "ms/lock.h"

static int failures;
static MsArena arena;

#define CHECK(cond)                                                                                \
    do {                                                                                           \
        if (!(cond)) {                                                                             \
            fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #cond);              \
            failures++;                                                                            \
        }                                                                                          \
    } while (0)

#define HASH "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
#define COMMIT "0123456789abcdef0123456789abcdef01234567"

static void test_specs(void) {
    static const char *const bad[] = {"-oX#v1", "ext::sh -c x#v1", "ssh://h/x#v1", "/etc#v1", "https://h/x.git#--upload-pack=x", "https://h/x.git#a..b", "https://h/x.git", "https://h/x.git#", "#v1", "https://h/x.git#a b"};
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        if (ms_spec_check(&arena, bad[i]) == NULL) {
            fprintf(stderr, "accepted spec \"%s\"\n", bad[i]);
            failures++;
        }
    }
    static const char *const good[] = {"https://h/x.git#v1.0.0", "https://h/x.git#v2026.11.0", "https://h/x.git#v2027.1.3", "file:///tmp/x#v1"};
    for (size_t i = 0; i < sizeof good / sizeof good[0]; i++) {
        CHECK(ms_spec_check(&arena, good[i]) == NULL);
    }
    CHECK(strcmp(ms_spec_check(&arena, "ssh://h/x#v1"), "dependency URL \"ssh://h/x\" must start with https:// (or file:// for a local repository); other git transports are not supported") == 0);
    CHECK(strstr(ms_spec_check(&arena, "https://h/x.git"), "invalid dependency \"https://h/x.git\"; write") != NULL);
}

static void test_keys(void) {
    static const char *const urls[] = {"https://github.com/acme/wire.git", "http://GitHub.com/acme/wire", "https://github.com/acme/wire/"};
    for (size_t i = 0; i < 3; i++) {
        CHECK(strcmp(ms_repo_key(&arena, urls[i]), "github.com/acme/wire") == 0);
    }
    CHECK(strcmp(ms_repo_key(&arena, "file:///tmp/x"), "file/tmp/x") == 0);
    CHECK(strcmp(ms_repo_key(&arena, "https://github.com/Acme/wire"), ms_repo_key(&arena, urls[0])) != 0);
    CHECK(strcmp(ms_copy_id(&arena, urls[0], "v1.4.2"), "github.com/acme/wire@v1.4.2") == 0);
    CHECK(strcmp(ms_spec_id(&arena, "https://h/x.git#v1"), "h/x@v1") == 0);
    CHECK(ms_spec_id(&arena, "https://h/x.git") == NULL);
}

static bool parse(const char *text, MsLock *lock, const char **error) {
    MsProjectError err = {0};
    const bool ok = ms_lock_parse(&arena, text, lock, &err);
    *error = ok ? "" : ms_project_error_text(&arena, &err);
    return ok;
}

static void test_lock(void) {
    const char *line = "\"h/x@v2026.11.0\" = \"https://h/x.git#v2026.11.0 " COMMIT " sha256:" HASH "\"\n";
    MsLock lock;
    const char *error;
    CHECK(parse(line, &lock, &error) && lock.count == 1);
    CHECK(strcmp(lock.entries[0].spec, "https://h/x.git#v2026.11.0") == 0 && strcmp(lock.entries[0].revision, COMMIT) == 0);
    const char *text = ms_lock_text(&arena, lock.entries, lock.count);
    CHECK(strlen(text) > strlen(line) && strcmp(text + strlen(text) - strlen(line), line) == 0);
    MsVersion version;
    CHECK(ms_lock_entry_version(&arena, &lock.entries[0], &version) && version.major == 2026);
    CHECK(ms_lock_find(&lock, "h/x@v2026.11.0") != NULL && ms_lock_find(&lock, "h/y@v1") == NULL);

    CHECK(!parse("\"h/y@v1\" = \"https://h/x.git#v1 " COMMIT " sha256:" HASH "\"\n", &lock, &error) && strstr(error, "keyed") != NULL);
    CHECK(strncmp(error, "ms.lock line 1 is keyed h/y@v1, but its source is https://h/x.git#v1;", 66) == 0);
    CHECK(!parse("nonsense\n", &lock, &error) && strncmp(error, "ms.lock line 1 is not `", 23) == 0);
    CHECK(!parse("\"h/x@v1\" = \"https://h/x.git#v1 abc sha256:" HASH "\"\n", &lock, &error) && strstr(error, "40-digit commit") != NULL);
    CHECK(!parse("\"h/x@v1\" = \"ssh://h/x#v1 " COMMIT " sha256:" HASH "\"\n", &lock, &error) && strstr(error, "ms.lock line 1: dependency URL") != NULL);
    const char *entry = "\"h/x@v1\" = \"https://h/x.git#v1 " COMMIT " sha256:" HASH "\"\n";
    CHECK(parse(ms_arena_fmt(&arena, "\xef\xbb\xbf# comment\n\n%s", entry).ptr, &lock, &error) && lock.count == 1);
    CHECK(!parse(ms_arena_fmt(&arena, "%s%s", entry, entry).ptr, &lock, &error) && strstr(error, "ms.lock line 2 repeats h/x@v1;") != NULL);
    CHECK(parse("", &lock, &error) && lock.count == 0);

    MsLockEntry unsorted[2] = {{"h/z@v1", "https://h/z#v1", COMMIT, HASH}, {"h/a@v1", "https://h/a#v1", COMMIT, HASH}};
    text = ms_lock_text(&arena, unsorted, 2);
    CHECK(strstr(text, "\"h/a@v1\"") < strstr(text, "\"h/z@v1\""));
}

int main(void) {
    test_specs();
    test_keys();
    test_lock();
    ms_arena_free(&arena);
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
