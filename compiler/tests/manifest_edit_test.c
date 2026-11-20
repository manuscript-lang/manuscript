/* Unit test of the ms.toml editor (compiler/src/project/edit.c): each expectation is what the Rust editor
 * (crates/ms-driver/src/project/edit.rs, toml_edit) writes for the same manifest. */
#include <stdio.h>
#include <string.h>

#include "ms/project.h"

static int failures;
static MsArena arena;

static void expect(const char *label, const char *got, const char *want) {
    if (strcmp(got, want) != 0) {
        fprintf(stderr, "%s:\n got  %s\n want %s\n", label, got, want);
        failures++;
    }
}

static const char *run(bool ok, const char *out, const MsProjectError *err) {
    return ok ? out : ms_arena_fmt(&arena, "ERR %s", ms_project_error_text(&arena, err)).ptr;
}

static const char *add(const char *text, const char *name, MsPinKind pin, const char *pinned) {
    const char *out = NULL;
    MsProjectError err = {0};
    const bool ok = ms_manifest_add_dependency(&arena, text, name, "https://h/x/ms-pg.git", pin, pinned, &out, &err);
    return run(ok, out, &err);
}

static const char *allow(const char *text, const char *name, const char *const *effects, uint32_t count) {
    const char *out = NULL;
    MsProjectError err = {0};
    const bool ok = ms_manifest_allow_effects(&arena, text, name, effects, count, &out, &err);
    return run(ok, out, &err);
}

static const char *remove_dep(const char *text, const char *name) {
    const char *out = NULL;
    MsProjectError err = {0};
    const bool ok = ms_manifest_remove_dependency(&arena, text, name, &out, &err);
    return run(ok, out, &err);
}

#define PG "\"@pg\" = { url = \"https://h/x/ms-pg.git\", tag = \"v1\" }\n"
#define PROJECT "[project]\nname = \"a\"\nsource = \"src\"\n"
#define DEP_A "\"@a\" = { url = \"https://h/a.git\", tag = \"v1\" }"

