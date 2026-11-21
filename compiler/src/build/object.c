/* MIR text to an object file (ms/build_object.h): the C back end writes IR, `opt` and `llc` compile it, and the
 * fault tables join the assembly before the last `llc` assembles it. Every step runs in a private directory that
 * is removed on the way out. */
#include "ms/build_object.h"

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

/* The target the host builds for, as the LLVM triple; NULL where the build is not ported. */
static const char *bo_triple(void) {
#if defined(__x86_64__) && defined(__linux__)
    return "x86_64-unknown-linux-gnu";
#elif defined(__aarch64__) && defined(__linux__)
    return "aarch64-unknown-linux-gnu";
#elif defined(__x86_64__) && defined(__APPLE__)
    return "x86_64-apple-darwin";
#elif defined(__aarch64__) && defined(__APPLE__)
    return "aarch64-apple-darwin";
#else
    return NULL;
#endif
}

/* The path `name` in the directory `dir`. */
static void bo_path(MsBuf *out, const char *dir, const char *name) {
    out->len = 0;
    ms_buf_printf(out, "%s/%s", dir, name);
    ms_buf_putc(out, 0);
}

/* Runs `argv`; the reason of a failure goes to `why`. */
static bool bo_run(const char *what, const char *const *argv, const char *log, MsBackendText *why) {
    MsBuf reason = {0};
    if (ms_build_run(what, argv, log, &reason)) {
        ms_buf_free(&reason);
        return true;
    }
    *why = ms_backend_take(&reason);
    return false;
}

/* The assembly as `module asm` lines of an LLVM module, so `llc` assembles it. The COFF `@feat.00` symbol is left
 * to the wrapping module. */
static void bo_asm_module(const char *text, size_t len, MsBuf *out) {
    static const char features[] = "@feat.00";
    bool in_features_def = false;
    size_t at = 0;
    while (at <= len) {
        const char *newline = memchr(text + at, '\n', len - at);
        const size_t end = newline != NULL ? (size_t)(newline - text) : len;
        const char *line = text + at;
        const size_t n = end - at;
        at = end + 1;
        bool names_features = false;
        for (size_t i = 0; i + sizeof features - 1 <= n; i++) {
            names_features = names_features || memcmp(line + i, features, sizeof features - 1) == 0;
        }
        if (in_features_def) {
            bool ends = false;
            for (size_t i = 0; i + 6 <= n; i++) {
                ends = ends || memcmp(line + i, ".endef", 6) == 0;
            }
            in_features_def = !ends;
            continue;
        }
        if (names_features) {
            size_t lead = 0;
            while (lead < n && (line[lead] == ' ' || line[lead] == '\t' || line[lead] == '\n' || line[lead] == '\r')) {
                lead++;
            }
            in_features_def = n - lead >= 4 && memcmp(line + lead, ".def", 4) == 0;
            continue;
        }
        ms_buf_puts(out, "module asm \"");
        for (size_t i = 0; i < n; i++) {
            const unsigned char byte = (unsigned char)line[i];
            if (byte >= 0x20 && byte < 0x7f && byte != '"' && byte != '\\') {
                ms_buf_putc(out, (char)byte);
            } else {
                ms_buf_printf(out, "\\%02X", byte);
            }
        }
        ms_buf_puts(out, "\"\n");
    }
}

/* The tools and the files of the steps after the IR; every path is NUL-terminated for `bo_run`. */
typedef struct {
    MsBuf triple, opt, llc, ll, bc, plain, wrapped, obj, log;
} BoFiles;

static void bo_files_free(BoFiles *f) {
    MsBuf *all[] = {&f->triple, &f->opt, &f->llc, &f->ll, &f->bc, &f->plain, &f->wrapped, &f->obj, &f->log};
    for (size_t i = 0; i < sizeof all / sizeof all[0]; i++) {
        ms_buf_free(all[i]);
    }
}

/* Sets `why` to `what` followed by `path` and returns false. */
static bool bo_fail_at(MsBackendText *why, const char *what, const char *path) {
    MsBuf message = {0};
    ms_buf_printf(&message, "%s %s", what, path);
    *why = ms_backend_take(&message);
    return false;
}

/* `opt` over the IR file at -O3 into the bitcode file. */
static bool bo_optimize(const BoFiles *f, const MsObjectOptions *o, MsBackendText *why) {
    const char *argv[10];
    size_t n = 0;
    argv[n++] = f->opt.data;
    if (!o->vectorize) {
        argv[n++] = "-vectorize-loops=false";
        argv[n++] = "-vectorize-slp=false";
    }
    if (o->llvm_verify) {
        argv[n++] = "-verify-each";
    }
    argv[n++] = f->triple.data;
    argv[n++] = "-passes=default<O3>";
    argv[n++] = f->ll.data;
    argv[n++] = "-o";
    argv[n++] = f->bc.data;
    argv[n] = NULL;
    return bo_run("opt (LLVM optimizer)", argv, f->log.data, why);
}

/* `llc` from `input` to assembly text. */
static bool bo_codegen(const BoFiles *f, const MsObjectOptions *o, const char *input, MsBackendText *why) {
    const char *argv[14];
    size_t n = 0;
    argv[n++] = f->llc.data;
    argv[n++] = o->backend.speed ? "-O3" : "-O0";
    argv[n++] = "-filetype=asm";
    argv[n++] = "-relocation-model=pic";
    argv[n++] = f->triple.data;
#if defined(__x86_64__)
    argv[n++] = "-align-loops=32";
    argv[n++] = "-mcpu=x86-64";
#endif
    argv[n++] = input;
    argv[n++] = "-o";
    argv[n++] = f->plain.data;
    argv[n] = NULL;
    return bo_run("llc (LLVM code generator)", argv, f->log.data, why);
}

