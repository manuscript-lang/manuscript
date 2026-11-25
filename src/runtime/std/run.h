/* runtime/std/run.h: what `run` collects from a child (run.c): the loop writes its input, reads both outputs up to the
 * limit, and ends the command when the child has exited and its pipes are closed, the deadline passes, the limit is
 * crossed, or the output stays open a second after the exit. */
#ifndef MS_RUNTIME_STD_RUN_H
#define MS_RUNTIME_STD_RUN_H

#include "base/bytes.h"
#include "runtime/std/child.h"

/* A command's captured result: the exit code (-1 when a signal ended the child), the streams and the peak resident set
 * size in bytes (0 when unknown). */
typedef struct MsCommandOut {
  int64_t exit_code;
  MsBytes out;
  MsBytes err;
  int64_t max_resident_bytes;
} MsCommandOut;

void ms_run_free(MsRun *run); /* NULL is allowed */
/* Ends what is finished after an exit or a closed pipe (loop thread). */
void ms_run_progress(MsChild *child);

/* ms-sig: msstd_process_command_run(program: *const StrVal, arguments: *const VecVal, input: *const VecVal, has_max: HasRaw, max: i64, has_timeout: HasRaw, timeout_ns: i64, has_cwd: HasRaw, cwd: *const StrVal, env_names: *const VecVal, env_values: *const VecVal, out: *mut CommandOut, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_command_run(const MsString *program, const MsList *arguments, const MsList *input, uint8_t has_max,
                                  int64_t max, uint8_t has_timeout, int64_t timeout_ns, uint8_t has_cwd,
                                  const MsString *cwd, const MsList *env_names, const MsList *env_values,
                                  MsCommandOut *out, MsString *err);

#endif
