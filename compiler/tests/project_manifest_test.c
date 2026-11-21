/* Unit test of ms.toml reading and import resolution (compiler/src/project/{manifest,resolve}.c), with the cases of
 * crates/ms-driver/tests/project_project.rs. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "host_test.h"
#include "ms/project.h"

static int failures;

#define CHECK(cond)                                                                                \
    do {                                                                                           \
        if (!(cond)) {                                                                             \
            fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #cond);              \
            failures++;                                                                            \
        }                                                                                          \
    } while (0)

#define MANIFEST "[project]\nname = \"sample\"\nsource = \"src\"\nentry = \"src/main.ms\"\n"

static MsArena arena;
static char root[256];

static void write_file(const char *name, const char *text) {
    const char *path = MS_PATH_JOIN(&arena, root, name);
    char *copy = ms_arena_strndup(&arena, path, strlen(path));
    for (char *slash = strchr(copy + strlen(root) + 1, '/'); slash != NULL; slash = strchr(slash + 1, '/')) {
        *slash = 0;
        host_mkdir(copy);
        *slash = '/';
    }
    FILE *f = fopen(path, "w");
    CHECK(f != NULL);
    if (f != NULL) {
        fputs(text, f);
        fclose(f);
    }
}

static void new_project(void) {
    CHECK(host_make_root(root, sizeof root, "ms_project"));
    write_file("src/main.ms", "");
    write_file("src/value.ms", "");
    write_file("src/main.txt", "");
    host_mkdir(MS_PATH_JOIN(&arena, root, "src/directory.ms"));
}

static void remove_tree(void) {
    host_remove_tree(root);
    host_remove_tree(ms_arena_fmt(&arena, "%s.outside", root).ptr);
}

typedef enum Outcome { OK, FAILS, UNSUPPORTED } Outcome;

/* Reads `manifest`; for a failure, `want` must be a substring of the error text. */
static bool read_manifest(const char *manifest, MsProject *p, MsProjectError *err, const char **text) {
    write_file("ms.toml", manifest);
    const bool ok = ms_project_read(&arena, MS_PATH_JOIN(&arena, root, "ms.toml"), p, err);
    *text = ok ? "" : ms_project_error_text(&arena, err);
    return ok;
}

static void expect_error(const char *name, const char *manifest, const char *want) {
    MsProject p;
    MsProjectError err = {0};
    const char *text;
    if (read_manifest(manifest, &p, &err, &text) || strstr(text, want) == NULL) {
        fprintf(stderr, "%s: got \"%s\", want \"%s\"\n", name, text, want);
        failures++;
    }
}

static void test_read(void) {
    MsProject p;
    MsProjectError err = {0};
    const char *text;
    const char *source = "[project]\nname = \"sample # \\\"quoted\\\"\" # c\nsource = 'src'\nentry = \"src/main.ms\"\n"
                         "[aliases]\n\"@values\" = \"src\" # directory\n\"@one\" = \"src/value.ms\"\n";
    CHECK(read_manifest(source, &p, &err, &text));
    CHECK(strcmp(p.name, "sample # \"quoted\"") == 0);
    CHECK(strcmp(p.configuration, source) == 0);
    CHECK(strcmp(p.source, MS_PATH_JOIN(&arena, p.root, "src")) == 0);
    CHECK(strcmp(p.entry, MS_PATH_JOIN(&arena, p.source, "main.ms")) == 0);
    CHECK(p.alias_count == 2 && strcmp(p.aliases[0].name, "@one") == 0 && strcmp(p.aliases[1].name, "@values") == 0);
    const char *want = MS_PATH_JOIN(&arena, p.source, "value.ms");
    static const char *const imports[] = {"./value.ms", "@values/value.ms", "@one"};
    for (size_t i = 0; i < sizeof imports / sizeof imports[0]; i++) {
        const char *got;
        CHECK(ms_project_resolve_import(&arena, &p, p.entry, imports[i], &got, &err));
        CHECK(strcmp(got, want) == 0);
    }
    CHECK(read_manifest("\xef\xbb\xbf[ project ]\nname = \"sample\"\nsource = \"src\"\n[ aliases ]\n\"@a\" = \"src\"\n", &p, &err, &text));
    CHECK(p.alias_count == 1 && p.entry[0] == 0);
}

