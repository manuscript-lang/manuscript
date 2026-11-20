/* The process entry: msrt_start runs main on the runtime thread and returns its status; the arguments and exit hooks
 * work; stop requests end a program with the status of the signal, in child processes because they end the process. */
#define _POSIX_C_SOURCE 200809L

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include "../core/task.h"
#include "../entry/entry.h"
#include "ms_rt/desc.h"
#include "ms_rt/string.h"


static void expect(int condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "entry_start: failed: %s\n", what);
        exit(1);
    }
}

/* What the std layer provides in a program. */

static int hooks_run;
static void count_hook(void) { hooks_run++; }

static const char *const arguments[] = {"program", "first", "second"};
static int observed_argument_count;
static int observed_argv_count;

static int64_t main_with_arguments(void) {
    MsVec list = {0};
    msrt_args(&list);
    observed_argument_count = (int)list.len;
    msrt_argv(&list);
    observed_argv_count = (int)list.len;
    return 7;
}

static int64_t main_sleeping(void) {
    (void)ms_task_sleep(30LL * 1000000000LL);
    return 0;
}

static int64_t main_out_of_range(void) { return 200; }

/* Runs msrt_start in a child and returns how it ended: the exit status, or 1000 + the signal. */
static int run_in_child(MsMainFn main_fn, int signal_after_start, int seconds_before_signal) {
    const pid_t child = fork();
    expect(child >= 0, "fork");
    if (child == 0) {
        exit(msrt_start(main_fn, NULL, 1, arguments));
    }
    if (signal_after_start != 0) {
        sleep((unsigned)seconds_before_signal);
        kill(child, signal_after_start);
    }
    int status = 0;
    expect(waitpid(child, &status, 0) == child, "waitpid");
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1000 + WTERMSIG(status);
}

int main(void) {
    msrt_process_on_exit(count_hook);
    const int status = msrt_start(main_with_arguments, NULL, 3, arguments);
    expect(status == 7, "main's status is msrt_start's result");
    expect(observed_argument_count == 2, "args() is argv without the program name");
    expect(observed_argv_count == 3, "argv() is the whole of argv");
    expect(hooks_run == 1, "the exit hook ran once");

    expect(run_in_child(main_out_of_range, 0, 0) == 134, "an exit code past 125 is a fault");
    expect(run_in_child(main_sleeping, SIGTERM, 1) == 143, "a terminate request ends a parked main with 143");
    expect(run_in_child(main_sleeping, SIGINT, 1) == 130, "an interrupt request ends it with 130");
    puts("entry_start: ok");
    return 0;
}
