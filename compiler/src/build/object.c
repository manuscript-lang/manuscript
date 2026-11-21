/* MIR text to an object file (ms/build_object.h): the C back end writes IR, `opt` and `llc` compile it, and the
 * fault tables join the assembly before the last `llc` assembles it. Every step runs in a private directory that
 * is removed on the way out. */
#if !defined(_WIN32) && !defined(_POSIX_C_SOURCE)
#define _POSIX_C_SOURCE 200809L
#endif
#if defined(__APPLE__) && !defined(_DARWIN_C_SOURCE)
#define _DARWIN_C_SOURCE
#endif
#include "ms/build_object.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
#elif defined(__x86_64__) && defined(_WIN32)
    return "x86_64-w64-windows-gnu";
#elif defined(__aarch64__) && defined(_WIN32)
    return "aarch64-w64-windows-gnu";
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

/* The files and tool paths of one build, all inside the private directory. */
typedef struct BoFiles {
    MsBuf triple, opt, llc, ll, bc, plain, wrapped, obj, log;
} BoFiles;

static void bo_files_init(BoFiles *f, const char *dir, const char *tools, const char *triple_name) {
    ms_buf_printf(&f->triple, "-mtriple=%s", triple_name);
    ms_buf_putc(&f->triple, 0);
    ms_buf_printf(&f->opt, "%s/opt", tools);
    ms_buf_putc(&f->opt, 0);
    ms_buf_printf(&f->llc, "%s/llc", tools);
    ms_buf_putc(&f->llc, 0);
    bo_path(&f->ll, dir, "program.ll");
    bo_path(&f->bc, dir, "program.bc");
    bo_path(&f->plain, dir, "program.plain.s");
    bo_path(&f->wrapped, dir, "program.asm.ll");
    bo_path(&f->obj, dir, "program.o");
    bo_path(&f->log, dir, "tool.log");
}

static void bo_files_free(BoFiles *f) {
    const char *const made[] = {f->ll.data, f->bc.data, f->plain.data, f->wrapped.data, f->obj.data, f->log.data};
    for (size_t i = 0; i < sizeof made / sizeof made[0]; i++) {
        ms_build_unlink(made[i]);
    }
    MsBuf *const all[] = {&f->triple, &f->opt, &f->llc, &f->ll, &f->bc, &f->plain, &f->wrapped, &f->obj, &f->log};
    for (size_t i = 0; i < sizeof all / sizeof all[0]; i++) {
        ms_buf_free(all[i]);
    }
}

static bool bo_fail(MsBackendText *why, const char *what, const char *path) {
    MsBuf message = {0};
    ms_buf_printf(&message, "cannot %s %s", what, path);
    *why = ms_backend_take(&message);
    return false;
}

/* `opt` (release builds): the O3 pipeline over the IR file; `*input` becomes the bitcode it writes. */
static bool bo_optimize(const BoFiles *f, const MsObjectOptions *o, const char **input, MsBackendText *why) {
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
    argv[n++] = *input;
    argv[n++] = "-o";
    argv[n++] = f->bc.data;
    argv[n] = NULL;
    *input = f->bc.data;
    return bo_run("opt (LLVM optimizer)", argv, f->log.data, why);
}

/* Whether the IR holds a function the emitter marked `optnone`, which is how a size tier shows. */
static bool bo_has_optnone(const MsBackendText *ir) {
    static const char needle[] = " optnone";
    const size_t width = sizeof needle - 1;
    for (size_t i = 0; ir->ptr != NULL && i + width <= ir->len; i++) {
        if (memcmp(ir->ptr + i, needle, width) == 0) {
            return true;
        }
    }
    return false;
}

/* `llc` to assembly text. */
static bool bo_to_assembly(const BoFiles *f, const MsObjectOptions *o, const char *input, bool size_tiered,
                           MsBackendText *why) {
    const char *argv[15];
    size_t n = 0;
    argv[n++] = f->llc.data;
    /* A module with an `optnone` function (a size tier, #3928) goes through the fast code generator: llc's -O3
     * two-address and register-allocation passes are superlinear in one function's size even when it is optnone.
     * AArch64's -O0 GlobalISel Localizer pass is too (#5540), so the selection-DAG path is used. */
    argv[n++] = (o->backend.speed && !size_tiered ? "-O3" : "-O0");
    if (size_tiered) {
        argv[n++] = "-global-isel=0";
    }
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

/* Adds the fault tables to the assembly and writes it back as a module-asm IR file. */
static bool bo_add_tables(const BoFiles *f, const MsBackendText *meta, MsBackendText *why) {
    MsBuf assembly = {0}, wrapped_text = {0};
    MsBackendText with_tables = {0};
    if (!ms_build_read(f->plain.data, &assembly)) {
        return bo_fail(why, "read", f->plain.data);
    }
    const char *prefix =
#ifdef __APPLE__
        "_";
#else
        "";
#endif
    bool ok = ms_backend_tables(meta->ptr, meta->len, assembly.data, assembly.len, prefix, &with_tables, why);
    if (ok) {
        bo_asm_module(with_tables.ptr == NULL ? "" : with_tables.ptr, with_tables.len, &wrapped_text);
        if (!ms_build_write(f->wrapped.data, wrapped_text.data, wrapped_text.len)) {
            ok = bo_fail(why, "write", f->wrapped.data);
        }
    }
    ms_backend_free(&with_tables);
    ms_buf_free(&assembly);
    ms_buf_free(&wrapped_text);
    return ok;
}

/* `llc` assembles the wrapped module to an object; `object` takes its bytes. */
static bool bo_assemble(const BoFiles *f, MsBackendText *object, MsBackendText *why) {
    const char *argv[10] = {f->llc.data, "-filetype=obj", "-relocation-model=pic", f->triple.data, f->wrapped.data,
                            "-o",        f->obj.data,     NULL};
    if (!bo_run("llc (assembler)", argv, f->log.data, why)) {
        return false;
    }
    MsBuf bytes = {0};
    const bool ok = ms_build_read(f->obj.data, &bytes);
    if (ok) {
        *object = ms_backend_take(&bytes);
    } else {
        (void)bo_fail(why, "read", f->obj.data);
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
    bo_files_init(&f, dir, o->tools, triple_name);
    bool ok = ms_build_write(f.ll.data, ir->ptr, ir->len) || bo_fail(why, "write", f.ll.data);
    if (ok && o->keep_ll != NULL) {
        (void)ms_build_write(o->keep_ll, ir->ptr, ir->len);
    }
    const char *input = f.ll.data;
    ok = ok && (!o->backend.speed || bo_optimize(&f, o, &input, why));
    ok = ok && bo_to_assembly(&f, o, input, bo_has_optnone(ir), why) && bo_add_tables(&f, meta, why) && bo_assemble(&f, object, why);
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
    // NOLINTBEGIN(concurrency-mt-unsafe): read before any thread starts.
    const char *temp = getenv("TMPDIR");
    temp = temp != NULL && *temp != '\0' ? temp : getenv("TEMP");
    // NOLINTEND(concurrency-mt-unsafe)
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
