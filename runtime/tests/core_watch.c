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
static bool epoch_moved(void) { return ms_watch_epoch() >= 40; }
static bool watcher_asleep(void) { return ms_watch_asleep(); }

static unsigned mark;
static bool calls_grew(void) { return atomic_load(&calls) > mark; }

int main(void) {
    watched = ms_isolate_register(no_wake, NULL);
    expect(watched != MS_NO_ISOLATE, "register");
    expect(ms_watch_add_hook(hook), "add hook");
    expect(ms_watch_add_hook(hook), "add the same hook again");

    /* Busy and never turning: held up within a few looks. */
    wait_until(was_held_up, "a busy isolate that does not turn is held up");

    /* The held-up test on a frozen clock: stop the watcher so the epoch no longer moves, then look at crafted looks. */
    wait_until(epoch_moved, "the clock advances");
    ms_watch_stop();
    const uint64_t now = ms_watch_epoch();
    ms_watch_turn(); /* seen = now */
    expect(!ms_watch_held_up((MsWatchLook){.now = now + 20, .last = now}, 0, watched),
           "an isolate that turned at the last look is not held up");
    expect(ms_watch_held_up((MsWatchLook){.now = now + 40, .last = now + 20}, 0, watched),
           "an isolate that has not turned for a whole interval is held up");
    expect(!ms_watch_held_up((MsWatchLook){.now = now + 40, .last = now + 20}, UINT64_C(1) << watched, watched),
           "a resting isolate is never held up");

    /* Restart; resting isolates let the watcher sleep, and leaving the rest wakes it. */
    expect(ms_watch_add_hook(hook), "restart");
    expect(ms_isolate_idle_enter(), "idle enter");
    wait_until(watcher_asleep, "the watcher sleeps when every isolate rests");

    /* Leaving the rest wakes it. */
    mark = atomic_load(&calls);
    ms_isolate_idle_leave();
    wait_until(calls_grew, "leaving the rest wakes the watcher");
    expect(!ms_watch_asleep() || atomic_load(&calls) > mark, "the watcher is awake");

    ms_watch_stop();
    ms_isolate_unregister(watched, NULL);
    puts("core_watch: ok");
    return 0;
}
