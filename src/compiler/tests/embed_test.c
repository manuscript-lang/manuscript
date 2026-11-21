/* Unit test of `[embed]` (src/compiler/src/project/embed.c): the generated module is what the Rust driver writes
 * (crates/ms-driver/src/project/embed.rs), and a project that embeds a directory loads. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "host_test.h"
#include "ms/project.h"

static int failures;
static MsArena arena;
static char root[256];

#define CHECK(cond)                                                                                \
    do {                                                                                           \
        if (!(cond)) {                                                                             \
            fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #cond);              \
            failures++;                                                                            \
        }                                                                                          \
    } while (0)

static const char *path(const char *name) {
    return MS_PATH_JOIN(&arena, root, name);
}

static void make_dir(const char *name) {
    CHECK(ms_sys_fs_mkdir(path(name), 0700) == 0);
}

/* Writes a file; false when the host refuses the name. */
static bool try_write_bytes(const char *name, const void *bytes, size_t length) {
    FILE *f = fopen(path(name), "wb");
    if (f == NULL) {
        return false;
    }
    fwrite(bytes, 1, length, f);
    fclose(f);
    return true;
}

static void write_bytes(const char *name, const void *bytes, size_t length) { CHECK(try_write_bytes(name, bytes, length)); }

/* Windows cannot create a name with a quote or a control character, and a second name that differs only by case is
 * the first file: the same cases run everywhere, and these hold what each host does. */
#ifdef _WIN32
#define NAMES_CREATABLE false
#else
#define NAMES_CREATABLE true
#endif

static const char *generate(const char *directory) {
    const char *source = NULL;
    MsProjectError err = {0};
    if (!ms_embed_generate(&arena, "@assets", path(directory), &source, &err)) {
        return ms_arena_fmt(&arena, "error: %s", ms_project_error_text(&arena, &err)).ptr;
    }
    return source;
}

int main(void) {
    if (!host_make_root(root, sizeof root, "ms-embed-test")) {
        return 1;
    }
    make_dir("assets");
    make_dir("assets/sub");
    make_dir("assets/sub/deep");
    make_dir("assets/empty");
    write_bytes("assets/b.txt", "b", 1);
    write_bytes("assets/B2.txt", "B2", 2);
    write_bytes("assets/sub/f.bin", "\0\xff\x80" "A", 4);
    const bool quoted = try_write_bytes("assets/sub/deep/q\"x.txt", "hello world", 11);
    CHECK(quoted == NAMES_CREATABLE);
    write_bytes("assets/\xc3\xa9.txt", "ab", 2);

    /* Without the quoted name the later files move up one index. */
    const int binary = quoted ? 3 : 2;
    const int accent = quoted ? 4 : 3;
    const char *want = ms_arena_fmt(&arena,
        "import (\n\tBytes from \"@std/bytes.ms\",\n\tEmbeddedTree, embedded_tree, msstd_embed_bytes from \"@std/os/tree.ms\",\n)\n"
        "// Generated from an [embed] table of ms.toml; edit the files in the directory, not this\n"
        "// module. The compiler places the bytes of each file in the program's read-only data;\n"
        "// making the tree costs one map entry per file, and a read copies only the file asked\n"
        "// for.\n"
        "fn load(index: Int) Bytes:\n"
        "    if index == 0: return msstd_embed_bytes(\"QjI=\")\n"
        "    if index == 1: return msstd_embed_bytes(\"Yg==\")\n"
        "%s"
        "    if index == %d: return msstd_embed_bytes(\"AP+AQQ==\")\n"
        "    if index == %d: return msstd_embed_bytes(\"YWI=\")\n"
        "    return msstd_embed_bytes(\"\")\n\n"
        "export fn files() EmbeddedTree:\n"
        "    var indexes = Map[String, Int]()\n"
        "    var directories = Set[String]()\n"
        "    directories.add(\"\")\n"
        "    indexes.add(\"B2.txt\", 0)\n"
        "    indexes.add(\"b.txt\", 1)\n"
        "    directories.add(\"empty\")\n"
        "    directories.add(\"sub\")\n"
        "    directories.add(\"sub/deep\")\n"
        "%s"
        "    indexes.add(\"sub/f.bin\", %d)\n"
        "    indexes.add(\"\xc3\xa9.txt\", %d)\n"
        "    return embedded_tree(indexes, directories, load)\n",
        quoted ? "    if index == 2: return msstd_embed_bytes(\"aGVsbG8gd29ybGQ=\")\n" : "", binary, accent,
        quoted ? "    indexes.add(\"sub/deep/q\\\"x.txt\", 2)\n" : "", binary, accent).ptr;
    CHECK(strcmp(generate("assets"), want) == 0);
    CHECK(strcmp(ms_embed_module_path(&arena, "/p", "@assets"), "/p/.ms-embed/assets.ms") == 0);

    /* A link is refused, and so are names that differ only by letter case. */
    make_dir("linked");
    CHECK(host_symlink("x", path("linked/l")));
    CHECK(strcmp(generate("linked"), "error: embedded l is a symbolic link; copy the file into the directory instead, since links are not followed") == 0);
    make_dir("cased");
    write_bytes("cased/a.txt", "a", 1);
    const bool upper = try_write_bytes("cased/A.txt", "A", 1); /* Windows: this is a.txt again */
    if (NAMES_CREATABLE) {
        CHECK(strstr(generate("cased"), "embedded a.txt and A.txt differ only by letter case") != NULL);
    } else {
        CHECK(upper && strstr(generate("cased"), "indexes.add(\"a.txt\", 0)") != NULL && strstr(generate("cased"), "A.txt") == NULL);
    }
    make_dir("control");
    const bool control = try_write_bytes("control/t\tab", "x", 1);
    CHECK(control == NAMES_CREATABLE);
    if (NAMES_CREATABLE) {
        CHECK(strstr(generate("control"), "has a control character; rename it") != NULL);
    } else {
        CHECK(strstr(generate("control"), "indexes.add(") == NULL); /* nothing was embedded: the name never existed */
    }

    /* A project that embeds a directory loads the generated module under .ms-embed, whose import is the alias alone. */
    const char *manifest = "[project]\nname = \"app\"\nsource = \"src\"\nentry = \"src/main.ms\"\n[embed]\n\"@assets\" = \"assets\"\n";
    write_bytes("ms.toml", manifest, strlen(manifest));
    make_dir("src");
    const char *main_ms = "import files from \"@assets\"\nfn main() Void:\n    void files()\n";
    write_bytes("src/main.ms", main_ms, strlen(main_ms));
    MsNames names;
    ms_names_init(&names);
    MsGraph graph;
    MsProjectError err = {0};
    CHECK(ms_project_load(&arena, &names, path("ms.toml"), &graph, &err));
    CHECK(graph.ndiagnostics == 0);
    CHECK(graph.count == 2);
    CHECK(graph.count == 2 && strcmp(graph.modules[0].name, ".ms-embed/assets.ms") == 0);
    CHECK(graph.count == 2 && strstr(graph.modules[0].source, "export fn files() EmbeddedTree:") != NULL);
    ms_names_free(&names);

    host_remove_tree(root);
    ms_arena_free(&arena);
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
