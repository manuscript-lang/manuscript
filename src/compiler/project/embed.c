/* compiler/project/embed.c: an [embed] directory as a generated Manuscript module, port of
 * crates/ms-driver/src/project/embed.rs. The module exports `files()`, which builds an `EmbeddedTree` holding
 * every file of the directory as Base64 text in a string literal. */
#include <errno.h>

#include "base/dir.h"
#include "base/file.h"
#include "base/path.h"
#include "base/sort.h"
#include "base/utf8.h"
#include "compiler/project/manifest.h"

enum { MAX_FILE_MIB = 16, MAX_TOTAL_MIB = 64, MIB = 1024 * 1024 };

static const char PRELUDE[] =
    "import (\n"
    "\tBytes from \"@std/bytes.ms\",\n"
    "\tEmbeddedTree, embedded_tree, msstd_embed_bytes from \"@std/os/tree.ms\",\n"
    ")\n"
    "// Generated from an [embed] table of ms.toml; edit the files in the directory, not this\n"
    "// module. The compiler places the bytes of each file in the program's read-only data;\n"
    "// making the tree costs one map entry per file, and a read copies only the file asked\n"
    "// for.\n";

typedef struct Found {
  MsSpan path;   /* below the embedded root */
  MsSpan source; /* on disk */
  bool directory;
} Found;

MS_LIST_DEFINE(FoundList, found_list, Found)

typedef struct Walk {
  MsArena *arena;
  FoundList found;
  MsProjectError *error;
} Walk;

static bool walk_failure(Walk *w, MsStrBuild *text) {
  ms_project_error_message(w->error, ms_project_text(w->arena, text));
  return false;
}

static int64_t entry_order(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const MsDirEntry *x = (const void *)a;
  const MsDirEntry *y = (const void *)b;
  const MsSpan left = ms_string_span(&x->name);
  const MsSpan right = ms_string_span(&y->name);
  const size_t common = left.len < right.len ? left.len : right.len;
  for (size_t i = 0; i < common; i++) {
    if (left.ptr[i] != right.ptr[i]) {
      return left.ptr[i] < right.ptr[i] ? -1 : 1;
    }
  }
  return left.len == right.len ? 0 : (left.len < right.len ? -1 : 1);
}

static MsSpan joined(Walk *w, MsSpan left, MsSpan right) {
  MsStrBuild text = ms_strbuild_new();
  ms_path_append_joined(&text, left, right);
  return ms_project_text(w->arena, &text);
}

static bool walk_directory(Walk *w, MsSpan root, MsSpan relative);

/* One entry: a link and anything that is neither file nor directory are refused. */
static bool walk_entry(Walk *w, MsSpan root, MsSpan relative, const MsDirEntry *entry) {
  const MsSpan name = ms_string_span(&entry->name);
  const MsSpan path = relative.len == 0 ? ms_arena_copy(w->arena, name) : joined(w, relative, name);
  const MsSpan source = joined(w, root, path);
  MsStrBuild text = ms_strbuild_new();
  if (entry->kind == MS_PATH_SYMLINK) {
    ms_strbuild_append_text(&text, "embedded ");
    ms_strbuild_append(&text, path);
    ms_strbuild_append_text(&text, " is a symbolic link; copy the file into the directory instead, since links are not followed");
    return walk_failure(w, &text);
  }
  if (entry->kind != MS_PATH_FILE && entry->kind != MS_PATH_DIRECTORY) {
    ms_strbuild_append_text(&text, "embedded ");
    ms_strbuild_append(&text, path);
    ms_strbuild_append_text(&text, " is neither a file nor a directory; remove it");
    return walk_failure(w, &text);
  }
  ms_strbuild_free(&text);
  const bool directory = entry->kind == MS_PATH_DIRECTORY;
  found_list_push(&w->found, (Found){.path = path, .source = source, .directory = directory});
  return !directory || walk_directory(w, root, path);
}

