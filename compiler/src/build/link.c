/* Linking with the pinned lld (ms/build_link.h). Linux only; see the header. */
#include "ms/build_link.h"

#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include "ms/base.h"
#include "ms/build_tool.h"
#include "ms/text.h"

#if defined(__linux__) && (defined(__x86_64__) || defined(__aarch64__))

#if defined(__aarch64__)
#define BL_TRIPLE "-mtriple=aarch64-unknown-linux-gnu"
#define BL_LOADER "/lib/ld-linux-aarch64.so.1"
#define BL_LOADER_NAME "ld-linux-aarch64.so.1"
#else
#define BL_TRIPLE "-mtriple=x86_64-unknown-linux-gnu"
#define BL_LOADER "/lib64/ld-linux-x86-64.so.2"
#define BL_LOADER_NAME "ld-linux-x86-64.so.2"
#endif

#define BL_PATH 4096

/* The libraries in the order the program lists them: libpthread first, so that before glibc 2.34 its definitions of
 * names libc also exports win, as with `cc -lpthread`. */
static const char *const bl_libraries[] = {"libpthread.so.0", "libc.so.6", "libm.so.6", "libdl.so.2", "librt.so.1", BL_LOADER_NAME};

static bool bl_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

/* One line of glibc.symbols: `soname version name kind [size]`, as slices of the table. */
typedef struct BlExport {
    MsStr soname, version, name;
    bool data;
    uint64_t size; /* the bytes of a data symbol */
} BlExport;

/* The exports of the table, in order; comment and blank lines are skipped. */
static void bl_parse(const char *text, size_t len, MsBuf *out) {
    size_t at = 0;
    while (at < len) {
        const char *newline = memchr(text + at, '\n', len - at);
        const size_t end = newline != NULL ? (size_t)(newline - text) : len;
        MsStr fields[5];
        size_t n = 0;
        size_t i = at;
        while (i < end && n < 5) {
            while (i < end && (text[i] == ' ' || text[i] == '\t')) {
                i++;
            }
            const size_t start = i;
            while (i < end && text[i] != ' ' && text[i] != '\t') {
                i++;
            }
            if (i > start) {
                fields[n++] = (MsStr){text + start, (uint32_t)(i - start)};
            }
        }
        if (n >= 4 && fields[0].ptr[0] != '#') {
            BlExport e = {fields[0], fields[1], fields[2], fields[3].ptr[0] == 'D', 0};
            if (e.data && n > 4) {
                char digits[32];
                (void)snprintf(digits, sizeof digits, "%.*s", (int)fields[4].len, fields[4].ptr);
                e.size = strtoull(digits, NULL, 16);
            }
            MS_VEC_PUSH(*out, BlExport, e);
        }
        at = end + 1;
    }
}

static int bl_compare_versions(const void *a, const void *b) {
    const MsStr x = *(const MsStr *)a, y = *(const MsStr *)b;
    const uint32_t common = x.len < y.len ? x.len : y.len;
    const int order = memcmp(x.ptr, y.ptr, common);
    return order != 0 ? order : (x.len > y.len) - (x.len < y.len);
}

/* Builds the stub of one library into `stage`: IR defining every export (a function, or zeroed data of the size copy
 * relocations need), assembled by `llc` and linked as a shared library whose version script names each version. */
