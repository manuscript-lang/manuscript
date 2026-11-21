/* The Linux link: glibc 2.28 stand-ins generated from glibc.symbols, or static musl (ms/build_link.h). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "build/link_internal.h"
#include "ms/base.h"
#include "ms/build_tool.h"
#include "ms/hints.h"
#include "ms/text.h"

#if defined(__linux__) && (defined(__x86_64__) || defined(__aarch64__))

#include <errno.h>

#include <sys/stat.h>

#include <unistd.h>

#if defined(__aarch64__)
#define BL_TRIPLE "-mtriple=aarch64-unknown-linux-gnu"
#define BL_LOADER "/lib/ld-linux-aarch64.so.1"
#define BL_LOADER_NAME "ld-linux-aarch64.so.1"
#else
#define BL_TRIPLE "-mtriple=x86_64-unknown-linux-gnu"
#define BL_LOADER "/lib64/ld-linux-x86-64.so.2"
#define BL_LOADER_NAME "ld-linux-x86-64.so.2"
#endif

/* The libraries in the order the program lists them: libpthread first, so that before glibc 2.34 its definitions of
 * names libc also exports win, as with `cc -lpthread`. */
static const char *const bl_libraries[] = {"libpthread.so.0", "libc.so.6", "libm.so.6", "libdl.so.2", "librt.so.1", BL_LOADER_NAME};

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
    qsort(ms_buf_items(&versions), MS_VEC_LEN(versions, MsStr), sizeof(MsStr), ms_str_compare_ptr);
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
        ms_buf_printf(why, "cannot write the %s stub: ", soname);
        ms_build_errno_text(errno, why);
    }
    if (ok) {
        const char *llc[] = {o->llc, "-filetype=obj", "-relocation-model=pic", BL_TRIPLE, ll, "-o", obj, NULL};
        ok = ms_build_run("llc (glibc stubs)", llc, log, why);
    }
    if (ok) {
        const char *lld[] = {o->lld, "-flavor", "gnu", "-shared", "-soname", soname,
                       "--version-script", map, "-o", lib, obj, NULL};
        ok = ms_build_run("lld (glibc stubs)", lld, log, why);
    }
    const char *const made[] = {ll, obj, map, log};
    for (size_t i = 0; i < sizeof made / sizeof made[0]; i++) {
        ms_build_unlink(made[i]);
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
    if (ms_link_exists(done)) {
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
    if (!ms_build_make_dir(stage)) {
        ms_buf_printf(why, "cannot create the glibc stubs in %s: ", out);
        ms_build_errno_text(errno, why);
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
            ms_build_unlink(path);
        }
        ms_build_unlink(stage_done);
        ms_build_unlink(stage);
        installed = ok && ms_link_exists(done); /* another build installed its set first */
        if (ok && !installed) {
            ms_buf_printf(why, "cannot install the glibc stubs in %s: ", out);
            ms_build_errno_text(errno, why);
        }
    }
    ms_buf_free(&table);
    ms_buf_free(&exports);
    return installed;
}


bool ms_link_prepare(BlJob *job, MsBuf *why) {
    const MsLinkOptions *o = job->options;
    char stubs[BL_PATH];
    if (!o->musl && !bl_stubs(o, stubs, sizeof stubs, why)) {
        return false;
    }
    const char *const common[] = {o->lld, "-flavor", "gnu", "--gc-sections", "--eh-frame-hdr", "-o", job->out};
    for (size_t i = 0; i < sizeof common / sizeof common[0]; i++) {
        ms_link_push(job, common[i]);
    }
    if (o->strip) {
        ms_link_push(job, "--strip-all");
    }
    if (o->musl) {
        ms_link_push(job, "-static");
        ms_link_push(job, ms_arena_fmt(&job->arena, "%s/crt1.o", o->files).ptr);
        ms_link_push(job, ms_arena_fmt(&job->arena, "%s/crti.o", o->files).ptr);
    } else {
        const char *const dynamic[] = {"--dynamic-linker", BL_LOADER, "-z", "now", "-z", "relro"};
        for (size_t i = 0; i < sizeof dynamic / sizeof dynamic[0]; i++) {
            ms_link_push(job, dynamic[i]);
        }
    }
    ms_link_push(job, job->object);
    ms_link_push(job, "--start-group");
    for (size_t i = 0; i < job->ninputs; i++) {
        ms_link_push(job, job->inputs[i]);
    }
    ms_link_push(job, ms_arena_fmt(&job->arena, "%s/libunwind.a", o->files).ptr);
    if (o->musl) {
        ms_link_push(job, ms_arena_fmt(&job->arena, "%s/libc.a", o->files).ptr);
    }
    ms_link_push(job, "--end-group");
    if (o->musl) {
        ms_link_push(job, ms_arena_fmt(&job->arena, "%s/crtn.o", o->files).ptr);
        return true;
    }
    ms_link_push(job, "--as-needed");
    for (size_t i = 0; i < sizeof bl_libraries / sizeof bl_libraries[0]; i++) {
        ms_link_push(job, ms_arena_fmt(&job->arena, "%s/%s", stubs, bl_libraries[i]).ptr);
    }
    return true;
}

bool ms_link_finish(BlJob *job, bool linked, MsBuf *why) {
    (void)job;
    (void)linked;
    (void)why;
    return true;
}

void ms_link_advice(const MsBuf *detail, bool musl, MsBuf *out) {
    ms_link_foreign_advice(detail, out);
    if (!musl) {
        ms_buf_puts(out, ". Programs link against glibc 2.28, so an object built against a newer glibc may need symbols it lacks; pass "
                         "--static to link musl instead");
    }
}

#endif