int main(void) {
    const char *base = "# my app\n[project]\nname = \"app\" # the name\nsource = \"src\"\n";
    const char *with = PROJECT "\n[dependencies]\n" DEP_A " # note\n\n[effects]\n\"@a\" = [\"std.net.*\"]\n";
    const char *net[] = {"std.net.*"};
    const char *two[] = {"std.fs.read", "std.net.*"};

    expect("no table", add(base, "@pg", MS_PIN_TAG, "v1.0.0"),
           "# my app\n[project]\nname = \"app\" # the name\nsource = \"src\"\n\n[dependencies]\n\"@pg\" = { url = \"https://h/x/ms-pg.git\", tag = \"v1.0.0\" }\n");
    expect("no final newline", add("[project]\nname = \"a\"\nsource = \"src\"", "@pg", MS_PIN_VERSION, "^1.2"),
           PROJECT "\n[dependencies]\n\"@pg\" = { url = \"https://h/x/ms-pg.git\", version = \"^1.2\" }\n");
    expect("blank line end", add(PROJECT "\n", "@pg", MS_PIN_SHA, "aaaa"),
           PROJECT "\n[dependencies]\n\"@pg\" = { url = \"https://h/x/ms-pg.git\", sha = \"aaaa\" }\n\n");
    expect("second dependency", add(with, "@pg", MS_PIN_TAG, "v1"),
           PROJECT "\n[dependencies]\n" DEP_A " # note\n" PG "\n[effects]\n\"@a\" = [\"std.net.*\"]\n");
    expect("empty table", add(PROJECT "[dependencies]\n", "@pg", MS_PIN_TAG, "v1"), PROJECT "[dependencies]\n" PG);
    expect("crlf", add("# my app\r\n[project]\r\nname = \"a\"\r\n", "@pg", MS_PIN_TAG, "v1"),
           "# my app\r\n[project]\r\nname = \"a\"\r\n\r\n[dependencies]\r\n" "\"@pg\" = { url = \"https://h/x/ms-pg.git\", tag = \"v1\" }\r\n");
    expect("trailing comment", add("[project]\nname = \"a\"\n# end\n", "@pg", MS_PIN_TAG, "v1"),
           "[project]\nname = \"a\"\n\n[dependencies]\n" PG "# end\n");
    expect("after other tables", add("[project]\nname = \"a\"\n[aliases]\n\"@x\" = \"src\"\n[embed]\n\"@e\" = \"d\"\n", "@pg", MS_PIN_TAG, "v1"),
           "[project]\nname = \"a\"\n[aliases]\n\"@x\" = \"src\"\n[embed]\n\"@e\" = \"d\"\n\n[dependencies]\n" PG);
    expect("in the middle", add("[project]\nname = \"a\"\n[dependencies]\n\"@a\" = { url = \"u\", tag = \"v\" }\n[aliases]\n\"@x\" = \"src\"\n", "@pg", MS_PIN_TAG, "v1"),
           "[project]\nname = \"a\"\n[dependencies]\n\"@a\" = { url = \"u\", tag = \"v\" }\n" PG "[aliases]\n\"@x\" = \"src\"\n");
    expect("header comment", add("[project]\nname = \"a\"\n[dependencies] # d\n", "@pg", MS_PIN_TAG, "v1"),
           "[project]\nname = \"a\"\n[dependencies] # d\n" PG);
    expect("empty file", add("", "@pg", MS_PIN_TAG, "v1"), "[dependencies]\n" PG);
    expect("bare key", add("[project]\nname=\"a\"\n", "pg", MS_PIN_TAG, "v1"),
           "[project]\nname=\"a\"\n\n[dependencies]\npg = { url = \"https://h/x/ms-pg.git\", tag = \"v1\" }\n");
    expect("already there", add(with, "@a", MS_PIN_TAG, "v1"), "ERR @a is already in [dependencies]; run `ms remove @a` first, or edit its entry");
    expect("dotted table", add(PROJECT "[dependencies.x]\n", "@pg", MS_PIN_TAG, "v1"), "ERR a table header the manifest editor does not read");

    expect("allow in a new table", allow(base, "@pg", net, 1),
           "# my app\n[project]\nname = \"app\" # the name\nsource = \"src\"\n\n[effects]\n\"@pg\" = [\"std.net.*\"]\n");
    expect("allow appends", allow(with, "@pg", two, 2),
           PROJECT "\n[dependencies]\n" DEP_A " # note\n\n[effects]\n\"@a\" = [\"std.net.*\"]\n\"@pg\" = [\"std.fs.read\", \"std.net.*\"]\n");
    const char *read[] = {"std.fs.read"};
    expect("allow replaces", allow(with, "@a", read, 1),
           PROJECT "\n[dependencies]\n" DEP_A " # note\n\n[effects]\n\"@a\" = [\"std.fs.read\"]\n");
    expect("allow in a leading table", allow("[effects]\n[project]\nname=\"a\"\n", "@pg", (const char *[]){"x"}, 1), "[effects]\n\"@pg\" = [\"x\"]\n[project]\nname=\"a\"\n");

    expect("remove dependency and effects", remove_dep(with, "@a"), PROJECT);
    expect("remove missing", remove_dep(with, "@zz"), "ERR @zz is not in [dependencies]");
    const char *pair = PROJECT "[dependencies]\n" DEP_A "\n\"@b\" = { url = \"https://h/b.git\", tag = \"v1\" }\n";
    expect("remove one of two", remove_dep(pair, "@a"), PROJECT "[dependencies]\n\"@b\" = { url = \"https://h/b.git\", tag = \"v1\" }\n");
    expect("remove last", remove_dep(PROJECT "\n[dependencies]\n" DEP_A "\n", "@a"), PROJECT);
    const char *notes = "[project]\nname = \"a\"\n[dependencies]\n# about a\n\"@a\" = { url = \"u\", tag = \"v\" }\n# about b\n\n\"@b\" = { url = \"u\", tag = \"v\" }\n[aliases]\n\"@x\" = \"s\"\n";
    expect("remove with comment", remove_dep(notes, "@a"),
           "[project]\nname = \"a\"\n[dependencies]\n# about b\n\n\"@b\" = { url = \"u\", tag = \"v\" }\n[aliases]\n\"@x\" = \"s\"\n");
    expect("remove second with comment", remove_dep(notes, "@b"),
           "[project]\nname = \"a\"\n[dependencies]\n# about a\n\"@a\" = { url = \"u\", tag = \"v\" }\n[aliases]\n\"@x\" = \"s\"\n");
    expect("remove table in the middle",
           remove_dep("[project]\nname = \"a\"\n\n# deps\n[dependencies]\n# about a\n\"@a\" = { url = \"u\", tag = \"v\" }\n\n# al\n[aliases]\n\"@x\" = \"s\"\n# end\n", "@a"),
           "[project]\nname = \"a\"\n\n# al\n[aliases]\n\"@x\" = \"s\"\n# end\n");
    expect("crlf remove", remove_dep("[project]\r\nname = \"a\"\r\n\r\n[dependencies]\r\n" DEP_A "\r\n", "@a"), "[project]\r\nname = \"a\"\r\n");

    expect("name from a repository", ms_manifest_default_name(&arena, "https://github.com/acme/ms-pg.git"), "@pg");
    expect("name without .git", ms_manifest_default_name(&arena, "https://github.com/acme/wire/"), "@wire");
    expect("name with dash", ms_manifest_default_name(&arena, "https://github.com/acme/my-lib.git"), "@my_lib");
    expect("name from scp url", ms_manifest_default_name(&arena, "git@h:acme/x.git"), "@x");
    expect("name from file url", ms_manifest_default_name(&arena, "file:///tmp/r"), "@r");
    const char *digit = ms_manifest_default_name(&arena, "https://github.com/acme/2fast.git");
    expect("name starting with a digit", digit == NULL ? "none" : digit, "none");

    ms_arena_free(&arena);
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
