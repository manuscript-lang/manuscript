/* `[embed]`: a directory baked into the program as a generated Manuscript module. The module exports `files()`, which
 * builds an `EmbeddedTree` (`@std/os/tree.ms`) holding every file of the directory as Base64 text in a string literal
 * that the compiler decodes into read-only data (`msstd_embed_bytes`). Port of crates/ms-driver/src/project/embed.rs. */
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L /* lstat; libms.c defines it first for the whole unit */
#endif
#include <errno.h>
#include <string.h>
#include <sys/stat.h>

#include "ms/project.h"

#define EMBED_MAX_FILE ((uint64_t)16 << 20)
#define EMBED_MAX_TOTAL ((uint64_t)64 << 20)

/* Directory in the project root that holds the logical paths of generated modules. */
#define EMBED_MODULE_DIR ".ms-embed"

static const char embed_template[] =
    "import (\n"
    "\tBytes from \"@std/bytes.ms\",\n"
    "\tEmbeddedTree, embedded_tree, msstd_embed_bytes from \"@std/os/tree.ms\",\n"
    ")\n"
    "// Generated from an [embed] table of ms.toml; edit the files in the directory, not this\n"
    "// module. The compiler places the bytes of each file in the program's read-only data;\n"
    "// making the tree costs one map entry per file, and a read copies only the file asked\n"
    "// for.\n";

/* One entry found by the walk, with its path below the embedded root. */
typedef struct EmbedFound {
    const char *path; /* relative, with `/` */
    const char *source;
    bool directory;
} EmbedFound;

typedef struct EmbedWalk {
    MsArena *arena;
    MsProjectError *err;
    MsBuf found; /* EmbedFound */
} EmbedWalk;

static bool embed_walk(EmbedWalk *w, const char *directory, const char *relative) {
    const char *const *names;
    uint32_t count;
    if (!ms_path_list_dir(w->arena, directory, "read directory", &names, &count, w->err)) {
        return false;
    }
    for (uint32_t i = 0; i < count; i++) {
        if (!ms_utf8_valid(names[i], strlen(names[i]))) {
            ms_project_error_message(w->err, ms_arena_fmt(w->arena, "embedded name in %s is not valid UTF-8; rename it", directory).ptr);
            return false;
        }
        const char *path = relative[0] == 0 ? names[i] : ms_arena_fmt(w->arena, "%s/%s", relative, names[i]).ptr;
        const char *source = MS_PATH_JOIN(w->arena, directory, names[i]);
        struct stat info;
        if (lstat(source, &info) != 0) {
            ms_project_error_path(w->err, w->arena, "stat", source, errno);
            return false;
        }
        if (S_ISLNK(info.st_mode)) {
            ms_project_error_message(w->err, ms_arena_fmt(w->arena, "embedded %s is a symbolic link; copy the file into the directory instead, since links are not followed", path).ptr);
            return false;
        }
        if (!S_ISDIR(info.st_mode) && !S_ISREG(info.st_mode)) {
            ms_project_error_message(w->err, ms_arena_fmt(w->arena, "embedded %s is neither a file nor a directory; remove it", path).ptr);
            return false;
        }
        const EmbedFound found = {.path = path, .source = source, .directory = S_ISDIR(info.st_mode)};
        MS_VEC_PUSH(w->found, EmbedFound, found);
        if (found.directory && !embed_walk(w, source, path)) {
            return false;
        }
    }
    return true;
}

static char embed_lower(char c) {
    return c >= 'A' && c <= 'Z' ? (char)(c - 'A' + 'a') : c;
}

static bool embed_same_ignoring_case(const char *a, const char *b) {
    for (; *a != 0 && *b != 0; a++, b++) {
        if (embed_lower(*a) != embed_lower(*b)) {
            return false;
        }
    }
    return *a == *b;
}

/* The entries of `root` in byte order, directories before their contents; names that differ only by case are an error. */
static bool embed_found(EmbedWalk *w, const char *root) {
    if (!embed_walk(w, root, "")) {
        return false;
    }
    const size_t count = MS_VEC_LEN(w->found, EmbedFound);
    const EmbedFound *items = ms_buf_items(&w->found);
    for (size_t i = 0; i < count; i++) {
        for (size_t earlier = 0; earlier < i; earlier++) {
            if (embed_same_ignoring_case(items[i].path, items[earlier].path)) {
                ms_project_error_message(w->err, ms_arena_fmt(w->arena, "embedded %s and %s differ only by letter case; rename one so the program behaves the same on every filesystem", items[i].path, items[earlier].path).ptr);
                return false;
            }
        }
    }
    return true;
}