static void test_errors(void) {
    expect_error("no table", "name = \"sample\"\n", "ms.toml:1:1: invalid manifest assignment");
    expect_error("unknown table", MANIFEST "[adapters]\n", "ms.toml:5:1: unsupported manifest table [adapters]");
    expect_error("package table", "[package]\n", "rename it to [project]");
    expect_error("unknown key", MANIFEST "license = \"MIT\"\n", "ms.toml:5:1: unknown project key license");
    expect_error("unknown number key", MANIFEST "retries = 3\n", "unknown project key retries");
    expect_error("missing name", "[project]\nsource = \"src\"\n", "ms.toml:1:1: [project] requires name and source; missing: name,");
    expect_error("missing both", "[project]\n", "missing: name, source,");
    expect_error("source is file", "[project]\nname = \"s\"\nsource = \"src/main.ms\"\n", "existing directory");
    expect_error("missing source", "[project]\nname = \"s\"\nsource = \"missing\"\n", "ms.toml:3:10: lstat");
    expect_error("entry extension", "[project]\nname = \"s\"\nsource = \"src\"\nentry = \"src/main.txt\"\n", "entry requires .ms extension");
    expect_error("entry is directory", "[project]\nname = \"s\"\nsource = \"src\"\nentry = \"src/directory.ms\"\n", "regular file");
    expect_error("empty entry", "[project]\nname = \"s\"\nsource = \"src\"\nentry = \"\"\n", "project entry cannot be empty");
    expect_error("reserved alias", MANIFEST "[aliases]\n\"@std\" = \"src\"\n", "invalid or reserved alias @std");
    expect_error("invalid alias", MANIFEST "[aliases]\n\"@2bad\" = \"src\"\n", "invalid or reserved alias");
    expect_error("alias hint", MANIFEST "[aliases]\nlib = \"src\"\n", "(did you mean @lib?)");
    expect_error("alias chaining", MANIFEST "[aliases]\n\"@one\" = \"@two\"\n", "ms.toml:6:10: invalid alias target @two");
    expect_error("NUL in value", "[project]\nname = \"s\"\nsource = \"src\"\nentry = \"src/ma\\u0000in.ms\"\n", "ms.toml:4:9: manifest value for entry contains a NUL");
    expect_error("escape", "[project]\nname = \"s\"\nsource = \"..\"\n", "escapes project root");
    expect_error("alias escape", MANIFEST "[aliases]\n\"@up\" = \"/\"\n", "alias @up target cannot be resolved");

    MsProject p;
    MsProjectError err = {0};
    const char *text;
    expect_error("std alias", "[project]\nname = \"s\"\nsource = \"src\"\n[aliases]\nstd = \"src\"\n", "invalid or reserved alias std;");
    CHECK(!read_manifest("[project]\nname = \"s\"\nsource = \"src\"\n[aliases]\nstd = \"src\"\n", &p, &err, &text) && strstr(text, "did you mean") == NULL);

    char *long_line = malloc(70100);
    CHECK(long_line != NULL);
    if (long_line != NULL) {
        const size_t head = strlen(MANIFEST "# ");
        memcpy(long_line, MANIFEST "# ", head);
        memset(long_line + head, 'x', 70000);
        memcpy(long_line + head + 70000, "\n", 2);
        expect_error("line too long", long_line, "ms.toml:5:1: line too long");
        free(long_line);
    }
}

/* Syntax the reader refuses, and valid TOML that ms.toml does not use, both with a position. */
static void test_invalid(void) {
    expect_error("duplicate table", MANIFEST "[project]\n", "ms.toml:5:1: invalid ms.toml: duplicate key");
    expect_error("duplicate key", MANIFEST "name = \"other\"\n", "ms.toml:5:1: invalid ms.toml: duplicate key");
    expect_error("missing value", "[project]\nname\n", "ms.toml:2:5: invalid ms.toml: expected equals");
    expect_error("bare word", "[project]\nname = sample\n", "ms.toml:2:8: invalid ms.toml: invalid value");
    expect_error("dependency table", MANIFEST "[dependencies.pg]\nurl = \"x\"\n", "invalid ms.toml: nested tables are not supported in ms.toml");
    expect_error("dotted key", MANIFEST "a.b = \"x\"\n", "invalid ms.toml: dotted keys are not supported in ms.toml");
    expect_error("table array", MANIFEST "[[project]]\n", "invalid ms.toml: table arrays are not supported in ms.toml");
    expect_error("multi-line string", "[project]\nname = \"\"\"x\"\"\"\n", "invalid ms.toml: multi-line strings are not supported in ms.toml");
    expect_error("unterminated string", "[project]\nname = \"x\n", "ms.toml:2:8: invalid ms.toml: unterminated string");
    expect_error("bad escape", "[project]\nname = \"\\q\"\n", "invalid ms.toml: invalid string escape");
    expect_error("unclosed header", "[project\n", "ms.toml:1:9: invalid ms.toml: expected closing table bracket");
    expect_error("trailing text", "[project] x\n", "invalid ms.toml: unexpected trailing text");
    expect_error("nested inline table", MANIFEST "[dependencies]\n\"@pg\" = { a = { b = \"c\" } }\n", "invalid ms.toml: invalid value");
    expect_error("trailing comma in inline table", MANIFEST "[dependencies]\n\"@pg\" = { path = \"src\", }\n", "invalid ms.toml: trailing comma in inline table");
    expect_error("array without comma", MANIFEST "effects = [\"a\" \"b\"]\n", "invalid ms.toml: expected array comma");
    expect_error("array alias", MANIFEST "[aliases]\n\"@a\" = [\"x\"]\n", "@a must be a string; write @a = \"[\"x\"]\"");
    expect_error("name as number", "[project]\nname = 3\nsource = \"src\"\n", "ms.toml:2:8: name must be a string; write name = \"3\"");
}

