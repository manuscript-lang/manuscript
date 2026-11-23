/* Owns `ms init` (init_command.h): the files of a new project, library or workspace, written into a directory that
 * holds none of them. Port of crates/ms-cli/src/init.rs. */
#include "cli/init_command.h"

#include <stdio.h>

#include "base/dir.h"
#include "base/file.h"
#include "base/message.h"
#include "base/path.h"
#include "compiler/project/project_internal.h"

enum { STATUS_FAILED = 1, STATUS_USAGE = 2 };

static const char kMain[] =
    "import arguments from \"@std/os/env.ms\"\n\nfn main() Void:\n\tprint(f\"Arguments: {arguments().length()}\")\n";
static const char kTest[] =
    "import expect_equal from \"@std/test/test.ms\"\n\ntest \"arithmetic\":\n\texpect_equal(2 + 3, 5)?\n";
static const char kLib[] = "export fn greeting(name: String) String: f\"Hello, {name}\"\n";
static const char kLibTest[] = "import (\n\texpect_equal from \"@std/test/test.ms\",\n\n\tgreeting from \"./src/lib.ms\",\n)\n\n"
                               "test \"greeting\":\n\texpect_equal(greeting(\"ms\"), \"Hello, ms\")?\n";
static const char kWorkspaceMain[] =
    "import greeting from \"@greeter/lib.ms\"\n\nfn main() Void:\n\tprint(greeting(\"ms\"))\n";
static const char kIgnore[] = ".ms-cache/\n";
static const char kAttributes[] = "*.ms text eol=lf\n*.toml text eol=lf\nms.lock text eol=lf\n";

typedef struct InitFile {
  const char *name;
  MsSpan content;
} InitFile;

typedef struct InitOptions {
  const char *directory;
  bool library, workspace;
} InitOptions;

static void print_span(FILE *stream, MsSpan text) {
  (void)fwrite(text.ptr, 1, text.len, stream);
}

static int usage(MsArena *arena, const char *message) {
  print_span(stderr, ms_message_format(arena, "%s\n", message));
  return STATUS_USAGE;
}

static int parse_arguments(MsArena *arena, int argc, char **argv, InitOptions *options) {
  bool given = false;
  for (int i = 0; i < argc; i++) {
    const MsSpan arg = ms_span_of_text(argv[i]);
    if (ms_span_is_text(arg, "--lib") && !options->library && !options->workspace) {
      options->library = true;
    } else if (ms_span_is_text(arg, "--workspace") && !options->workspace && !options->library) {
      options->workspace = true;
    } else if ((arg.len > 0 && arg.ptr[0] == '-') || given) {
      print_span(stderr, ms_message_format(arena,
                                           "unexpected init argument: %S; ms init takes --lib or --workspace (not "
                                           "both) and at most one directory, e.g. ms init --lib greeter\n",
                                           arg));
      return STATUS_USAGE;
    } else if (arg.len == 0) {
      return usage(arena, "ms init: the directory is empty; pass a directory name such as ms init hello, or omit it "
                          "for the current directory");
    } else {
      options->directory = argv[i];
      given = true;
    }
  }
  return 0;
}

static MsSpan joined(MsArena *arena, MsSpan left, MsSpan right) {
  MsStrBuild path = ms_strbuild_new();
  ms_path_append_joined(&path, left, right);
  MsStrBuild cleaned = ms_strbuild_new();
  ms_path_clean(&cleaned, ms_strbuild_span(&path));
  ms_strbuild_free(&path);
  return ms_project_text(arena, &cleaned);
}

/* A manifest name from the directory: lowercase letters, digits, `-` and `_`, falling back to `app`. */
static MsSpan project_name(MsArena *arena, MsSpan absolute) {
  const MsSpan base = ms_path_file_name(absolute);
  MsStrBuild name = ms_strbuild_new();
  for (size_t i = 0; i < base.len; i++) {
    const uint8_t c = base.ptr[i];
    if (c >= 'A' && c <= 'Z') {
      ms_strbuild_append_byte(&name, (uint8_t)(c + 32));
    } else if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_') {
      ms_strbuild_append_byte(&name, c);
    } else if (c == ' ' || c == '.') {
      ms_strbuild_append_byte(&name, '-');
    }
  }
  MsSpan text = ms_strbuild_span(&name);
  while (text.len > 0 && (text.ptr[0] == '-' || text.ptr[0] == '_')) {
    text = ms_span_of(text.ptr + 1, text.len - 1);
  }
  while (text.len > 0 && (text.ptr[text.len - 1] == '-' || text.ptr[text.len - 1] == '_')) {
    text.len--;
  }
  const MsSpan result = text.len == 0 ? ms_span_of_text("app") : ms_arena_copy(arena, text);
  ms_strbuild_free(&name);
  return result;
}