static bool walk_directory(Walk *w, MsSpan root, MsSpan relative) {
  const MsSpan directory = relative.len == 0 ? root : joined(w, root, relative);
  MsDirEntryList entries = {0};
  if (!ms_dir_list(directory, &entries)) {
    ms_project_error_path(w->error, "read directory", directory, errno);
    ms_dir_entries_free(&entries);
    return false;
  }
  ms_sort((uint8_t *)entries.ptr, entries.len, sizeof(MsDirEntry), entry_order, NULL);
  bool ok = true;
  for (size_t i = 0; ok && i < entries.len; i++) {
    const MsSpan name = ms_string_span(&entries.ptr[i].name);
    if (!ms_utf8_is_valid(name.ptr, name.len)) {
      MsStrBuild text = ms_strbuild_new();
      ms_strbuild_append_text(&text, "embedded name in ");
      ms_strbuild_append(&text, directory);
      ms_strbuild_append_text(&text, " is not valid UTF-8; rename it");
      ok = walk_failure(w, &text);
    } else {
      ok = walk_entry(w, root, relative, &entries.ptr[i]);
    }
  }
  ms_dir_entries_free(&entries);
  return ok;
}

static bool equal_ignoring_case(MsSpan a, MsSpan b) {
  if (a.len != b.len) {
    return false;
  }
  for (size_t i = 0; i < a.len; i++) {
    const uint8_t x = a.ptr[i] >= 'A' && a.ptr[i] <= 'Z' ? (uint8_t)(a.ptr[i] + 32) : a.ptr[i];
    const uint8_t y = b.ptr[i] >= 'A' && b.ptr[i] <= 'Z' ? (uint8_t)(b.ptr[i] + 32) : b.ptr[i];
    if (x != y) {
      return false;
    }
  }
  return true;
}

/* Names that differ only by letter case would behave differently on a case-insensitive file system. */
static bool check_case(Walk *w) {
  for (size_t i = 1; i < w->found.len; i++) {
    for (size_t j = 0; j < i; j++) {
      if (equal_ignoring_case(w->found.ptr[i].path, w->found.ptr[j].path)) {
        MsStrBuild text = ms_strbuild_new();
        ms_strbuild_append_text(&text, "embedded ");
        ms_strbuild_append(&text, w->found.ptr[i].path);
        ms_strbuild_append_text(&text, " and ");
        ms_strbuild_append(&text, w->found.ptr[j].path);
        ms_strbuild_append_text(&text, " differ only by letter case; rename one so the program behaves the same on every filesystem");
        return walk_failure(w, &text);
      }
    }
  }
  return true;
}

static void append_base64(MsStrBuild *out, MsSpan data) {
  static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  for (size_t at = 0; at < data.len; at += 3) {
    const size_t left = data.len - at;
    const uint32_t n = ((uint32_t)data.ptr[at] << 16) | ((left > 1 ? (uint32_t)data.ptr[at + 1] : 0) << 8) |
                       (left > 2 ? (uint32_t)data.ptr[at + 2] : 0);
    for (size_t i = 0; i < 4; i++) {
      ms_strbuild_append_byte(out, i <= left ? (uint8_t)alphabet[(n >> (18 - 6 * i)) & 63] : '=');
    }
  }
}

/* The name as the inside of a string literal; a control character is refused. */
static bool append_escaped(MsStrBuild *out, MsSpan text, MsString *refusal) {
  for (size_t i = 0; i < text.len; i++) {
    const uint8_t c = text.ptr[i];
    if (c < 0x20 || c == 0x7f) {
      MsStrBuild message = ms_strbuild_new();
      ms_strbuild_append_text(&message, "embedded name \"");
      ms_strbuild_append(&message, text);
      ms_strbuild_append_text(&message, "\" has a control character; rename it");
      *refusal = ms_strbuild_finish(&message);
      return false;
    }
    if (c == '"' || c == '\\') {
      ms_strbuild_append_byte(out, '\\');
    }
    ms_strbuild_append_byte(out, c);
  }
  return true;
}