static bool bl_stub(const MsLinkOptions *o, const char *stage, const char *soname, const BlExport *all, size_t count, MsBuf *why) {
    const size_t soname_len = strlen(soname);
    MsBuf ir = {0}, script = {0}, versions = {0};
    for (size_t i = 0; i < count; i++) {
        if (all[i].soname.len != soname_len || memcmp(all[i].soname.ptr, soname, soname_len) != 0) {
            continue;
        }
        bool seen = false;
        for (size_t v = 0; v < MS_VEC_LEN(versions, MsStr); v++) {
            seen = seen || ms_text_equal(MS_VEC_AT(versions, MsStr, v), all[i].version);
        }
        if (!seen) {
            MS_VEC_PUSH(versions, MsStr, all[i].version);
        }
        if (all[i].data) {
            ms_buf_printf(&ir, "@\"%.*s\" = global [%llu x i8] zeroinitializer, align 8\n", (int)all[i].name.len, all[i].name.ptr,
                          (unsigned long long)(all[i].size == 0 ? 1 : all[i].size));
        } else {
            ms_buf_printf(&ir, "define void @\"%.*s\"() {\n  ret void\n}\n", (int)all[i].name.len, all[i].name.ptr);
        }
    }
    qsort(ms_buf_items(&versions), MS_VEC_LEN(versions, MsStr), sizeof(MsStr), bl_compare_versions);
    for (size_t v = 0; v < MS_VEC_LEN(versions, MsStr); v++) {
        const MsStr version = MS_VEC_AT(versions, MsStr, v);
        ms_buf_printf(&script, "%.*s { global:", (int)version.len, version.ptr);
        for (size_t i = 0; i < count; i++) {
            if (all[i].soname.len == soname_len && memcmp(all[i].soname.ptr, soname, soname_len) == 0 && ms_text_equal(all[i].version, version)) {
                ms_buf_printf(&script, " %.*s;", (int)all[i].name.len, all[i].name.ptr);
            }
        }
        ms_buf_puts(&script, " };\n");
    }
    char ll[BL_PATH], obj[BL_PATH], map[BL_PATH], log[BL_PATH], lib[BL_PATH];
    (void)snprintf(ll, sizeof ll, "%s/%s.ll", stage, soname);
    (void)snprintf(obj, sizeof obj, "%s/%s.o", stage, soname);
    (void)snprintf(map, sizeof map, "%s/%s.map", stage, soname);
    (void)snprintf(log, sizeof log, "%s/%s.log", stage, soname);
    (void)snprintf(lib, sizeof lib, "%s/%s", stage, soname);
    bool ok = ms_build_write(ll, ir.data, ir.len) && ms_build_write(map, script.data, script.len);
    if (!ok) {
        ms_buf_printf(why, "cannot write the %s stub: %s", soname, strerror(errno));
    }
    if (ok) {
        char *llc[] = {(char *)o->llc, (char *)"-filetype=obj", (char *)"-relocation-model=pic", (char *)BL_TRIPLE, ll, (char *)"-o", obj, NULL};
        ok = ms_build_run("llc (glibc stubs)", llc, log, why);
    }
    if (ok) {
        char *lld[] = {(char *)o->lld, (char *)"-flavor", (char *)"gnu", (char *)"-shared", (char *)"-soname", (char *)soname,
                       (char *)"--version-script", map, (char *)"-o", lib, obj, NULL};
        ok = ms_build_run("lld (glibc stubs)", lld, log, why);
    }
    const char *const made[] = {ll, obj, map, log};
    for (size_t i = 0; i < sizeof made / sizeof made[0]; i++) {
        (void)unlink(made[i]);
    }
    ms_buf_free(&ir);
    ms_buf_free(&script);
    ms_buf_free(&versions);
    return ok;
}

/* The directory of glibc stubs under `files`, generated once into a private directory and moved into place, so a
 * concurrent build never sees a partial set. */
