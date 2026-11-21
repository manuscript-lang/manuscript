/* MIR text to an object file (ms/build_object.h): the C back end writes IR, `opt` and `llc` compile it, and the
 * fault tables join the assembly before the last `llc` assembles it. Every step runs in a private directory that
 * is removed on the way out. */
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
    MsBuf triple = {0}, opt = {0}, llc = {0}, ll = {0}, bc = {0}, plain = {0}, wrapped = {0}, obj = {0}, log = {0};
    ms_buf_printf(&triple, "-mtriple=%s", triple_name);
    ms_buf_putc(&triple, 0);
    ms_buf_printf(&opt, "%s/opt", o->tools);
    ms_buf_putc(&opt, 0);
    ms_buf_printf(&llc, "%s/llc", o->tools);
    ms_buf_putc(&llc, 0);
    bo_path(&ll, dir, "program.ll");
    bo_path(&bc, dir, "program.bc");
    bo_path(&plain, dir, "program.plain.s");
    bo_path(&wrapped, dir, "program.asm.ll");
    bo_path(&obj, dir, "program.o");
    bo_path(&log, dir, "tool.log");
    bool ok = ms_build_write(ll.data, ir->ptr, ir->len);
    if (!ok) {
        MsBuf message = {0};
        ms_buf_printf(&message, "cannot write %s", ll.data);
        *why = ms_backend_take(&message);
    }
    if (ok && o->keep_ll != NULL) {
        (void)ms_build_write(o->keep_ll, ir->ptr, ir->len);
    }
    const char *input = ll.data;
    if (ok && o->backend.speed) {
        const char *argv[10];
        size_t n = 0;
        argv[n++] = opt.data;
        if (!o->vectorize) {
            argv[n++] = "-vectorize-loops=false";
            argv[n++] = "-vectorize-slp=false";
        }
        if (o->llvm_verify) {
            argv[n++] = "-verify-each";
        }
        argv[n++] = triple.data;
        argv[n++] = "-passes=default<O3>";
        argv[n++] = input;
        argv[n++] = "-o";
        argv[n++] = bc.data;
        argv[n] = NULL;
        ok = bo_run("opt (LLVM optimizer)", argv, log.data, why);
        input = bc.data;
    }
    if (ok) {
        const char *argv[14];
        size_t n = 0;
        argv[n++] = llc.data;
        argv[n++] = (o->backend.speed ? "-O3" : "-O0");
        argv[n++] = "-filetype=asm";
        argv[n++] = "-relocation-model=pic";
        argv[n++] = triple.data;
#if defined(__x86_64__)
        argv[n++] = "-align-loops=32";
        argv[n++] = "-mcpu=x86-64";
#endif
        argv[n++] = input;
        argv[n++] = "-o";
        argv[n++] = plain.data;
        argv[n] = NULL;
        ok = bo_run("llc (LLVM code generator)", argv, log.data, why);
    }
    MsBuf assembly = {0}, wrapped_text = {0};
    MsBackendText with_tables = {0};
    if (ok && !ms_build_read(plain.data, &assembly)) {
        MsBuf message = {0};
        ms_buf_printf(&message, "cannot read %s", plain.data);
        *why = ms_backend_take(&message);
        ok = false;
    }
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
        ok = ms_build_write(wrapped.data, wrapped_text.data, wrapped_text.len);
        if (!ok) {
            MsBuf message = {0};
            ms_buf_printf(&message, "cannot write %s", wrapped.data);
            *why = ms_backend_take(&message);
        }
    }
    if (ok) {
        const char *argv[10] = {llc.data, "-filetype=obj", "-relocation-model=pic", triple.data, wrapped.data,
                          "-o", obj.data, NULL};
        ok = bo_run("llc (assembler)", argv, log.data, why);
    }
    if (ok) {
        MsBuf bytes = {0};
        ok = ms_build_read(obj.data, &bytes);
        if (ok) {
            *object = ms_backend_take(&bytes);
        } else {
            MsBuf message = {0};
            ms_buf_printf(&message, "cannot read %s", obj.data);
            *why = ms_backend_take(&message);
        }
        ms_buf_free(&bytes);
    }
    const char *const made[] = {ll.data, bc.data, plain.data, wrapped.data, obj.data, log.data};
    for (size_t i = 0; i < sizeof made / sizeof made[0]; i++) {
        ms_build_unlink(made[i]);
    }
    ms_backend_free(&with_tables);
    ms_buf_free(&assembly);
    ms_buf_free(&wrapped_text);
    ms_buf_free(&triple);
    ms_buf_free(&opt);
    ms_buf_free(&llc);
    ms_buf_free(&ll);
    ms_buf_free(&bc);
    ms_buf_free(&plain);
    ms_buf_free(&wrapped);
    ms_buf_free(&obj);
    ms_buf_free(&log);
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
