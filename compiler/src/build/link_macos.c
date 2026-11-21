/* The macOS link (ms/build_link.h): lld over generated SDK stubs, then a debug companion. Apple's SDK is not
 * redistributable and is absent without Xcode tools, so the stubs (`.tbd` text files, which lld reads like the real
 * ones) export exactly the symbols the program and runtime import but do not define; dyld binds those names in the
 * real libSystem, Security, CoreFoundation and SystemConfiguration. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "build/link_internal.h"
#include "ms/base.h"
#include "ms/build_macho.h"
#include "ms/build_tool.h"
#include "ms/hints.h"

#if defined(__APPLE__)

#include <unistd.h>

#if defined(__aarch64__)
#define BM_ARCH "arm64"
#else
#define BM_ARCH "x86_64"
#endif

/* Sorts `list` (MsStr) and drops repeats. */
static size_t bm_sort_unique(MsBuf *list) {
    MsStr *items = ms_buf_items(list);
    size_t count = MS_VEC_LEN(*list, MsStr);
    if (count > 1) {
        qsort(items, count, sizeof(MsStr), ms_str_compare_ptr);
    }
    size_t kept = 0;
    for (size_t i = 0; i < count; i++) {
        if (kept == 0 || ms_str_compare_ptr(&items[kept - 1], &items[i]) != 0) {
            items[kept++] = items[i];
        }
    }
    return kept;
}

