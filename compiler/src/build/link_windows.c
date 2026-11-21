/* The Windows link (ms/build_link.h): not in C yet. The executable links over the mingw-w64 CRT the Rust command
 * fetches (crates/ms-build/src/link/), so `ms build` hands the program to that command first (ms_build_host_ported in
 * object.c) and these steps never run; they refuse in case they are reached. */
#if defined(_WIN32)
#include "build/link_internal.h"

bool ms_link_prepare(BlJob *job, MsBuf *why) {
    (void)job;
    ms_buf_puts(why, "the C link step does not link for Windows yet; the Rust command does");
    return false;
}

bool ms_link_finish(BlJob *job, bool linked, MsBuf *why) {
    (void)job;
    (void)why;
    return !linked;
}

void ms_link_advice(const MsBuf *detail, bool musl, MsBuf *out) {
    (void)musl;
    ms_link_foreign_advice(detail, out);
}

#endif
