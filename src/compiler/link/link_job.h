/* compiler/link/link_job.h: what the host-specific parts of the link share (link.c, link_job.c). */
#ifndef MS_COMPILER_LINK_LINK_JOB_H
#define MS_COMPILER_LINK_LINK_JOB_H

#include "compiler/link/link.h"

MS_LIST_DEFINE(LinkArgList, link_arg_list, MsString)

/* One link in progress. Ownership: the job owns its arguments and the scratch directory name. */
typedef struct LinkJob {
  const LinkOptions *options; /* borrowed */
  const LinkRequest *request; /* borrowed */
  LinkArgList args;           /* owned: the lld command line */
  MsString scratch;           /* owned: a directory made for this link and removed afterwards; empty if none */
} LinkJob;

void link_job_push(LinkJob *job, MsSpan argument);
/* Pushes a C string literal. */
void link_job_push_text(LinkJob *job, const char *literal);
/* Pushes `directory/name`. */
void link_job_push_in(LinkJob *job, MsSpan directory, const char *name);

/* The host's part of the command line, after nothing: fills `job->args` starting with the lld path. False,
 * with `why` set, when something it needs (the glibc stubs, the SDK stubs) cannot be made. */
MS_NODISCARD bool link_host_prepare(LinkJob *job, MsStrBuild *why);
/* After the link attempt (`linked` says whether it worked): removes the scratch directory and does the host's
 * last steps. False, with `why` set, when one fails. */
MS_NODISCARD bool link_host_finish(LinkJob *job, bool linked, MsStrBuild *why);
/* What a missing symbol in the linker output usually means on this host. */
void link_host_advice(MsSpan detail, bool musl, MsStrBuild *out);
/* The advice for a symbol the runtime does not define: names it. */
void link_foreign_advice(MsSpan detail, MsStrBuild *out);

#endif