/* The assembly with the fault tables, wrapped as `module asm` lines and written to the wrapped file. */
static bool bo_add_tables(const BoFiles *f, const MsBackendText *meta, MsBackendText *why) {
    MsBuf assembly = {0}, wrapped_text = {0};
    MsBackendText with_tables = {0};
    bool ok = ms_build_read(f->plain.data, &assembly) || bo_fail_at(why, "cannot read", f->plain.data);
    if (ok) {
        const char *prefix =
#ifdef __APPLE__
            "_";
#else
            "";
#endif
        ok = ms_backend_tables(meta->ptr, meta->len, assembly.data, assembly.len, prefix, &with_tables, why);
    }
    if (ok) {
        bo_asm_module(with_tables.ptr == NULL ? "" : with_tables.ptr, with_tables.len, &wrapped_text);
        ok = ms_build_write(f->wrapped.data, wrapped_text.data, wrapped_text.len) ||
             bo_fail_at(why, "cannot write", f->wrapped.data);
    }
    ms_backend_free(&with_tables);
    ms_buf_free(&assembly);
    ms_buf_free(&wrapped_text);
    return ok;
}

/* `llc` over the wrapped module into the object file, whose bytes go to `object`. */
static bool bo_assemble(const BoFiles *f, MsBackendText *object, MsBackendText *why) {
    const char *argv[10] = {f->llc.data, "-filetype=obj", "-relocation-model=pic", f->triple.data, f->wrapped.data,
                            "-o",        f->obj.data,     NULL};
    if (!bo_run("llc (assembler)", argv, f->log.data, why)) {
        return false;
    }
    MsBuf bytes = {0};
    const bool ok = ms_build_read(f->obj.data, &bytes) || bo_fail_at(why, "cannot read", f->obj.data);
    if (ok) {
        *object = ms_backend_take(&bytes);
    }
    ms_buf_free(&bytes);
    return ok;
}

/* The steps after the IR: optimize, assemble to text, add the fault tables, assemble to an object. */
static bool bo_compile(const char *dir, const MsObjectOptions *o, const MsBackendText *ir, const MsBackendText *meta,
                       MsBackendText *object, MsBackendText *why) {
    const char *triple_name = bo_triple();
    if (triple_name == NULL) {
        MsBuf message = {0};
        ms_buf_puts(&message, "the C build is not ported to this host");
        *why = ms_backend_take(&message);
        return false;
    }
    BoFiles f = {0};
    ms_buf_printf(&f.triple, "-mtriple=%s", triple_name);
    ms_buf_putc(&f.triple, 0);
    ms_buf_printf(&f.opt, "%s/opt", o->tools);
    ms_buf_putc(&f.opt, 0);
    ms_buf_printf(&f.llc, "%s/llc", o->tools);
    ms_buf_putc(&f.llc, 0);
    bo_path(&f.ll, dir, "program.ll");
    bo_path(&f.bc, dir, "program.bc");
    bo_path(&f.plain, dir, "program.plain.s");
    bo_path(&f.wrapped, dir, "program.asm.ll");
    bo_path(&f.obj, dir, "program.o");
    bo_path(&f.log, dir, "tool.log");
    bool ok = ms_build_write(f.ll.data, ir->ptr, ir->len) || bo_fail_at(why, "cannot write", f.ll.data);
    if (ok && o->keep_ll != NULL) {
        (void)ms_build_write(o->keep_ll, ir->ptr, ir->len);
    }
    ok = ok && (!o->backend.speed || bo_optimize(&f, o, why));
    ok = ok && bo_codegen(&f, o, o->backend.speed ? f.bc.data : f.ll.data, why);
    ok = ok && bo_add_tables(&f, meta, why);
    ok = ok && bo_assemble(&f, object, why);
    const char *const made[] = {f.ll.data, f.bc.data, f.plain.data, f.wrapped.data, f.obj.data, f.log.data};
    for (size_t i = 0; i < sizeof made / sizeof made[0]; i++) {
        (void)unlink(made[i]);
    }
    bo_files_free(&f);
    return ok;
}

bool ms_build_object(const char *mir, size_t mir_len, const char *shown, size_t shown_len, const MsObjectOptions *options,
                     MsBackendText *object, MsBackendText *why) {
    MsBackendText ir = {0}, meta = {0};
    MsBackendOptions backend = options->backend;
    backend.tables = true;
    backend.verify = true;
    if (!ms_backend_ir(mir, mir_len, "program.mir", shown, shown_len, &backend, &ir, &meta, why)) {
        return false;
    }
    const char *temp = getenv("TMPDIR"); // NOLINT(concurrency-mt-unsafe): read before any thread starts.
    MsBuf pattern = {0};
    ms_buf_printf(&pattern, "%s/ms-cbackend-XXXXXX", temp != NULL && *temp != '\0' ? temp : "/tmp");
    ms_buf_putc(&pattern, 0);
    bool ok = false;
    if (!ms_build_make_dir(pattern.data)) {
        MsBuf message = {0};
        ms_buf_puts(&message, "cannot create a build directory: ");
        ms_build_errno_text(errno, &message);
        *why = ms_backend_take(&message);
    } else {
        ok = bo_compile(pattern.data, options, &ir, &meta, object, why);
        ms_build_unlink(pattern.data);
    }
    ms_buf_free(&pattern);
    ms_backend_free(&ir);
    ms_backend_free(&meta);
    return ok;
}
