/* Stop requests and the grace timer: a signal reaches the callback on the stop thread, the grace timer fires once
 * armed and is restarted by arming again, and the thread ends cleanly. */
#define _POSIX_C_SOURCE 200809L

#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>

#ifndef _WIN32
#include <unistd.h>
#endif

#include "../io/stop.h"
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

static void deliver(int signal_number) {
#ifdef _WIN32
    expect(raise(signal_number) == 0, "raise");
#else
    expect(kill(getpid(), signal_number) == 0, "kill");
#endif
}

int main(void) {
    expect(ms_io_stop_start(on_stop, on_expired), "start");
    expect(!ms_io_stop_start(on_stop, on_expired), "a second start is refused");

    deliver(SIGTERM);
    expect(wait_for(&requests, 1), "a terminate request arrives");
    expect(atomic_load(&last_request) == MS_STOP_TERMINATE, "terminate is reported as terminate");

    deliver(SIGINT);
    expect(wait_for(&requests, 2), "an interrupt request arrives");
    expect(atomic_load(&last_request) == MS_STOP_INTERRUPT, "interrupt is reported as interrupt");

    ms_io_stop_arm(3600);
    ms_io_stop_arm(1); /* arming again restarts the timer */
    expect(wait_for(&expiries, 1), "the grace timer fires");
    expect(atomic_load(&expiries) == 1, "it fires once");

    ms_io_stop_end();
    ms_io_stop_end(); /* ending twice is harmless */
    puts("io_stop: ok");
    return 0;
}
