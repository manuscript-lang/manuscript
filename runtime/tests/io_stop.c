/* Stop requests and the grace timer: a signal reaches the callback on the stop thread, the grace timer fires once
 * armed and is restarted by arming again, and the thread ends cleanly. */
#define _POSIX_C_SOURCE 200809L

#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef _WIN32
#include <unistd.h>
#endif

#include "../io/stop.h"
#include "support/child.h"
#include <uv.h>

static void expect(bool condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "io_stop: failed: %s\n", what);
        exit(1);
    }
}

static _Atomic int last_request;
static _Atomic int requests;
static _Atomic int expiries;

static void on_stop(int signal_number) {
    atomic_store(&last_request, signal_number);
    atomic_fetch_add(&requests, 1);
}

static void on_expired(void) { atomic_fetch_add(&expiries, 1); }

/* Waits up to about five seconds for `counter` to reach `want`. */
static bool wait_for(_Atomic int *counter, int want) {
    for (int waited = 0; waited < 5000; waited++) {
        if (atomic_load(counter) >= want) {
            return true;
        }
        uv_sleep(1);
    }
    return false;
}

/* The stop thread's work: an interrupt reaches the callback, the grace timer fires once armed, the thread ends. */
static void watch_for_interrupt(void) {
    expect(ms_io_stop_start(on_stop, on_expired), "start");
    expect(!ms_io_stop_start(on_stop, on_expired), "a second start is refused");
}

static void finish(void) {
    ms_io_stop_arm(3600);
    ms_io_stop_arm(1); /* arming again restarts the timer */
    expect(wait_for(&expiries, 1), "the grace timer fires");
    expect(atomic_load(&expiries) == 1, "it fires once");

    ms_io_stop_end();
    ms_io_stop_end(); /* ending twice is harmless */
}

#ifdef _WIN32
/* Console events reach a program only from the console: Ctrl-Break sent to a child in its own process group. The
 * child waits for it (its own mode), the parent sends it and reads how the child ended. A terminate request is a
 * console close, which no process can send to another; the mapping is checked directly. */
static const char *const ready_name = "MS_IO_STOP_READY";

static int run_child(void) {
    watch_for_interrupt();
    char name[1024];
    size_t size = sizeof name;
    expect(uv_os_getenv(ready_name, name, &size) == 0, "the ready file is named");
    FILE *marker = fopen(name, "wb");
    expect(marker != NULL, "the ready file is created");
    (void)fclose(marker);
    expect(wait_for(&requests, 1), "an interrupt request arrives");
    expect(atomic_load(&last_request) == MS_STOP_INTERRUPT, "Ctrl-Break is reported as interrupt");
    finish();
    return 0;
}

static int run_parent(void) {
    char self[1024];
    size_t self_size = sizeof self;
    expect(uv_exepath(self, &self_size) == 0, "exepath");
    char directory[512];
    size_t directory_size = sizeof directory;
    expect(uv_os_tmpdir(directory, &directory_size) == 0, "tmpdir");
    char ready[640];
    snprintf(ready, sizeof ready, "%s/ms-io-stop-%d.ready", directory, (int)uv_os_getpid());
    (void)remove(ready);
    expect(uv_os_setenv(ready_name, ready) == 0, "setenv");
    char *const argv[] = {self, (char *)"child", NULL};
    MsTestChild *child = ms_test_child_start(self, argv);
    expect(child != NULL, "start the child");
    for (int waited = 0; waited < 10000; waited++) {
        FILE *marker = fopen(ready, "rb");
        if (marker != NULL) {
            (void)fclose(marker);
            break;
        }
        uv_sleep(1);
    }
    expect(ms_test_child_interrupt(child), "send Ctrl-Break");
    expect(ms_test_child_wait(child, 30) == 0, "the child saw the interrupt and finished");
    (void)remove(ready);
    return 0;
}
#else
static void deliver(int signal_number) { expect(kill(getpid(), signal_number) == 0, "kill"); }

static int run_parent(void) {
    watch_for_interrupt();
    deliver(SIGTERM);
    expect(wait_for(&requests, 1), "a terminate request arrives");
    expect(atomic_load(&last_request) == MS_STOP_TERMINATE, "terminate is reported as terminate");

    deliver(SIGINT);
    expect(wait_for(&requests, 2), "an interrupt request arrives");
    expect(atomic_load(&last_request) == MS_STOP_INTERRUPT, "interrupt is reported as interrupt");
    finish();
    return 0;
}
#endif

int main(int argc, char **argv) {
    expect(ms_io_stop_request_of(SIGINT) == MS_STOP_INTERRUPT, "SIGINT is an interrupt");
    expect(ms_io_stop_request_of(SIGTERM) == MS_STOP_TERMINATE, "SIGTERM is a terminate request");
#ifdef _WIN32
    expect(ms_io_stop_request_of(SIGBREAK) == MS_STOP_INTERRUPT, "Ctrl-Break is an interrupt");
    expect(ms_io_stop_request_of(SIGHUP) == MS_STOP_TERMINATE, "a console close is a terminate request");
    if (argc == 2 && strcmp(argv[1], "child") == 0) {
        return run_child();
    }
#else
    (void)argc;
    (void)argv;
#endif
    const int status = run_parent();
    if (status == 0) {
        puts("io_stop: ok");
    }
    return status;
}
