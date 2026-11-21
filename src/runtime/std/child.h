/* runtime/std/child.h: a child process on libuv, shared by `run` (run.c) and `spawn` (spawn.c).
 *
 * uv_spawn starts the child, and a loop of its own on a thread of its own reaps it, reads and writes its pipes and keeps
 * its deadlines. The loop thread never calls the runtime: it records state under the child's lock and posts the token
 * the waiting task parks on. Each child leads its own process group (UV_PROCESS_DETACHED: a new session on Unix) or job
 * object (Windows), so a kill reaches its whole tree. */
#ifndef MS_RUNTIME_STD_CHILD_H
#define MS_RUNTIME_STD_CHILD_H

#include <uv.h>

#include "base/desc.h"
#include "runtime/std/command.h"
#include "runtime/sys/process.h"

typedef struct MsRun MsRun;

enum {
  MS_STDIO_PIPE = 0,
  MS_STDIO_INHERIT = 1,
  MS_STDIO_NULL = 2,
  MS_STREAM_IN = 0,
  MS_STREAM_OUT = 1,
  MS_STREAM_ERR = 2,
  MS_STREAM_COUNT = 3,
};

typedef struct MsChild {
  MsObj header; /* first: the runtime drops the handle through it */
  uv_mutex_t lock;
  uv_loop_t loop;
  uv_process_t process;
  uv_timer_t sampler;
  uv_thread_t thread;
  MsSysGroup *group;
  MsRun *run;     /* NULL for a `spawn` */
  uint64_t token; /* the token a waiting task parks on (0: none); one per park, see ms_child_arm */
  int64_t pid;
  int64_t code; /* once exited */
  int64_t max_resident;
  int descriptors[MS_STREAM_COUNT]; /* a spawn's parent ends; -1 when none or taken */
  int64_t ids[MS_STREAM_COUNT];     /* the stream-table id once taken; -2 not yet */
  bool exited, finished, stopped, loop_ready, started; /* finished: the loop thread has ended */
} MsChild;

/* A new child with its loop; `run` (owned) is NULL for a spawn. */
MsChild *ms_child_new(MsRun *run);
/* Starts the process with the given stdio modes. On success the parent ends of its pipes are in `parent` (-1 for a
 * stream that is not piped) and the loop is ready but its thread not started. `parent_flags` are the libuv flags of the
 * parent end of each pipe. False with `fail` set. */
bool ms_child_spawn(MsChild *child, const MsCommand *command, const int64_t modes[MS_STREAM_COUNT], int parent_flags,
                    int parent[MS_STREAM_COUNT], MsFail *fail);
/* After a successful spawn (and the run's attach): the sampler and the loop thread. */
bool ms_child_start_loop(MsChild *child);
/* Ends the child (kills the group), joins the loop and frees everything. */
void ms_child_free(MsObj *object);

void ms_child_lock(MsChild *child);
void ms_child_unlock(MsChild *child);
/* Wakes the waiting task, if any (any thread). */
void ms_child_wake(MsChild *child);
/* A remote token counts as a pending wake-up only until its first post, so a task that parks again needs a new one: arm
 * before reading the state, park only while the state says to, then disarm. */
uint64_t ms_child_arm(MsChild *child);
void ms_child_disarm(MsChild *child, uint64_t token);

/* SIGTERM to the child's group unless `force`; a child that has exited is left alone, since its pid may be reused. */
void ms_child_signal(MsChild *child, bool force);
/* Kills what remains of the group, also after the leader has been reaped. */
void ms_child_kill_group(MsChild *child);
/* Waits for the loop thread to finish. The child must be exiting: callers kill it first. */
void ms_child_join(MsChild *child);
/* Closes a descriptor of the parent's pipe ends (-1 is ignored). */
void ms_child_close_descriptor(int fd);

/* Called on the loop thread after an exit or a closed pipe: ends what is finished, wakes the task. */
void ms_child_progress(MsChild *child);

#endif
