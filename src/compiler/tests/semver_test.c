/* Unit test of versions and requirements (src/compiler/src/project/semver.c), with the cases of
 * crates/ms-driver/src/project/semver.rs. */
#include <stdio.h>
#include <string.h>

#include "ms/semver.h"

static int failures;
static MsArena arena;

#define CHECK(cond)                                                                                \
    do {                                                                                           \
        if (!(cond)) {                                                                             \
            fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #cond);              \
            failures++;                                                                            \
        }                                                                                          \
    } while (0)

static MsVersion v(const char *text) {
    MsVersion version = {0};
    const char *error;
    if (!ms_version_parse(&arena, text, &version, &error)) {
        fprintf(stderr, "version %s: %s\n", text, error);
        failures++;
    }
    return version;
}

static MsRequirement r(const char *text) {
    MsRequirement requirement = {0};
    const char *error;
    if (!ms_requirement_parse(&arena, text, &requirement, &error)) {
        fprintf(stderr, "requirement %s: %s\n", text, error);
        failures++;
    }
    return requirement;
}

static bool matches(const char *requirement, const char *version) {
    const MsRequirement req = r(requirement);
    const MsVersion ver = v(version);
    return ms_requirement_matches(&req, &ver);
}

static void test_versions(void) {
    static const char *const good[] = {"1.2.3", "0.0.0", "2026.11.0", "1.0.0-rc.1", "1.0.0-alpha"};
    for (size_t i = 0; i < sizeof good / sizeof good[0]; i++) {
        const MsVersion version = v(good[i]);
        CHECK(strcmp(ms_version_text(&arena, &version), good[i]) == 0);
    }
    static const char *const bad[] = {"1.2", "1.2.3.4", "v1.2.3", "01.2.3", "1.2.x", "", "1.2.3-", "1.2.3-01", "1.2.3+b", "-1.2.3", "99999999999999999999.0.0"};
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        MsVersion version;
        const char *error;
        if (ms_version_parse(&arena, bad[i], &version, &error)) {
            fprintf(stderr, "accepted version \"%s\"\n", bad[i]);
            failures++;
        }
    }
    MsVersion version;
    const char *error;
    CHECK(!ms_version_parse(&arena, "1.2", &version, &error));
    CHECK(strcmp(error, "\"1.2\" is not a version; write three numbers such as 1.2.3 (a suffix such as -rc.1 is allowed)") == 0);
    CHECK(ms_version_of_tag(&arena, "v1.4.2", &version) && version.major == 1 && version.minor == 4 && version.patch == 2);
    CHECK(ms_version_of_tag(&arena, "1.4.2", &version));
    CHECK(!ms_version_of_tag(&arena, "release-1", &version));
    CHECK(!ms_version_of_tag(&arena, "v1.4", &version));
}

static void test_order(void) {
    static const char *const order[] = {"1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2",
                                        "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.0.1", "1.1.0", "2.0.0"};
    for (size_t i = 0; i + 1 < sizeof order / sizeof order[0]; i++) {
        const MsVersion x = v(order[i]), y = v(order[i + 1]);
        if (!(ms_version_compare(&x, &y) < 0 && ms_version_compare(&y, &x) > 0)) {
            fprintf(stderr, "%s should be below %s\n", order[i], order[i + 1]);
            failures++;
        }
    }
    const MsVersion same = v("1.2.3");
    CHECK(ms_version_compare(&same, &same) == 0);
}