/* Bytes that are not UTF-8 read as U+FFFD, so one in a comment is harmless. */
static void test_lossy(void) {
    MsProject p;
    MsProjectError err = {0};
    const char *text;
    CHECK(read_manifest("# \xff\xfe\n" MANIFEST, &p, &err, &text));
}

/* ms_project_unquote reads what ms_project_quote writes, and refuses what Go's strconv.Unquote refuses. */
static void test_unquote(void) {
    const char *text;
    CHECK(ms_project_unquote(&arena, "\"a\\tb\\\"c\\\\\"", &text) && strcmp(text, "a\tb\"c\\") == 0);
    CHECK(ms_project_unquote(&arena, "\"\\u00e9\\x41\\101\"", &text) && strcmp(text, "\xc3\xa9" "AA") == 0);
    CHECK(!ms_project_unquote(&arena, "x", &text));
    CHECK(!ms_project_unquote(&arena, "\"open", &text));
    CHECK(!ms_project_unquote(&arena, "\"a\"b\"", &text));
    CHECK(!ms_project_unquote(&arena, "\"\\q\"", &text));
    CHECK(!ms_project_unquote(&arena, "\"\\xff\"", &text)); /* the decoded text must be UTF-8 */
    CHECK(!ms_project_unquote(&arena, "\"\\ud800\"", &text));
    const char *quoted = ms_project_quote(&arena, "tab\t \"q\" \xc3\xa9 \x01");
    CHECK(ms_project_unquote(&arena, quoted, &text) && strcmp(text, "tab\t \"q\" \xc3\xa9 \x01") == 0);
}

#define URL "https://github.com/acme/pg.git"
#define SHA "0123456789abcdef0123456789abcdef01234567"