/* The generated module is data, not one statement per file: its size must not grow the functions the compiler
 * optimizes. Each file's bytes are a function of their own, `load` finds one by halving, and the paths are two string
 * literals the generated `files` splits at run time. */
typedef struct Emit {
  MsStrBuild loads;   /* `fn file_<n>() Bytes`, one per file */
  MsStrBuild paths;   /* the file paths, in file order, separated by `\n` escapes */
  MsStrBuild dirs;    /* the directory paths, separated by `\n` escapes */
  size_t files, directories;
  uint64_t total;
} Emit;

static bool emit_failure(Walk *w, const char *head, MsSpan name, const char *tail) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, head);
  ms_strbuild_append(&text, name);
  ms_strbuild_append_text(&text, tail);
  return walk_failure(w, &text);
}

static bool emit_file(Walk *w, Emit *emit, const Found *item, MsSpan path_literal, MsSpan name) {
  MsBytes data = {0};
  if (!ms_file_read(item->source, &data)) {
    ms_project_error_path(w->error, "read", item->source, errno);
    return false;
  }
  const bool too_big = data.len > (uint64_t)MAX_FILE_MIB * MIB;
  emit->total += data.len;
  if (too_big || emit->total > (uint64_t)MAX_TOTAL_MIB * MIB) {
    ms_bytes_free(&data);
    return too_big ? emit_failure(w, "embedded ", item->path, " is larger than 16 MiB; keep large data outside the program")
                   : emit_failure(w, "embedded ", name, " holds more than 64 MiB; keep large data outside the program");
  }
  ms_strbuild_printf(&emit->loads, "fn file_%zu() Bytes:\n    return msstd_embed_bytes(\"", emit->files);
  append_base64(&emit->loads, ms_bytes_span(&data));
  ms_strbuild_append_text(&emit->loads, "\")\n\n");
  ms_strbuild_append_text(&emit->paths, emit->files == 0 ? "" : "\\n");
  ms_strbuild_append(&emit->paths, path_literal);
  emit->files++;
  ms_bytes_free(&data);
  return true;
}

static bool emit_item(Walk *w, Emit *emit, const Found *item, MsSpan name) {
  MsStrBuild literal = ms_strbuild_new();
  MsString refusal = ms_string_empty();
  if (!append_escaped(&literal, item->path, &refusal)) {
    ms_strbuild_free(&literal);
    ms_project_error_message(w->error, ms_arena_copy(w->arena, ms_string_span(&refusal)));
    ms_string_release(&refusal);
    return false;
  }
  bool ok = true;
  if (item->directory) {
    ms_strbuild_append_text(&emit->dirs, emit->directories++ == 0 ? "" : "\\n");
    ms_strbuild_append(&emit->dirs, ms_strbuild_span(&literal));
  } else {
    ok = emit_file(w, emit, item, ms_strbuild_span(&literal), name);
  }
  ms_strbuild_free(&literal);
  return ok;
}

enum { DISPATCH_LEAF = 32 };

/* The test of file numbers [first, last) by halving, in function `body`'s text: one test and one call per file. */
static void emit_halves(MsStrBuild *out, size_t first, size_t last, size_t depth) {
  if (last - first == 1) {
    for (size_t i = 0; i < depth; i++) {
      ms_strbuild_append_text(out, "    ");
    }
    ms_strbuild_printf(out, "return file_%zu()\n", first);
    return;
  }
  const size_t middle = first + (last - first) / 2;
  for (size_t i = 0; i < depth; i++) {
    ms_strbuild_append_text(out, "    ");
  }
  ms_strbuild_printf(out, "if index < %zu:\n", middle);
  emit_halves(out, first, middle, depth + 1);
  emit_halves(out, middle, last, depth); /* the branch above returns, so the rest follows flat */
}

/* `load_<first>_<last>(index)` finds file numbers [first, last): a range above DISPATCH_LEAF splits into two such
 * functions, so no function is longer than a few hundred lines however many files there are. */