static bool bl_stubs(const MsLinkOptions *o, char *out, size_t out_size, MsBuf *why) {
    (void)snprintf(out, out_size, "%s/glibc", o->files);
    char done[BL_PATH];
    (void)snprintf(done, sizeof done, "%s/.ok", out);
    if (bl_exists(done)) {
        return true;
    }
    char table_path[BL_PATH];
    (void)snprintf(table_path, sizeof table_path, "%s/glibc.symbols", o->files);
    MsBuf table = {0}, exports = {0};
    if (!ms_build_read(table_path, &table)) {
        ms_buf_printf(why, "cannot read the symbol table for the glibc stubs in %s", table_path);
        ms_buf_free(&table);
        return false;
    }
    bl_parse(table.data, table.len, &exports);
    char stage[BL_PATH];
    (void)snprintf(stage, sizeof stage, "%s/.glibc-XXXXXX", o->files);
    if (mkdtemp(stage) == NULL) {
        ms_buf_printf(why, "cannot create the glibc stubs in %s: %s", out, strerror(errno));
        ms_buf_free(&table);
        ms_buf_free(&exports);
        return false;
    }
    bool ok = true;
    for (size_t i = 0; ok && i < sizeof bl_libraries / sizeof bl_libraries[0]; i++) {
        ok = bl_stub(o, stage, bl_libraries[i], ms_buf_items(&exports), MS_VEC_LEN(exports, BlExport), why);
    }
    char stage_done[BL_PATH];
    (void)snprintf(stage_done, sizeof stage_done, "%s/.ok", stage);
    ok = ok && ms_build_write(stage_done, "", 0);
    bool installed = ok && rename(stage, out) == 0;
    if (!installed) {
        for (size_t i = 0; i < sizeof bl_libraries / sizeof bl_libraries[0]; i++) {
            char path[BL_PATH];
            (void)snprintf(path, sizeof path, "%s/%s", stage, bl_libraries[i]);
            (void)unlink(path);
        }
        (void)unlink(stage_done);
        (void)rmdir(stage);
        installed = ok && bl_exists(done); /* another build installed its set first */
        if (ok && !installed) {
            ms_buf_printf(why, "cannot install the glibc stubs in %s: %s", out, strerror(errno));
        }
    }
    ms_buf_free(&table);
    ms_buf_free(&exports);
    return installed;
}

/* The advice that follows a linker failure: what the missing symbol usually means. */
static void bl_advice(const MsBuf *detail, bool musl, MsBuf *out) {
    static const char marker[] = "undefined symbol: ";
    const char *foreign = NULL;
    size_t foreign_len = 0;
    for (size_t i = 0; detail->len >= sizeof marker && i + sizeof marker - 1 <= detail->len; i++) {
        if (memcmp(detail->data + i, marker, sizeof marker - 1) != 0) {
            continue;
        }
        const char *name = detail->data + i + sizeof marker - 1;
        size_t n = 0;
        while (i + sizeof marker - 1 + n < detail->len && name[n] != '\n' && name[n] != '\r') {
            n++;
        }
        while (n > 0 && name[n - 1] == ' ') {
            n--;
        }
        const bool runtime = (n >= 6 && memcmp(name, "msrt_", 5) == 0) || (n >= 7 && memcmp(name, "msstd_", 6) == 0);
        if (!runtime) {
            foreign = name;
            foreign_len = n;
            break;
        }
    }
    if (foreign != NULL) {
        ms_buf_printf(out,
                      "%.*s is not part of the Manuscript runtime; if an extern fn declares it, pass the object or static library that "
                      "defines it with --link <file>",
                      (int)foreign_len, foreign);
    } else {
        ms_buf_puts(out, "A missing symbol or library usually means a stale or mismatched runtime (check MS_RT_LIB), not a source error");
    }
    if (!musl) {
        ms_buf_puts(out, ". Programs link against glibc 2.28, so an object built against a newer glibc may need symbols it lacks; pass "
                         "--static to link musl instead");
    }
}