static MsSpan manifest(MsArena *arena, MsSpan name, const char *entry, const char *extra) {
  return ms_message_format(arena, "[project]\nname = %S\nsource = \"./src\"\n%s%s", ms_project_quote(arena, name), entry,
                           extra);
}

/* The files to create, as paths below the project directory. */
static size_t plan(MsArena *arena, const InitOptions *options, MsSpan absolute, InitFile *files) {
  size_t n = 0;
  if (options->workspace) {
    const MsSpan app = manifest(arena, ms_span_of_text("app"), "entry = \"./src/main.ms\"\n",
                                "\n[dependencies]\n\"@greeter\" = { path = \"../libs/greeter\" }\n");
    files[n++] = (InitFile){"ms.toml", ms_span_of_text("[workspace]\nmembers = [\"app\", \"libs/*\"]\n")};
    files[n++] = (InitFile){"app/ms.toml", app};
    files[n++] = (InitFile){"app/src/main.ms", ms_span_of_text(kWorkspaceMain)};
    files[n++] = (InitFile){"app/test.ms", ms_span_of_text(kTest)};
    files[n++] = (InitFile){"libs/greeter/ms.toml", manifest(arena, ms_span_of_text("greeter"), "", "")};
    files[n++] = (InitFile){"libs/greeter/src/lib.ms", ms_span_of_text(kLib)};
    files[n++] = (InitFile){"libs/greeter/test.ms", ms_span_of_text(kLibTest)};
    return n;
  }
  const bool lib = options->library;
  files[n++] = (InitFile){"ms.toml", manifest(arena, project_name(arena, absolute), lib ? "" : "entry = \"./src/main.ms\"\n", "")};
  files[n++] = (InitFile){lib ? "src/lib.ms" : "src/main.ms", ms_span_of_text(lib ? kLib : kMain)};
  files[n++] = (InitFile){"test.ms", ms_span_of_text(lib ? kLibTest : kTest)};
  return n;
}

static MsSpan absolute_of(MsArena *arena, const char *directory) {
  MsString cwd = ms_string_empty();
  MsStrBuild path = ms_strbuild_new();
  if (ms_path_is_absolute(ms_span_of_text(directory)) || !ms_dir_current(&cwd)) {
    ms_strbuild_append_text(&path, directory);
  } else {
    ms_path_append_joined(&path, ms_string_span(&cwd), ms_span_of_text(directory));
    ms_string_release(&cwd);
  }
  MsStrBuild cleaned = ms_strbuild_new();
  ms_path_clean(&cleaned, ms_strbuild_span(&path));
  ms_strbuild_free(&path);
  return ms_project_text(arena, &cleaned);
}

/* Appends `addition` to the file at `path` unless a line passes `present`; creates the file when it is missing. */
static bool append_rule(MsArena *arena, MsSpan path, const char *addition, bool (*present)(MsSpan line)) {
  MsBytes bytes = {0};
  MsSpan existing = {0};
  if (ms_path_kind(path) != MS_PATH_MISSING) {
    if (!ms_file_read(path, &bytes)) {
      return false;
    }
    existing = ms_arena_copy(arena, ms_bytes_span(&bytes));
    ms_bytes_free(&bytes);
  }
  size_t start = 0;
  for (size_t i = 0; i <= existing.len; i++) {
    if (i == existing.len || existing.ptr[i] == '\n') {
      MsSpan line = ms_span_of(existing.ptr + start, i - start);
      while (line.len > 0 && line.ptr[0] <= ' ') {
        line = ms_span_of(line.ptr + 1, line.len - 1);
      }
      while (line.len > 0 && line.ptr[line.len - 1] <= ' ') {
        line.len--;
      }
      if (present(line)) {
        return true;
      }
      start = i + 1;
    }
  }
  const bool newline = existing.len == 0 || existing.ptr[existing.len - 1] == '\n';
  return ms_file_write(path, ms_message_format(arena, "%S%s%s", existing, newline ? "" : "\n", addition));
}