static void test_matches(void) {
    static const char *const carets[] = {"^1.2", "1.2", "^1.2.0"};
    for (size_t i = 0; i < 3; i++) {
        CHECK(matches(carets[i], "1.2.0"));
        CHECK(matches(carets[i], "1.9.4"));
        CHECK(!matches(carets[i], "1.1.9"));
        CHECK(!matches(carets[i], "2.0.0"));
    }
    CHECK(matches("1", "1.0.0") && !matches("1", "2.0.0"));
    CHECK(matches("^0.4.1", "0.4.1") && matches("^0.4.1", "0.4.9") && !matches("^0.4.1", "0.5.0") && !matches("^0.4.1", "0.4.0"));
    CHECK(matches("^0.0.3", "0.0.3") && !matches("^0.0.3", "0.0.4"));
    CHECK(matches("~1.2.3", "1.2.9") && !matches("~1.2.3", "1.3.0") && !matches("~1.2.3", "1.2.2"));
    CHECK(matches("~1", "1.9.0"));
    CHECK(matches("=1.2.3", "1.2.3") && !matches("=1.2.3", "1.2.4"));
    CHECK(matches("=1.2", "1.2.7") && !matches("=1.2", "1.3.0"));
    CHECK(!matches("^1.0", "1.1.0-rc.1"));
    CHECK(matches("^1.0.0-rc.1", "1.0.0-rc.2") && matches("^1.0.0-rc.1", "1.0.0") && !matches("^1.0.0-rc.2", "1.0.0-rc.1"));
}

static void test_buckets(void) {
    CHECK(ms_bucket_equal(ms_requirement_bucket(&(MsRequirement){0}), (MsBucket){MS_BUCKET_PATCH, 0}));
    const MsRequirement caret = r("^1.2"), tilde = r("~1.2.3"), minor = r("^0.4.1"), patch = r("^0.0.3");
    CHECK(ms_bucket_equal(ms_requirement_bucket(&caret), (MsBucket){MS_BUCKET_MAJOR, 1}));
    CHECK(ms_bucket_equal(ms_requirement_bucket(&tilde), (MsBucket){MS_BUCKET_MAJOR, 1}));
    CHECK(ms_bucket_equal(ms_requirement_bucket(&minor), (MsBucket){MS_BUCKET_MINOR, 4}));
    CHECK(ms_bucket_equal(ms_requirement_bucket(&patch), (MsBucket){MS_BUCKET_PATCH, 3}));
    const MsVersion zero = v("0.4.9"), year = v("2026.11.0");
    CHECK(ms_bucket_equal(ms_version_bucket(&zero), (MsBucket){MS_BUCKET_MINOR, 4}));
    CHECK(ms_bucket_equal(ms_version_bucket(&year), (MsBucket){MS_BUCKET_MAJOR, 2026}));
    CHECK(strcmp(ms_bucket_text(&arena, (MsBucket){MS_BUCKET_MAJOR, 1}), "1.x") == 0);
    CHECK(strcmp(ms_bucket_text(&arena, (MsBucket){MS_BUCKET_MINOR, 4}), "0.4.x") == 0);
    CHECK(strcmp(ms_bucket_text(&arena, (MsBucket){MS_BUCKET_PATCH, 3}), "0.0.3") == 0);
    CHECK(ms_bucket_compare((MsBucket){MS_BUCKET_MAJOR, 9}, (MsBucket){MS_BUCKET_MINOR, 1}) < 0);
}

static void test_requirement_errors(void) {
    static const char *const bad[] = {"0", "^0", "0.0", "~0", ">=1.0", "1.2.3.4", "^", "", "1.x", "*", "1.0-rc", "^v1.2", "1,2"};
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        MsRequirement requirement;
        const char *error;
        if (ms_requirement_parse(&arena, bad[i], &requirement, &error)) {
            fprintf(stderr, "accepted requirement \"%s\"\n", bad[i]);
            failures++;
        }
    }
    MsRequirement requirement;
    const char *error;
    CHECK(!ms_requirement_parse(&arena, "0", &requirement, &error));
    CHECK(strcmp(error, "\"0\" is not a version requirement: 0 alone covers incompatible releases; write 0.4 or 0.4.1") == 0);
    const MsRequirement plain = r("1.2"), tilde = r("~1.2.3"), exact = r("=0.4.1");
    CHECK(strcmp(ms_requirement_text(&arena, &plain), "^1.2") == 0);
    CHECK(strcmp(ms_requirement_text(&arena, &tilde), "~1.2.3") == 0);
    CHECK(strcmp(ms_requirement_text(&arena, &exact), "=0.4.1") == 0);
}

int main(void) {
    test_versions();
    test_order();
    test_matches();
    test_buckets();
    test_requirement_errors();
    ms_arena_free(&arena);
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