static void embed_base64(MsBuf *out, const uint8_t *data, size_t length) {
    static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    for (size_t at = 0; at < length; at += 3) {
        const size_t chunk = length - at < 3 ? length - at : 3;
        const uint32_t n = ((uint32_t)data[at] << 16) | (chunk > 1 ? (uint32_t)data[at + 1] << 8 : 0) | (chunk > 2 ? data[at + 2] : 0);
        for (size_t i = 0; i < 4; i++) {
            ms_buf_putc(out, i <= chunk ? alphabet[(n >> (18 - 6 * i)) & 63] : '=');
        }
    }
}

/* `text` as a string literal; a control character is refused. */
static const char *embed_literal(MsArena *a, const char *text, MsProjectError *err) {
    MsBuf out = {0};
    ms_buf_putc(&out, '"');
    for (const char *p = text; *p != 0; p++) {
        if ((unsigned char)*p < 0x20 || *p == 0x7f) {
            ms_buf_free(&out);
            ms_project_error_message(err, ms_arena_fmt(a, "embedded name %s has a control character; rename it", ms_project_quote(a, text)).ptr);
            return NULL;
        }
        if (*p == '\\' || *p == '"') {
            ms_buf_putc(&out, '\\');
        }
        ms_buf_putc(&out, *p);
    }
    ms_buf_putc(&out, '"');
    const char *literal = ms_arena_strndup(a, out.data, out.len);
    ms_buf_free(&out);
    return literal;
}

const char *ms_embed_module_path(MsArena *a, const char *root, const char *name) {
    return MS_PATH_JOIN(a, root, EMBED_MODULE_DIR, ms_arena_fmt(a, "%s.ms", name[0] == '@' ? name + 1 : name).ptr);
}

bool ms_embed_generate(MsArena *a, const char *name, const char *root, const char **source, MsProjectError *err) {
    EmbedWalk walk = {.arena = a, .err = err};
    bool ok = embed_found(&walk, root);
    MsBuf loads = {0};
    MsBuf entries = {0};
    uint64_t total = 0;
    uint32_t files = 0;
    const size_t count = MS_VEC_LEN(walk.found, EmbedFound);
    for (size_t i = 0; ok && i < count; i++) {
        const EmbedFound *entry = &((const EmbedFound *)ms_buf_items(&walk.found))[i];
        const char *path = embed_literal(a, entry->path, err);
        if (path == NULL) {
            ok = false;
        } else if (entry->directory) {
            ms_buf_printf(&entries, "    directories.add(%s)\n", path);
        } else {
            size_t length = 0;
            const char *data = ms_project_read_file(a, entry->source, &length, err);
            if (data == NULL) {
                ok = false;
            } else if (length > EMBED_MAX_FILE) {
                ms_project_error_message(err, ms_arena_fmt(a, "embedded %s is larger than %u MiB; keep large data outside the program", entry->path, (unsigned)(EMBED_MAX_FILE >> 20)).ptr);
                ok = false;
            } else if ((total += length) > EMBED_MAX_TOTAL) {
                ms_project_error_message(err, ms_arena_fmt(a, "embedded %s holds more than %u MiB; keep large data outside the program", name, (unsigned)(EMBED_MAX_TOTAL >> 20)).ptr);
                ok = false;
            } else {
                ms_buf_printf(&loads, "    if index == %u: return msstd_embed_bytes(\"", files);
                embed_base64(&loads, (const uint8_t *)data, length);
                ms_buf_puts(&loads, "\")\n");
                ms_buf_printf(&entries, "    indexes.add(%s, %u)\n", path, files);
                files++;
            }
        }
    }
    if (ok) {
        MsBuf text = {0};
        ms_buf_puts(&text, embed_template);
        ms_buf_puts(&text, "fn load(index: Int) Bytes:\n");
        ms_buf_put(&text, loads.data, loads.len);
        ms_buf_puts(&text, "    return msstd_embed_bytes(\"\")\n\n");
        ms_buf_puts(&text, "export fn files() EmbeddedTree:\n");
        ms_buf_puts(&text, "    var indexes = Map[String, Int]()\n");
        ms_buf_puts(&text, "    var directories = Set[String]()\n");
        ms_buf_puts(&text, "    directories.add(\"\")\n");
        ms_buf_put(&text, entries.data, entries.len);
        ms_buf_puts(&text, "    return embedded_tree(indexes, directories, load)\n");
        *source = ms_arena_strndup(a, text.data, text.len);
        ms_buf_free(&text);
    }
    ms_buf_free(&walk.found);
    ms_buf_free(&loads);
    ms_buf_free(&entries);
    return ok;
}