static bool ignores_cache(MsSpan line) {
  return ms_span_is_text(line, ".ms-cache") || ms_span_is_text(line, ".ms-cache/") ||
         ms_span_is_text(line, "/.ms-cache") || ms_span_is_text(line, "/.ms-cache/");
}

static bool pins_sources(MsSpan line) {
  return ms_span_starts_with(line, ms_span_of_text("*.ms "));
}

static bool write_files(MsArena *arena, MsSpan absolute, const InitFile *files, size_t count) {
  for (size_t i = 0; i < count; i++) {
    const MsSpan path = joined(arena, absolute, ms_span_of_text(files[i].name));
    if (!ms_dir_make_all(ms_path_parent(path)) || !ms_file_write(path, files[i].content)) {
      return false;
    }
  }
  return append_rule(arena, joined(arena, absolute, ms_span_of_text(".gitignore")), kIgnore, ignores_cache) &&
         append_rule(arena, joined(arena, absolute, ms_span_of_text(".gitattributes")), kAttributes, pins_sources);
}

/* A path spelled so the argument parser reads it as a file, not an option. */
static MsSpan operand(MsArena *arena, MsSpan path) {
  return path.len > 0 && path.ptr[0] == '-' ? ms_message_format(arena, "./%S", path) : path;
}

/* A path quoted for a command the user can paste. */
static MsSpan shell_quote(MsArena *arena, MsSpan path) {
  bool plain = true;
  for (size_t i = 0; i < path.len; i++) {
    const uint8_t c = path.ptr[i];
    plain = plain && c > ' ' && !(c == '\'' || c == '"' || c == '\\' || c == '$' || c == '`' || c == '!' ||
                                  c == '&' || c == ';' || c == '|' || c == '<' || c == '>' || c == '(' ||
                                  c == ')' || c == '*' || c == '?' || c == '[' || c == ']' || c == '{' ||
                                  c == '}' || c == '#' || c == '~');
  }
  if (plain) {
    return path;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_byte(&text, '\'');
  for (size_t i = 0; i < path.len; i++) {
    ms_strbuild_append(&text, path.ptr[i] == '\'' ? ms_span_of_text("'\\''") : ms_span_of(path.ptr + i, 1));
  }
  ms_strbuild_append_byte(&text, '\'');
  return ms_project_text(arena, &text);
}

static void print_next(MsArena *arena, const InitOptions *options, MsSpan directory) {
  const MsSpan manifest_path = shell_quote(arena, operand(arena, joined(arena, directory, ms_span_of_text("ms.toml"))));
  MsSpan next = {0};
  if (options->workspace) {
    const MsSpan app = shell_quote(arena, operand(arena, joined(arena, directory, ms_span_of_text("app/ms.toml"))));
    next = ms_message_format(arena, "ms run %S; ms test runs every member from %S", app, directory);
  } else if (options->library) {
    next = ms_message_format(arena, "ms test %S", manifest_path);
  } else {
    next = ms_message_format(arena, "ms run %S -- first second", manifest_path);
  }
  print_span(stdout, ms_message_format(arena, "Created project in %S\nNext: %S\n", directory, next));
}

int ms_init_command(int argc, char **argv) {
  MsArena arena = ms_arena_new();
  InitOptions options = {.directory = "."};
  int status = parse_arguments(&arena, argc, argv, &options);
  if (status == 0) {
    const MsSpan directory = ms_span_of_text(options.directory);
    const MsSpan absolute = absolute_of(&arena, options.directory);
    InitFile files[8];
    const size_t count = plan(&arena, &options, absolute, files);
    for (size_t i = 0; i < count && status == 0; i++) {
      if (ms_path_kind(joined(&arena, absolute, ms_span_of_text(files[i].name))) != MS_PATH_MISSING) {
        print_span(stderr, ms_message_format(&arena,
                                             "ms init: %S already exists; run it in an empty directory or remove "
                                             "the file first\n",
                                             joined(&arena, directory, ms_span_of_text(files[i].name))));
        status = STATUS_FAILED;
      }
    }
    if (status == 0 && !write_files(&arena, absolute, files, count)) {
      print_span(stderr, ms_message_format(&arena, "ms init: cannot create project in %S; check that the directory is writable\n", directory));
      status = STATUS_FAILED;
    } else if (status == 0) {
      print_next(&arena, &options, directory);
    }
  }
  ms_arena_free(&arena);
  return status;
}