bool ms_build_link(const char *object, const char *const *inputs, size_t ninputs, const char *out, const MsLinkOptions *o,
                   MsBackendText *why) {
    MsBuf reason = {0}, argv = {0}, stubs_dir = {0};
    char stubs[BL_PATH];
    bool ok = o->musl || bl_stubs(o, stubs, sizeof stubs, &reason);
    char libunwind[BL_PATH], libc[BL_PATH], crt1[BL_PATH], crti[BL_PATH], crtn[BL_PATH], log[BL_PATH];
    (void)snprintf(libunwind, sizeof libunwind, "%s/libunwind.a", o->files);
    (void)snprintf(libc, sizeof libc, "%s/libc.a", o->files);
    (void)snprintf(crt1, sizeof crt1, "%s/crt1.o", o->files);
    (void)snprintf(crti, sizeof crti, "%s/crti.o", o->files);
    (void)snprintf(crtn, sizeof crtn, "%s/crtn.o", o->files);
    (void)snprintf(log, sizeof log, "%s.link.log", out);
    if (ok) {
        MS_VEC_PUSH(argv, const char *, o->lld);
        const char *const common[] = {"-flavor", "gnu", "--gc-sections", "--eh-frame-hdr", "-o", out};
        for (size_t i = 0; i < sizeof common / sizeof common[0]; i++) {
            MS_VEC_PUSH(argv, const char *, common[i]);
        }
        if (o->strip) {
            MS_VEC_PUSH(argv, const char *, "--strip-all");
        }
        if (o->musl) {
            MS_VEC_PUSH(argv, const char *, "-static");
            MS_VEC_PUSH(argv, const char *, crt1);
            MS_VEC_PUSH(argv, const char *, crti);
        } else {
            const char *const dynamic[] = {"--dynamic-linker", BL_LOADER, "-z", "now", "-z", "relro"};
            for (size_t i = 0; i < sizeof dynamic / sizeof dynamic[0]; i++) {
                MS_VEC_PUSH(argv, const char *, dynamic[i]);
            }
        }
        MS_VEC_PUSH(argv, const char *, object);
        MS_VEC_PUSH(argv, const char *, "--start-group");
        for (size_t i = 0; i < ninputs; i++) {
            MS_VEC_PUSH(argv, const char *, inputs[i]);
        }
        MS_VEC_PUSH(argv, const char *, libunwind);
        if (o->musl) {
            MS_VEC_PUSH(argv, const char *, libc);
        }
        MS_VEC_PUSH(argv, const char *, "--end-group");
        if (o->musl) {
            MS_VEC_PUSH(argv, const char *, crtn);
        } else {
            MS_VEC_PUSH(argv, const char *, "--as-needed");
            for (size_t i = 0; i < sizeof bl_libraries / sizeof bl_libraries[0]; i++) {
                ms_buf_printf(&stubs_dir, "%s/%s", stubs, bl_libraries[i]);
                ms_buf_putc(&stubs_dir, 0);
            }
            const char *path = stubs_dir.data;
            for (size_t i = 0; i < sizeof bl_libraries / sizeof bl_libraries[0]; i++) {
                MS_VEC_PUSH(argv, const char *, path);
                path += strlen(path) + 1;
            }
        }
        MS_VEC_PUSH(argv, const char *, NULL);
        MsBuf detail = {0};
        ok = ms_build_run("the bundled linker", (char *const *)ms_buf_items(&argv), log, &detail);
        if (!ok) {
            ms_buf_printf(&reason, "linking failed; the linker output follows. ");
            MsBuf advice = {0};
            bl_advice(&detail, o->musl, &advice);
            ms_buf_put(&reason, advice.data, advice.len);
            ms_buf_printf(&reason, ":\n%.*s", (int)detail.len, detail.data == NULL ? "" : detail.data);
            ms_buf_free(&advice);
        }
        ms_buf_free(&detail);
    }
    (void)unlink(log);
    ms_buf_free(&argv);
    ms_buf_free(&stubs_dir);
    if (!ok) {
        *why = ms_backend_take(&reason);
        return false;
    }
    ms_buf_free(&reason);
    return true;
}

#else

bool ms_build_link(const char *object, const char *const *inputs, size_t ninputs, const char *out, const MsLinkOptions *o,
                   MsBackendText *why) {
    (void)object;
    (void)inputs;
    (void)ninputs;
    (void)out;
    (void)o;
    MsBuf reason = {0};
    ms_buf_puts(&reason, "the C link is not ported to this host");
    *why = ms_backend_take(&reason);
    return false;
}

#endif
