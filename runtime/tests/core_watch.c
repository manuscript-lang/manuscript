/* Unit test of the watcher (runtime/core/watch.c): a busy isolate that does not turn is held up, a resting one and one
 * that turns are not, and the watcher sleeps when every isolate rests and wakes when one leaves its rest. */
#define _DEFAULT_SOURCE 1
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "../core/isolate.h"
#include "../core/watch.h"
#include "ms_rt/sys.h"

static void expect(bool condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "core_watch: failed: %s\n", what);
        exit(1);
    }
}

static void no_wake(void *argument) { (void)argument; }

static _Atomic unsigned calls;
static _Atomic bool held_up_seen;
static uint32_t watched;

static bool hook(MsWatchLook look, uint64_t resting) {
    atomic_fetch_add(&calls, 1);
    if (ms_watch_held_up(look, resting, watched)) {
        atomic_store(&held_up_seen, true);
    }
    return false;
}

static void wait_until(bool (*done)(void), const char *what) {
    for (int i = 0; i < 5000; i++) {
        if (done()) {
            return;
        }
        usleep(1000);
    }
    expect(false, what);
}

static bool was_held_up(void) { return atomic_load(&held_up_seen); }
static bool called_more(void) { return atomic_load(&calls) >= 3; }

static unsigned mark;
static bool calls_grew(void) { return atomic_load(&calls) > mark; }

int main(void) {
    watched = ms_isolate_register(no_wake, NULL);
    expect(watched != MS_NO_ISOLATE, "register");
    expect(ms_watch_add_hook(hook), "add hook");
    expect(ms_watch_add_hook(hook), "add the same hook again");

    /* Busy and never turning: held up within a few looks. */
    wait_until(was_held_up, "a busy isolate that does not turn is held up");

    /* Turning at each look keeps it from being held up. */
    atomic_store(&held_up_seen, false);
    const unsigned before = atomic_load(&calls);
    while (atomic_load(&calls) < before + 20) {
        ms_watch_turn();
        usleep(50);
    }
    expect(!atomic_load(&held_up_seen), "an isolate that turns is not held up");

    /* Resting: never held up, and the watcher goes to sleep after its quiet looks. */
    expect(ms_isolate_idle_enter(), "idle enter");
    wait_until(called_more, "the hook runs while the watcher is awake");
    usleep(120000);
    mark = atomic_load(&calls);
    usleep(30000);
    expect(atomic_load(&calls) == mark, "the watcher sleeps when every isolate rests");
    expect(!atomic_load(&held_up_seen), "a resting isolate is not held up");

    /* Leaving the rest wakes it. */
    ms_isolate_idle_leave();
    wait_until(calls_grew, "leaving the rest wakes the watcher");

    ms_watch_stop();
    ms_isolate_unregister(watched, NULL);
    puts("core_watch: ok");
    return 0;
}
