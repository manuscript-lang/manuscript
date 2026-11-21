/* The Windows link (ms/build_link.h): lld in its GNU flavor over mingw-w64's startup object and CRT, dropping unreachable
 * sections (`--gc-sections`, the `/opt:ref` of the MSVC linker) and keeping DWARF in the image. The import libraries
 * (`libkernel32.a`, ...) are the ones llvm-mingw generates from the DLL export lists. */
#include "build/link_internal.h"

#if defined(_WIN32)

#include <stdio.h>
#include <string.h>

#include "ms/base.h"
#include "ms/build_tool.h"

bool ms_link_prepare(BlJob *job, MsBuf *why) {
    (void)why;
    const MsLinkOptions *o = job->options;
#if defined(__aarch64__)
    const char *machine = "arm64pe";
#else
    const char *machine = "i386pep";
#endif
    const char *const head[] = {o->lld, "-flavor", "gnu", "-m", machine, "--gc-sections", "--subsystem", "console",
                                /* Identical inputs must link to identical bytes. */
                                "--no-insert-timestamp", "-o", job->out};
    for (size_t i = 0; i < sizeof head / sizeof head[0]; i++) {
        ms_link_push(job, head[i]);
    }
    if (o->strip) {
        ms_link_push(job, "--strip-all");
    }
    ms_link_push(job, ms_arena_fmt(&job->arena, "%s/crt2.o", o->files).ptr);
    ms_link_push(job, job->object);
    ms_link_push(job, "--start-group");
    for (size_t i = 0; i < job->ninputs; i++) {
        ms_link_push(job, job->inputs[i]);
    }
    static const char *const libraries[] = {"libmingw32.a", "libunwind.a", "libmoldname.a", "libmingwex.a", "libucrt.a", "libadvapi32.a",
                                            "libbcrypt.a", "libcrypt32.a", "libdbghelp.a", "libntdll.a", "libsecur32.a", "libshell32.a",
                                            "libuser32.a", "libuserenv.a", "libiphlpapi.a", "libpsapi.a", "libole32.a", "libws2_32.a",
                                            "libkernel32.a"};
    for (size_t i = 0; i < sizeof libraries / sizeof libraries[0]; i++) {
        ms_link_push(job, ms_arena_fmt(&job->arena, "%s/%s", o->files, libraries[i]).ptr);
    }
    ms_link_push(job, "--end-group");
    return true;
}

/* Windows linkers add `.exe` to an output name without it; the build keeps the name it chose. */
bool ms_link_finish(BlJob *job, bool linked, MsBuf *why) {
    (void)why;
    if (!linked || ms_link_exists(job->out)) {
        return true;
    }
    const char *slash = strrchr(job->out, '/');
    const char *back = strrchr(job->out, '\\');
    const char *base = slash != NULL && (back == NULL || slash > back) ? slash : back;
    if (strchr(base == NULL ? job->out : base, '.') != NULL) {
        return true;
    }
    const char *with_suffix = ms_arena_fmt(&job->arena, "%s.exe", job->out).ptr;
    if (ms_link_exists(with_suffix) && rename(with_suffix, job->out) != 0) {
        ms_buf_printf(why, "cannot place the executable %s", job->out);
        return false;
    }
    return true;
}

void ms_link_advice(const MsBuf *detail, bool musl, MsBuf *out) {
    (void)musl;
    ms_link_foreign_advice(detail, out);
}

#endif