static void test_packages(void) {
    MsProject p;
    MsProjectError err = {0};
    const char *text;
    const char *source = MANIFEST "version = \"1.2.3\"\neffects = [\"std.fs.read\", # c\n  \"std.net.*\",\n]\n"
                         "[workspace]\nmembers = [\"app\", \"libs/*\"]\n"
                         "[embed]\n\"@assets\" = \"src\"\n"
                         "[dependencies]\n\"@zed\" = { url = \"" URL "\", tag = \"v1.0.0\" }\n\"@pg\" = { url = \"" URL "\", version = \"^1.2\" }\n"
                         "\"@sha\" = { url = \"file:///tmp/r\", sha = \"" SHA "\" }\n\"@local\" = { path = \"src\" }\n"
                         "[effects]\n\"@pg\" = [\"std.net.*\"]\n";
    CHECK(read_manifest(source, &p, &err, &text));
    CHECK(p.has_version && p.version.major == 1 && p.version.minor == 2 && p.version.patch == 3);
    CHECK(p.effect_count == 2 && strcmp(p.effects[1], "std.net.*") == 0);
    CHECK(p.is_workspace && p.member_count == 2 && strcmp(p.members[1], "libs/*") == 0);
    CHECK(p.embed_count == 1 && strcmp(p.embed[0].target, p.source) == 0);
    CHECK(p.dependency_count == 3 && strcmp(p.dependencies[0].alias, "@pg") == 0 && p.dependencies[0].kind == MS_DEP_VERSION);
    CHECK(strcmp(p.dependencies[1].alias, "@sha") == 0 && p.dependencies[1].kind == MS_DEP_SHA && strcmp(p.dependencies[1].reference, SHA) == 0);
    CHECK(strcmp(p.dependencies[2].alias, "@zed") == 0 && p.dependencies[2].kind == MS_DEP_TAG && strcmp(p.dependencies[2].reference, "v1.0.0") == 0);
    CHECK(strcmp(ms_project_dependency_row(&arena, &p.dependencies[0]), "@pg\t" URL "\tversion\t^1.2") == 0);
    CHECK(strcmp(ms_project_dependency_row(&arena, &p.dependencies[2]), "@zed\t" URL "\ttag\tv1.0.0") == 0);
    CHECK(p.path_dependency_count == 1 && strcmp(p.path_dependencies[0].target, p.source) == 0);
    CHECK(p.allowed_effect_count == 1 && strcmp(p.allowed_effects[0].name, "@pg") == 0 && p.allowed_effects[0].count == 1);

    CHECK(read_manifest("[workspace]\nmembers = [\"app\"]\n", &p, &err, &text) && p.is_workspace && p.name[0] == 0);
    expect_error("workspace root with project tables", "[workspace]\nmembers = [\"app\"]\n[aliases]\n\"@a\" = \"src\"\n",
                 "ms.toml:4:1: a workspace root without [project] holds only [workspace]; move [aliases] into a member");
    expect_error("workspace key", "[workspace]\nmember = []\n", "ms.toml:2:1: unknown workspace key member; [workspace] accepts members");
    expect_error("members shape", "[workspace]\nmembers = \"app\"\n", "members: members are a list of strings: [\"app\", \"libs/*\"]");
    expect_error("member listed twice", "[workspace]\nmembers = [\"a\", \"a\"]\n", "members: member a is listed twice; remove one");
    expect_error("effect with space", MANIFEST "effects = [\"std net\"]\n", "effects: invalid effect \"std net\"; write one pattern per string, such as \"std.net.*\"");
    expect_error("bad version", MANIFEST "version = \"1.0\"\n", "ms.toml:5:11: version:");
    expect_error("package name", MANIFEST "[dependencies]\npg = { path = \"src\" }\n", "ms.toml:6:1: invalid or reserved package name pg;");
    expect_error("dependency not a table", MANIFEST "[dependencies]\n\"@pg\" = \"x\"\n", "dependency @pg: a dependency is a table; write { url =");
    expect_error("unknown dependency field", MANIFEST "[dependencies]\n\"@pg\" = { url = \"" URL "\", branch = \"main\" }\n",
                 "dependency @pg: unknown field branch; a dependency has url and one of version, tag or sha, or only path");
    expect_error("number field", MANIFEST "[dependencies]\n\"@pg\" = { url = 3 }\n", "dependency @pg: url must be a string;");
    expect_error("missing url", MANIFEST "[dependencies]\n\"@pg\" = { tag = \"v1\" }\n", "dependency @pg: url is missing;");
    expect_error("two sources", MANIFEST "[dependencies]\n\"@pg\" = { url = \"" URL "\", tag = \"v1\", sha = \"" SHA "\" }\n", "dependency @pg: name exactly one of version, tag and sha;");
    expect_error("short sha", MANIFEST "[dependencies]\n\"@pg\" = { url = \"" URL "\", sha = \"abc\" }\n", "dependency @pg: sha must be the full 40-digit lowercase commit");
    expect_error("ssh url", MANIFEST "[dependencies]\n\"@pg\" = { url = \"git@github.com:a/b.git\", tag = \"v1\" }\n", "dependency @pg: dependency URL \"git@github.com:a/b.git\" must start with https://");
    expect_error("path with url", MANIFEST "[dependencies]\n\"@pg\" = { path = \"src\", url = \"" URL "\" }\n", "dependency @pg: a path dependency has only path = \"../member\"");
    expect_error("path missing", MANIFEST "[dependencies]\n\"@pg\" = { path = \"nope\" }\n", "dependency @pg: path \"nope\" cannot be resolved:");
    expect_error("dependency and alias", MANIFEST "[aliases]\n\"@pg\" = \"src\"\n[dependencies]\n\"@pg\" = { path = \"src\" }\n",
                 "ms.toml:8:1: @pg is declared in [dependencies] and also as an alias or embed;");
    expect_error("effects without dependency", MANIFEST "[effects]\n\"@pg\" = [\"std.net.*\"]\n", "ms.toml:6:1: [effects] names @pg, which is not under [dependencies];");
    expect_error("embed and alias", MANIFEST "[aliases]\n\"@a\" = \"src\"\n[embed]\n\"@a\" = \"src\"\n", "ms.toml:8:1: @a is declared in both [aliases] and [embed];");
    expect_error("embed not a directory", MANIFEST "[embed]\n\"@a\" = \"src/main.ms\"\n", "embed @a must name an existing directory;");
    expect_error("embed to alias", MANIFEST "[embed]\n\"@a\" = \"@b\"\n", "ms.toml:6:8: invalid embed target @b;");
    expect_error("control before alias check", MANIFEST "[aliases]\nbad = \"s\\u0001\"\n", "manifest value for bad contains a NUL or control character");
}

