/* Linking with the pinned lld (ms/build_link.h): the steps every host shares. What differs per host is in
 * link_linux.c, link_macos.c and link_windows.c (link_internal.h). */
#include "ms/build_link.h"

#include <stdio.h>
#include <string.h>

#include "build/link_internal.h"
#include "ms/base.h"
#include "ms/build_tool.h"

bool ms_link_exists(const char *path) { return ms_build_is_file(path); }

void ms_link_push(BlJob *job, const char *arg) { MS_VEC_PUSH(job->argv, const char *, arg); }

/* The first undefined symbol the linker names that is not the runtime's (`msrt_`, `msstd_`) is an `extern fn` nobody
 * linked: the advice names it. */
void ms_link_foreign_advice(const MsBuf *detail, MsBuf *out) {
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
        const bool runtime = (n >= 5 && memcmp(name, "msrt_", 5) == 0) || (n >= 6 && memcmp(name, "msstd_", 6) == 0);
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
}

bool ms_build_link(const char *object, const char *const *inputs, size_t ninputs, const char *out, const MsLinkOptions *options,
                   MsBackendText *why) {
    BlJob job = {.options = options, .object = object, .inputs = inputs, .ninputs = ninputs, .out = out};
    MsBuf reason = {0};
    bool ok = ms_link_prepare(&job, &reason);
    if (ok) {
        ms_link_push(&job, NULL);
        MsBuf detail = {0};
        ok = ms_build_run("the bundled linker", (const char *const *)ms_buf_items(&job.argv), &detail);
        if (!ok) {
            ms_buf_puts(&reason, "linking failed; the linker output follows. ");
            ms_link_advice(&detail, options->musl, &reason);
            ms_buf_printf(&reason, ":\n%.*s", (int)detail.len, detail.data == NULL ? "" : detail.data);
        }
        ms_buf_free(&detail);
        ok = ms_link_finish(&job, ok, &reason) && ok;
    } else {
        (void)ms_link_finish(&job, false, &reason);
    }
    ms_buf_free(&job.argv);
    ms_arena_free(&job.arena);
    if (!ok) {
        *why = ms_backend_take(&reason);
        return false;
    }
    ms_buf_free(&reason);
    return true;
}
