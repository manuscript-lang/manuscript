/* cli/pipeline.h: a checked program to an executable: LLVM IR from the back end, an object from `opt` and `llc`,
 * then the linker. The commands that build, run and test call this after they have checked the program. */
#ifndef MS_CLI_PIPELINE_H
#define MS_CLI_PIPELINE_H

#include "base/strbuild.h"
#include "cli/backend.h"
#include "compiler/check/program.h"

typedef enum MsBuildType { MS_BUILD_DEBUG, MS_BUILD_RELEASE, MS_BUILD_MINSIZEREL } MsBuildType;

typedef struct MsLinkRequest {
  MsCheckProgram *program; /* checked, without diagnostics */
  uint32_t entry;          /* the module declaring `main` */
  MsBuildType build_type;
  MsSpan output;           /* the executable to write */
  const MsSpan *link;      /* extra files to link after the runtime */
  size_t link_count;
  bool static_libc;        /* static musl instead of the glibc 2.28 stand-ins */
  bool tests;              /* the entry is the test runner over the program's `test` blocks, not `main` */
  bool bench;              /* with `tests`: the runner over the `bench` blocks instead */
  bool count_ops;          /* count executed MIR operations (`MS_COUNT_OPS=1` asks for it too) */
} MsLinkRequest;

/* Builds the executable. On failure returns false and `error` (valid until the next call) says what failed.
 *
 * The tools come from the environment: `MS_OPT`, `MS_LLC` and `MS_LLD` name the executables (default `opt`, `llc`,
 * `lld`, found on PATH); `MS_FILES` is the directory of startup files and the glibc export table; `MS_RUNTIME` lists
 * the runtime archives, separated by `:` (`;` on Windows). Without `MS_FILES` and `MS_RUNTIME` the build's own
 * `files` directory next to `ms` and its runtime archives are used (cmake/MsRuntimePackage.cmake). */
bool ms_pipeline_link(const MsLinkRequest *request, MsSpan *error);

/* The back-end options `ms_pipeline_link` uses for `request` (before it splits the program into modules), so a
 * tool that prints the IR shows what a build would hand to `opt`. */
BackendOptions ms_pipeline_backend_options(const MsLinkRequest *request);

/* The name of the executable `run` and `test` build inside their temporary folder: Windows will not start a program
 * whose name lacks `.exe`. */
#ifdef _WIN32
#define MS_TEMP_PROGRAM "%S/program.exe"
#else
#define MS_TEMP_PROGRAM "%S/program"
#endif

#endif
