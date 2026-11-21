/* The process entry: msrt_start runs main on the runtime thread and returns its status; the arguments and exit hooks
 * work; stop requests end a program with the status of the signal, in child processes (this executable again, in a
 * mode named by its arguments) because they end the process. Windows programs see an interrupt as Ctrl-Break; a
 * terminate request reaches them only as a console close, which no process can send to another, so only the
 * interrupt is sent there. */
#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <uv.h>

#include "../core/task.h"
#include "../entry/entry.h"
#include "ms_rt/desc.h"
#include "ms_rt/string.h"
#include "support/child.h"


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

/* A parked main reports it is running by creating the file MS_ENTRY_START_READY names, when the parent set it. */
static int64_t main_sleeping(void) {
    char name[1024];
    size_t size = sizeof name;
    if (uv_os_getenv("MS_ENTRY_START_READY", name, &size) == 0) {
        FILE *marker = fopen(name, "wb");
        if (marker != NULL) {
            (void)fclose(marker);
        }
    }
    (void)ms_task_sleep(30LL * 1000000000LL);
    return 0;
}

static int64_t main_out_of_range(void) { return 200; }

enum { MODE_OUT_OF_RANGE, MODE_SLEEPING, EXECUTABLE_BYTES = 1024, DIRECTORY_BYTES = 512, PATH_BYTES = 640, MODE_NAME_BYTES = 32, CHILD_SECONDS = 30 };

static const char *const mode_names[] = {"out_of_range", "sleeping"};

/* The file a sleeping child creates once its main runs, so the parent knows the stop request will find it parked. */
static void ready_path(char *path, size_t capacity) {
    char directory[DIRECTORY_BYTES];
    size_t size = sizeof directory;
    expect(uv_os_tmpdir(directory, &size) == 0, "tmpdir");
    snprintf(path, capacity, "%s/ms-entry-start-%d.ready", directory, (int)uv_os_getpid());
}

/* Runs this executable in `mode` and returns how it ended: the exit status, or 1000 + the signal. `request` is
 * 0 for none, 2 to interrupt, 15 to terminate, sent once the child reports it is running. */
static int run_in_child(const char *self, int mode, int request) {
    char ready[PATH_BYTES];
    ready_path(ready, sizeof ready);
    (void)remove(ready);
    if (mode == MODE_SLEEPING) {
        expect(uv_os_setenv("MS_ENTRY_START_READY", ready) == 0, "setenv");
    } else {
        (void)uv_os_unsetenv("MS_ENTRY_START_READY");
    }
    /* Writable copies: the spawn API takes a mutable argv. */
    char program[EXECUTABLE_BYTES];
    char word[] = "child";
    char mode_name[MODE_NAME_BYTES];
    expect(snprintf(program, sizeof program, "%s", self) < (int)sizeof program, "program path fits");
    expect(snprintf(mode_name, sizeof mode_name, "%s", mode_names[mode]) < (int)sizeof mode_name, "mode name fits");
    char *const argv[] = {program, word, mode_name, NULL};
    MsTestChild *child = ms_test_child_start(self, argv);
    expect(child != NULL, "start the child");
    if (request != 0) {
        for (int waited = 0; waited < 10000; waited++) {
            FILE *marker = fopen(ready, "rb");
            if (marker != NULL) {
                (void)fclose(marker);
                break;
            }
            uv_sleep(1);
        }
        expect(request == 2 ? ms_test_child_interrupt(child) : ms_test_child_terminate(child), "send the request");
    }
    const int status = ms_test_child_wait(child, CHILD_SECONDS);
    (void)remove(ready);
    return status;
}

int main(int argc, char **argv) {
    if (argc == 3 && strcmp(argv[1], "child") == 0) {
        const MsMainFn entry = strcmp(argv[2], mode_names[MODE_SLEEPING]) == 0 ? main_sleeping : main_out_of_range;
        return msrt_start(entry, NULL, 1, arguments);
    }
    char self[EXECUTABLE_BYTES];
    size_t self_size = sizeof self;
    expect(uv_exepath(self, &self_size) == 0, "exepath");

    msrt_process_on_exit(count_hook);
    const int status = msrt_start(main_with_arguments, NULL, 3, arguments);
    expect(status == 7, "main's status is msrt_start's result");
    expect(observed_argument_count == 2, "args() is argv without the program name");
    expect(observed_argv_count == 3, "argv() is the whole of argv");
    expect(hooks_run == 1, "the exit hook ran once");

    expect(run_in_child(self, MODE_OUT_OF_RANGE, 0) == 134, "an exit code past 125 is a fault");
    expect(run_in_child(self, MODE_SLEEPING, 2) == 130, "an interrupt request ends a parked main with 130");
#ifndef _WIN32
    expect(run_in_child(self, MODE_SLEEPING, 15) == 143, "a terminate request ends it with 143");
#endif
    puts("entry_start: ok");
    return 0;
}