static void emit_load(MsStrBuild *out, size_t first, size_t last) {
  const size_t middle = first + (last - first) / 2;
  if (last - first > DISPATCH_LEAF) {
    emit_load(out, first, middle);
    emit_load(out, middle, last);
  }
  ms_strbuild_printf(out, "fn load_%zu_%zu(index: Int) Bytes:\n", first, last);
  if (last - first > DISPATCH_LEAF) {
    ms_strbuild_printf(out, "    if index < %zu:\n        return load_%zu_%zu(index)\n    return load_%zu_%zu(index)\n\n",
                       middle, first, middle, middle, last);
  } else {
    emit_halves(out, first, last, 1);
    ms_strbuild_append_byte(out, '\n');
  }
}

bool ms_project_embed_generate(MsArena *arena, MsSpan name, MsSpan directory, MsSpan *source,
                               MsProjectError *error) {
  Walk walk = {.arena = arena, .error = error};
  Emit emit = {.loads = ms_strbuild_new(), .paths = ms_strbuild_new(), .dirs = ms_strbuild_new()};
  bool ok = walk_directory(&walk, directory, (MsSpan){0}) && check_case(&walk);
  for (size_t i = 0; ok && i < walk.found.len; i++) {
    ok = emit_item(&walk, &emit, &walk.found.ptr[i], name);
  }
  if (ok) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, PRELUDE);
    ms_strbuild_append(&text, ms_strbuild_span(&emit.loads));
    if (emit.files > 0) {
      emit_load(&text, 0, emit.files);
      ms_strbuild_printf(&text, "fn load(index: Int) Bytes:\n    return load_0_%zu(index)\n", emit.files);
    } else {
      ms_strbuild_append_text(&text, "fn load(index: Int) Bytes:\n    return msstd_embed_bytes(\"\")\n");
    }
    ms_strbuild_append_text(&text, "\nexport fn files() EmbeddedTree:\n"
                                   "    var indexes = Map[String, Int]()\n    var directories = Set[String]()\n"
                                   "    directories.add(\"\")\n");
    if (emit.files > 0) {
      ms_strbuild_append_text(&text, "    var number = 0\n    for path in \"");
      ms_strbuild_append(&text, ms_strbuild_span(&emit.paths));
      ms_strbuild_append_text(&text, "\".split(\"\\n\"):\n        indexes.add(path, number)\n        number += 1\n");
    }
    if (emit.directories > 0) {
      ms_strbuild_append_text(&text, "    for path in \"");
      ms_strbuild_append(&text, ms_strbuild_span(&emit.dirs));
      ms_strbuild_append_text(&text, "\".split(\"\\n\"):\n        directories.add(path)\n");
    }
    ms_strbuild_append_text(&text, "    return embedded_tree(indexes, directories, load)\n");
    *source = ms_project_text(arena, &text);
  }
  ms_strbuild_free(&emit.loads);
  ms_strbuild_free(&emit.paths);
  ms_strbuild_free(&emit.dirs);
  found_list_free(&walk.found);
  return ok;
}

MsSpan ms_project_embed_module_path(MsArena *arena, MsSpan root, MsSpan name) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append(&text, root);
  ms_strbuild_append_text(&text, "/.ms-embed/");
  ms_strbuild_append(&text, ms_span_of(name.ptr + (name.len > 0 && name.ptr[0] == '@' ? 1 : 0),
                                       name.len - (name.len > 0 && name.ptr[0] == '@' ? 1 : 0)));
  ms_strbuild_append_text(&text, ".ms");
  return ms_project_text(arena, &text);
}

bool ms_project_embed_of(MsArena *arena, const struct MsManifest *manifest, MsSpan canonical, MsSpan *name,
                         MsSpan *directory) {
  for (size_t i = 0; manifest != NULL && i < manifest->embeds.len; i++) {
    const MsManifestName *embed = &manifest->embeds.ptr[i];
    if (ms_span_equal(ms_project_embed_module_path(arena, manifest->root, embed->name), canonical)) {
      *name = embed->name;
      *directory = embed->target;
      return true;
    }
  }
  return false;
}