static void test_imports(void) {
    MsProject p;
    MsProjectError err = {0};
    const char *text;
    CHECK(read_manifest(MANIFEST "[aliases]\n\"@dir\" = \"src\"\n\"@file\" = \"src/value.ms\"\n", &p, &err, &text));
    static const char *const bad[] = {"value.ms", "/value.ms", ".\\dir\\value.ms", "./value", "@missing/value.ms", "@dir_extra/value.ms",
                                      "@dir", "@dir/value", "@file/suffix.ms", "@std/value.ms", "./", "../.."};
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        const char *got;
        if (ms_project_resolve_import(&arena, &p, p.entry, bad[i], &got, &err)) {
            fprintf(stderr, "accepted invalid import %s\n", bad[i]);
            failures++;
        }
    }
    const char *got;
    CHECK(!ms_project_resolve_import(&arena, &p, p.entry, "/abs/money.ms", &got, &err));
    CHECK(strstr(ms_project_error_text(&arena, &err), "absolute import paths are not supported") != NULL);
    CHECK(!ms_project_resolve_import(&arena, &p, p.entry, "@missing/x.ms", &got, &err));
    CHECK(strstr(ms_project_error_text(&arena, &err), "unknown import alias @missing; declared aliases: @dir, @file") != NULL);
    CHECK(!ms_project_resolve_import(&arena, &p, p.entry, "./value", &got, &err));
    CHECK(strcmp(ms_project_error_text(&arena, &err), "import path requires .ms extension; write \"./value.ms\"") == 0);
    CHECK(!ms_project_resolve_import(&arena, &p, p.entry, "../../escape.ms", &got, &err));
    CHECK(strstr(ms_project_error_text(&arena, &err), "lstat") != NULL || strstr(ms_project_error_text(&arena, &err), "escapes project root") != NULL);
    CHECK(!ms_project_resolve_import(&arena, &p, p.entry, "./", &got, &err));
    CHECK(strstr(ms_project_error_text(&arena, &err), "names a directory, not a module") != NULL);

    const char *outside = ms_arena_fmt(&arena, "%s.outside", root).ptr; /* a file beside the project root */
    FILE *outside_file = fopen(outside, "w");
    CHECK(outside_file != NULL);
    if (outside_file != NULL) {
        fclose(outside_file);
    }
    CHECK(host_symlink(outside, MS_PATH_JOIN(&arena, p.source, "out.ms")));
    CHECK(!ms_project_resolve_import(&arena, &p, p.entry, "./out.ms", &got, &err));
    CHECK(strstr(ms_project_error_text(&arena, &err), "path escapes project root") != NULL);
    CHECK(host_symlink(MS_PATH_JOIN(&arena, p.source, "value.ms"), MS_PATH_JOIN(&arena, p.source, "link.ms")));
    CHECK(ms_project_resolve_import(&arena, &p, p.entry, "./link.ms", &got, &err));
    CHECK(strcmp(got, MS_PATH_JOIN(&arena, p.source, "value.ms")) == 0);

    const char *found = ms_project_find_manifest(&arena, MS_PATH_JOIN(&arena, root, "src/main.ms"));
    CHECK(found != NULL && strcmp(found, MS_PATH_JOIN(&arena, root, "ms.toml")) == 0);
    write_file("nested/src/main.ms", "");
    write_file("nested/ms.toml", "invalid configuration");
    found = ms_project_find_manifest(&arena, MS_PATH_JOIN(&arena, root, "nested/src/main.ms"));
    CHECK(found != NULL && strcmp(found, MS_PATH_JOIN(&arena, root, "nested/ms.toml")) == 0);
}

static void test_quote(void) {
    CHECK(strcmp(ms_project_quote(&arena, "a\"b\\c\n"), "\"a\\\"b\\\\c\\n\"") == 0);
    CHECK(strcmp(ms_project_quote(&arena, "/tmp/x y"), "\"/tmp/x y\"") == 0);
    CHECK(strcmp(ms_project_quote(&arena, "\x01\x7f"), "\"\\x01\\x7f\"") == 0);
}

int main(void) {
    new_project();
    test_read();
    test_errors();
    test_invalid();
    test_unquote();
    test_lossy();
    test_packages();
    test_imports();
    test_quote();
    remove_tree();
    ms_arena_free(&arena);
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
