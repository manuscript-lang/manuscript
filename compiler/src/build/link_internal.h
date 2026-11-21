/* What each host adds to the link (build/link.c): its lld arguments and its steps before and after the link. */
#ifndef MS_BUILD_LINK_INTERNAL_H
#define MS_BUILD_LINK_INTERNAL_H

#include <stdbool.h>
#include <stddef.h>

#include "ms/base.h"
#include "ms/build_link.h"

#define BL_PATH 4096

typedef struct BlJob {
    const MsLinkOptions *options;
    const char *object;
    const char *const *inputs;
    size_t ninputs;
    const char *out;
    MsArena arena; /* the strings the arguments point at */
    MsBuf argv;    /* const char *: the lld command line, NULL-terminated once prepared */
    char *scratch; /* a directory made for the link, removed afterwards; NULL if none */
} BlJob;

/* Appends one argument (not copied). */
void ms_link_push(BlJob *job, const char *arg);
/* Whether `path` is a regular file. */
bool ms_link_exists(const char *path);

/* The host's part of the command line, after `lld`: fills `job->argv`. False with `why` set when something it needs
 * (the glibc stubs, the SDK stubs) cannot be made. */
bool ms_link_prepare(BlJob *job, MsBuf *why);
/* After the link attempt (`linked` says whether it succeeded): removes `scratch` and does the host's last steps (the
 * debug companion on macOS, the `.exe` name on Windows). False with `why` set when one of them fails. */
bool ms_link_finish(BlJob *job, bool linked, MsBuf *why);
/* The advice for a symbol the runtime does not define: names it (link.c). */
void ms_link_foreign_advice(const MsBuf *detail, MsBuf *out);
/* What a missing symbol in the linker output usually means on this host, appended to `out`. */
void ms_link_advice(const MsBuf *detail, bool musl, MsBuf *out);

#endif
