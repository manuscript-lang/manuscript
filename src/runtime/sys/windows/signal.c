/* Signal observers on Windows: console control events delivered as the signals Go maps them to. Ctrl-C and
 * Ctrl-Break are SIGINT (2); closing the console, logoff and shutdown are SIGTERM (15). One handler (installed with
 * the first observer, removed with the last) counts each event for every observer of that signal, then returns FALSE
 * so the handler installed before (the runtime's cancellation) still runs. */
#include <windows.h>

#include <stdatomic.h>
#include <stdlib.h>

#include "ms_rt/sys_signal.h"

enum { SLOTS = 32, SIGNAL_INT = 2, SIGNAL_KILL = 9, SIGNAL_TERM = 15, EVENT_KINDS = 2 };

struct MsSysSignals {
    int slot;
    uint64_t mask;
    atomic_bool stopped;
    MsSysSignalNotify notify;
    void *context;
};

static atomic_uint_least64_t slot_mask[SLOTS]; /* the signals an observer watches; 0 when the slot is free */
static atomic_uint pending[SLOTS][EVENT_KINDS]; /* per slot, SIGINT then SIGTERM events waiting */
static MsSysSignals *observer_of[SLOTS]; /* the observer of a slot, for its notify */
static atomic_int observers;

static int kind_index(int signal) { return signal == SIGNAL_INT ? 0 : 1; }

static void wake(int slot) {
    MsSysSignals *observer = observer_of[slot];
    if (observer != NULL) {
        observer->notify(observer->context);
    }
}

/* Counts `signal` for every observer of it. */
static void deliver(int signal) {
    const uint64_t bit = UINT64_C(1) << (signal - 1);
    for (int slot = 0; slot < SLOTS; slot++) {
        if ((atomic_load(&slot_mask[slot]) & bit) != 0) {
            atomic_fetch_add(&pending[slot][kind_index(signal)], 1);
            wake(slot);
        }
    }
}

static BOOL WINAPI on_event(DWORD kind) {
    switch (kind) {
    case CTRL_C_EVENT:
    case CTRL_BREAK_EVENT:
        deliver(SIGNAL_INT);
        return FALSE;
    case CTRL_CLOSE_EVENT:
    case CTRL_LOGOFF_EVENT:
    case CTRL_SHUTDOWN_EVENT:
        deliver(SIGNAL_TERM);
        return FALSE;
    default:
        return FALSE;
    }
}

void ms_sys_signal_raise(int signal) { deliver(signal); }

bool ms_sys_signal_valid(int64_t signal) {
    return signal >= 1 && signal <= MS_SYS_SIGNAL_MAX && signal != SIGNAL_KILL;
}

MsSysError ms_sys_signals_open(uint64_t mask, size_t capacity, MsSysSignalNotify notify, void *context, MsSysSignals **out) {
    (void)capacity;
    int slot = -1;
    for (int i = 0; i < SLOTS && slot < 0; i++) {
        uint64_t free_slot = 0;
        if (atomic_compare_exchange_strong(&slot_mask[i], &free_slot, mask)) {
            slot = i;
        }
    }
    if (slot < 0) {
        return MS_SYS_SIGNALS_FULL;
    }
    MsSysSignals *observer = calloc(1, sizeof *observer);
    if (observer == NULL) {
        atomic_store(&slot_mask[slot], 0);
        return ERROR_NOT_ENOUGH_MEMORY;
    }
    for (int kind = 0; kind < EVENT_KINDS; kind++) {
        atomic_store(&pending[slot][kind], 0);
    }
    if (atomic_fetch_add(&observers, 1) == 0 && !SetConsoleCtrlHandler(on_event, TRUE)) {
        const DWORD error = GetLastError();
        atomic_fetch_sub(&observers, 1);
        atomic_store(&slot_mask[slot], 0);
        free(observer);
        return (MsSysError)error;
    }
    observer->slot = slot;
    observer->mask = mask;
    observer->notify = notify;
    observer->context = context;
    observer_of[slot] = observer;
    *out = observer;
    return 0;
}

/* Takes waiting events, SIGINT before SIGTERM. */
size_t ms_sys_signals_take(MsSysSignals *observer, uint8_t *out, size_t capacity) {
    static const uint8_t signals[EVENT_KINDS] = {SIGNAL_INT, SIGNAL_TERM};
    size_t count = 0;
    for (int kind = 0; kind < EVENT_KINDS; kind++) {
        if ((observer->mask & (UINT64_C(1) << (signals[kind] - 1))) == 0) {
            continue;
        }
        unsigned int waiting = atomic_load(&pending[observer->slot][kind]);
        while (count < capacity && waiting > 0) {
            if (atomic_compare_exchange_weak(&pending[observer->slot][kind], &waiting, waiting - 1)) {
                out[count++] = signals[kind];
                waiting = atomic_load(&pending[observer->slot][kind]);
            }
        }
    }
    return count;
}

int ms_sys_signals_fd(const MsSysSignals *observer) {
    (void)observer;
    return -1;
}

bool ms_sys_signals_pending(const MsSysSignals *observer) {
    for (int kind = 0; kind < EVENT_KINDS; kind++) {
        if (atomic_load(&pending[observer->slot][kind]) > 0) {
            return true;
        }
    }
    return false;
}

void ms_sys_signals_stop(MsSysSignals *observer) {
    if (atomic_exchange(&observer->stopped, true)) {
        return;
    }
    atomic_store(&slot_mask[observer->slot], 0);
    observer->notify(observer->context);
    if (atomic_fetch_sub(&observers, 1) == 1) {
        (void)SetConsoleCtrlHandler(on_event, FALSE);
    }
}

void ms_sys_signals_destroy(MsSysSignals *observer) {
    ms_sys_signals_stop(observer);
    free(observer);
}
