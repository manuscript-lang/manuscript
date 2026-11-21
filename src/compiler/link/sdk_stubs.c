/* Owns writing the macOS SDK stubs (see sdk_stubs.h). */
#include "compiler/link/sdk_stubs.h"

#include "base/file.h"
#include "base/intern.h"
#include "base/path.h"

#if defined(__aarch64__)
#define ARCH "arm64"
#else
#define ARCH "x86_64"
#endif

typedef struct Library {
  const char *file;         /* path of the stub under the SDK root */
  const char *install_name; /* where dyld finds the real library */
  MsNames symbols;          /* owned: the symbols it exports, in first-seen order */
} Library;

enum { LIBRARY_SYSTEM, LIBRARY_SECURITY, LIBRARY_CORE, LIBRARY_CONFIGURATION, LIBRARY_COUNT };

static const char *const directories[] = {
    "usr", "usr/lib", "System", "System/Library", "System/Library/Frameworks",
    "System/Library/Frameworks/Security.framework", "System/Library/Frameworks/CoreFoundation.framework",
    "System/Library/Frameworks/SystemConfiguration.framework"};

static bool starts(MsSpan name, const char *prefix) {
  return ms_span_starts_with(name, ms_span_of_text(prefix));
}

/* The library whose names start like `name`: the frameworks by prefix, everything else libSystem. */
static size_t library_of(MsSpan name) {
  if (starts(name, "_Sec") || starts(name, "_kSec")) {
    return LIBRARY_SECURITY;
  }
  if (starts(name, "_CF") || starts(name, "_kCF")) {
    return LIBRARY_CORE;
  }
  if (starts(name, "_SC") || starts(name, "_kSC")) {
    return LIBRARY_CONFIGURATION;
  }
  return LIBRARY_SYSTEM;
}

static void append_stub(MsStrBuild *out, const Library *library) {
  ms_strbuild_append_text(out, "--- !tapi-tbd\ntbd-version: 4\ntargets: [ " ARCH "-macos ]\ninstall-name: '");
  ms_strbuild_append_text(out, library->install_name);
  ms_strbuild_append_text(out, "'\ncurrent-version: 1\nexports:\n  - targets: [ " ARCH "-macos ]\n    symbols: [");
  size_t count = ms_names_count(&library->symbols);
  for (size_t index = 1; index < count; index++) { /* name 0 is the empty text */
    ms_strbuild_append_text(out, index == 1 ? "\n" : ",\n");
    ms_strbuild_append_text(out, "      '");
    ms_strbuild_append(out, ms_names_span(&library->symbols, (MsName)index));
    ms_strbuild_append_byte(out, '\'');
  }
  ms_strbuild_append_text(out, " ]\n...\n");
}

static bool write_stub(MsSpan sdk, const Library *library, MsStrBuild *why) {
  MsStrBuild path = ms_strbuild_new();
  ms_path_append_joined(&path, sdk, ms_span_of_text(library->file));
  MsStrBuild text = ms_strbuild_new();
  append_stub(&text, library);
  bool ok = ms_file_write(ms_strbuild_span(&path), ms_strbuild_span(&text));
  if (!ok) {
    ms_strbuild_append_text(why, "cannot write the SDK stubs: ");
    ms_strbuild_append(why, ms_strbuild_span(&path));
  }
  ms_strbuild_free(&path);
  ms_strbuild_free(&text);
  return ok;
}

static bool make_directories(MsSpan sdk, MsStrBuild *why) {
  for (size_t index = 0; index < MS_COUNT_OF(directories); index++) {
    MsStrBuild path = ms_strbuild_new();
    ms_path_append_joined(&path, sdk, ms_span_of_text(directories[index]));
    bool ok = ms_dir_make_all(ms_strbuild_span(&path));
    if (!ok) {
      ms_strbuild_append_text(why, "cannot write the SDK stubs: ");
      ms_strbuild_append(why, ms_strbuild_span(&path));
    }
    ms_strbuild_free(&path);
    if (!ok) {
      return false;
    }
  }
  return true;
}

/* Names the program imports and nothing it links defines; `binder` is lld's own lazy-binding import,
 * spelled without the usual leading underscore. */
static void assign_imports(const MachoSymbols *symbols, MsNames *defined, Library libraries[LIBRARY_COUNT]) {
  for (size_t index = 0; index < symbols->defined.len; index++) {
    (void)ms_names_intern(defined, symbols->defined.ptr[index]);
  }
  MsName found = 0;
  for (size_t index = 0; index < symbols->undefined.len; index++) {
    MsSpan name = symbols->undefined.ptr[index];
    if (!ms_names_find(defined, name, &found)) {
      (void)ms_names_intern(&libraries[library_of(name)].symbols, name);
    }
  }
  (void)ms_names_intern(&libraries[LIBRARY_SYSTEM].symbols, ms_span_of_text("dyld_stub_binder"));
}

bool link_sdk_stubs(MsSpan sdk, const MachoSymbols *symbols, MsStrBuild *why) {
  Library libraries[LIBRARY_COUNT] = {
      [LIBRARY_SYSTEM] = {.file = "usr/lib/libSystem.tbd", .install_name = "/usr/lib/libSystem.B.dylib"},
      [LIBRARY_SECURITY] = {.file = "System/Library/Frameworks/Security.framework/Security.tbd",
                            .install_name = "/System/Library/Frameworks/Security.framework/Versions/A/Security"},
      [LIBRARY_CORE] = {.file = "System/Library/Frameworks/CoreFoundation.framework/CoreFoundation.tbd",
                        .install_name = "/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation"},
      [LIBRARY_CONFIGURATION] = {
          .file = "System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration.tbd",
          .install_name = "/System/Library/Frameworks/SystemConfiguration.framework/Versions/A/SystemConfiguration"}};
  MsNames defined;
  ms_names_init(&defined);
  for (size_t index = 0; index < LIBRARY_COUNT; index++) {
    ms_names_init(&libraries[index].symbols);
  }
  assign_imports(symbols, &defined, libraries);
  bool ok = make_directories(sdk, why);
  for (size_t index = 0; index < LIBRARY_COUNT; index++) {
    ok = ok && write_stub(sdk, &libraries[index], why);
    ms_names_free(&libraries[index].symbols);
  }
  ms_names_free(&defined);
  return ok;
}