static bool bm_has(const MsStr *items, size_t count, MsStr name) {
    size_t lo = 0, hi = count;
    while (lo < hi) {
        const size_t mid = lo + (hi - lo) / 2;
        const int order = ms_str_compare_ptr(&items[mid], &name);
        if (order == 0) {
            return true;
        }
        if (order < 0) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    return false;
}

static bool bm_starts(MsStr name, const char *prefix) {
    const size_t n = strlen(prefix);
    return name.len >= n && memcmp(name.ptr, prefix, n) == 0;
}

/* One text-based dylib stub (TAPI v4) exporting `symbols`. */
static void bm_tbd(MsBuf *out, const char *install_name, const MsBuf *symbols) {
    ms_buf_printf(out,
                  "--- !tapi-tbd\ntbd-version: 4\ntargets: [ " BM_ARCH "-macos ]\ninstall-name: '%s'\ncurrent-version: 1\nexports:\n"
                  "  - targets: [ " BM_ARCH "-macos ]\n    symbols: [",
                  install_name);
    const MsStr *items = ms_buf_items((MsBuf *)symbols);
    for (size_t i = 0; i < MS_VEC_LEN(*symbols, MsStr); i++) {
        ms_buf_printf(out, "%s      '%.*s'", i == 0 ? "\n" : ",\n", (int)items[i].len, items[i].ptr);
    }
    ms_buf_puts(out, " ]\n...\n");
}

static bool bm_write_tbd(const char *path, const char *install_name, const MsBuf *symbols, MsBuf *why) {
    MsBuf text = {0};
    bm_tbd(&text, install_name, symbols);
    const bool ok = ms_build_write(path, text.data, text.len);
    if (!ok) {
        ms_buf_printf(why, "cannot write the SDK stubs: %s", path);
    }
    ms_buf_free(&text);
    return ok;
}

/* Writes `usr/lib/libSystem.tbd` and the three framework stubs under `sdk`, for the symbols the object and the inputs import
 * and do not define. */
static bool bm_stubs(const BlJob *job, const char *sdk, MsBuf *why) {
    MsMachoSymbols symbols = {0};
    MsBuf contents[64] = {{0}};
    size_t nfiles = 0;
    bool ok = true;
    const char *paths[65];
    paths[0] = job->object;
    for (size_t i = 0; i < job->ninputs && i < 64; i++) {
        paths[i + 1] = job->inputs[i];
    }
    const size_t total = 1 + (job->ninputs < 64 ? job->ninputs : 64);
    for (size_t i = 0; ok && i < total; i++) {
        if (!ms_build_read(paths[i], &contents[nfiles])) {
            ms_buf_printf(why, "cannot read %s", paths[i]);
            ok = false;
            break;
        }
        ms_macho_collect(contents[nfiles].data == NULL ? "" : contents[nfiles].data, contents[nfiles].len, &symbols);
        nfiles++;
    }
    MsBuf system = {0}, security = {0}, core = {0}, configuration = {0};
    if (ok) {
        /* lld's own lazy-binding stubs import this, spelled without the usual leading underscore. */
        const MsStr binder = {"dyld_stub_binder", 16};
        MS_VEC_PUSH(symbols.undefined, MsStr, binder);
        const size_t ndefined = bm_sort_unique(&symbols.defined);
        const size_t nundefined = bm_sort_unique(&symbols.undefined);
        const MsStr *defined = ms_buf_items(&symbols.defined);
        const MsStr *undefined = ms_buf_items(&symbols.undefined);
        for (size_t i = 0; i < nundefined; i++) {
            if (bm_has(defined, ndefined, undefined[i])) {
                continue;
            }
            const MsStr name = undefined[i];
            MsBuf *list = bm_starts(name, "_Sec") || bm_starts(name, "_kSec")   ? &security
                          : bm_starts(name, "_CF") || bm_starts(name, "_kCF")   ? &core
                          : bm_starts(name, "_SC") || bm_starts(name, "_kSC")   ? &configuration
                                                                                : &system;
            MS_VEC_PUSH(*list, MsStr, name);
        }
        char path[BL_PATH];
        (void)snprintf(path, sizeof path, "%s/usr/lib", sdk);
        const char *const dirs[] = {"usr", "usr/lib", "System", "System/Library", "System/Library/Frameworks",
                                    "System/Library/Frameworks/Security.framework", "System/Library/Frameworks/CoreFoundation.framework",
                                    "System/Library/Frameworks/SystemConfiguration.framework"};
        for (size_t i = 0; ok && i < sizeof dirs / sizeof dirs[0]; i++) {
            (void)snprintf(path, sizeof path, "%s/%s", sdk, dirs[i]);
            ok = ms_build_make_path(path);
            if (!ok) {
                ms_buf_printf(why, "cannot write the SDK stubs: %s", path);
            }
        }
        (void)snprintf(path, sizeof path, "%s/usr/lib/libSystem.tbd", sdk);
        ok = ok && bm_write_tbd(path, "/usr/lib/libSystem.B.dylib", &system, why);
        (void)snprintf(path, sizeof path, "%s/System/Library/Frameworks/Security.framework/Security.tbd", sdk);
        ok = ok && bm_write_tbd(path, "/System/Library/Frameworks/Security.framework/Versions/A/Security", &security, why);
        (void)snprintf(path, sizeof path, "%s/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation.tbd", sdk);
        ok = ok && bm_write_tbd(path, "/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation", &core, why);
        (void)snprintf(path, sizeof path, "%s/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration.tbd", sdk);
        ok = ok && bm_write_tbd(path, "/System/Library/Frameworks/SystemConfiguration.framework/Versions/A/SystemConfiguration", &configuration, why);
    }
    for (size_t i = 0; i < nfiles; i++) {
        ms_buf_free(&contents[i]);
    }
    ms_buf_free(&system);
    ms_buf_free(&security);
    ms_buf_free(&core);
    ms_buf_free(&configuration);
    ms_macho_free(&symbols);
    return ok;
}

/* `path` made absolute without resolving links or `..`, so the linker and the debug companion see one spelling. */
static const char *bm_absolute(BlJob *job, const char *path) {
    if (path[0] == '/') {
        return path;
    }
    char cwd[BL_PATH];
    if (getcwd(cwd, sizeof cwd) == NULL) {
        return path;
    }
    return ms_arena_fmt(&job->arena, "%s/%s", cwd, path).ptr;
}

bool ms_link_prepare(BlJob *job, MsBuf *why) {
    const MsLinkOptions *o = job->options;
    char pattern[BL_PATH];
    (void)snprintf(pattern, sizeof pattern, "%s/.sdk-XXXXXX", o->files);
    if (!ms_build_make_dir(pattern)) {
        ms_buf_printf(why, "cannot stage the SDK stubs in %s", o->files);
        return false;
    }
    job->scratch = ms_arena_strndup(&job->arena, pattern, strlen(pattern));
    if (!bm_stubs(job, job->scratch, why)) {
        return false;
    }
    const char *const head[] = {o->lld, "-flavor", "darwin", "-arch", BM_ARCH, "-platform_version", "macos", "12.0", "12.0", "-syslibroot"};
    for (size_t i = 0; i < sizeof head / sizeof head[0]; i++) {
        ms_link_push(job, head[i]);
    }
    ms_link_push(job, job->scratch);
    ms_link_push(job, "-dead_strip");
    /* lld turns `adrp x10, got; ...; ldr x8, [x10, got]` into `adr x8` at the adrp, clobbering an x8 the code in between
     * still uses (a list of string literals stored a shift result). Workaround: remove once lld is fixed (#1748). */
    ms_link_push(job, "-ignore_optimization_hints");
    if (o->strip) {
        ms_link_push(job, "-x");
    }
    const char *object = bm_absolute(job, job->object);
    const char *slash = strrchr(object, '/');
    /* The directory boundary is part of the prefix: names stay relative to it, and a sibling such as `stage-external` is
     * never stripped. */
    const char *prefix = slash == NULL ? "" : ms_arena_fmt(&job->arena, "%.*s", (int)(slash - object + 1), object).ptr;
    ms_link_push(job, "-oso_prefix");
    ms_link_push(job, prefix);
    ms_link_push(job, "-o");
    ms_link_push(job, bm_absolute(job, job->out));
    ms_link_push(job, object);
    for (size_t i = 0; i < job->ninputs; i++) {
        ms_link_push(job, bm_absolute(job, job->inputs[i]));
    }
    const char *const tail[] = {"-lSystem", "-framework", "Security", "-framework", "CoreFoundation", "-framework", "SystemConfiguration"};
    for (size_t i = 0; i < sizeof tail / sizeof tail[0]; i++) {
        ms_link_push(job, tail[i]);
    }
    return true;
}

/* The debug companion of the executable: macOS keeps source lines in a dSYM bundle once the object files are removed.
 * Without `dsymutil` (no Xcode tools) the executable still runs; it just has no source lines. */
static bool bm_companion(BlJob *job, MsBuf *why) {
    MsMachoSymbols symbols = {0};
    MsBuf contents[65] = {{0}};
    size_t nfiles = 0;
    const char *paths[65];
    paths[0] = job->object;
    for (size_t i = 0; i < job->ninputs && i < 64; i++) {
        paths[i + 1] = job->inputs[i];
    }
    const size_t total = 1 + (job->ninputs < 64 ? job->ninputs : 64);
    for (size_t i = 0; i < total; i++) {
        if (ms_build_read(paths[i], &contents[nfiles])) {
            ms_macho_collect(contents[nfiles].data == NULL ? "" : contents[nfiles].data, contents[nfiles].len, &symbols);
            nfiles++;
        }
    }
    const bool debug = symbols.debug;
    ms_macho_free(&symbols);
    for (size_t i = 0; i < nfiles; i++) {
        ms_buf_free(&contents[i]);
    }
    if (!debug || !ms_build_have("dsymutil")) {
        return true;
    }
    const char *object = bm_absolute(job, job->object);
    const char *slash = strrchr(object, '/');
    const char *dir = slash == NULL ? "." : ms_arena_fmt(&job->arena, "%.*s", (int)(slash - object), object).ptr;
    const char *out = bm_absolute(job, job->out);
    const char *companion = ms_arena_fmt(&job->arena, "%s.dSYM", out).ptr;
    const char *argv[] = {"dsymutil", out, "-o", companion, NULL};
    const char *log = ms_arena_fmt(&job->arena, "%s.dsym.log", out).ptr;
    const bool ok = ms_build_run_in("dsymutil", argv, dir, log, why);
    ms_build_unlink(log);
    return ok;
}

bool ms_link_finish(BlJob *job, bool linked, MsBuf *why) {
    if (job->scratch != NULL) {
        ms_build_remove_tree(job->scratch);
    }
    return !linked || bm_companion(job, why);
}

void ms_link_advice(const MsBuf *detail, bool musl, MsBuf *out) {
    (void)musl;
    ms_link_foreign_advice(detail, out);
}

#endif
