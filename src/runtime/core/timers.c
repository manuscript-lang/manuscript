/* A binary min-heap of timers. See timers.h. */
#include "timers.h"

#include "array.h"

static bool earlier(MsTimer a, MsTimer b) {
    return a.deadline < b.deadline || (a.deadline == b.deadline && a.handle < b.handle);
}

static void sift_up(MsTimers *timers, size_t index) {
    const MsTimer moving = timers->items[index];
    while (index > 0) {
        const size_t parent = (index - 1) / 2;
        if (!earlier(moving, timers->items[parent])) {
            break;
        }
        timers->items[index] = timers->items[parent];
        index = parent;
    }
    timers->items[index] = moving;
}

static void sift_down(MsTimers *timers, size_t index) {
    const MsTimer moving = timers->items[index];
    for (;;) {
        size_t child = 2 * index + 1;
        if (child >= timers->length) {
            break;
        }
        if (child + 1 < timers->length && earlier(timers->items[child + 1], timers->items[child])) {
            child++;
        }
        if (!earlier(timers->items[child], moving)) {
            break;
        }
        timers->items[index] = timers->items[child];
        index = child;
    }
    timers->items[index] = moving;
}

void ms_timers_push(MsTimers *timers, MsTimer timer) {
    void *items = timers->items;
    if (!ms_array_reserve(&items, &timers->capacity, timers->length + 1, sizeof *timers->items)) {
        return;
    }
    timers->items = items;
    timers->items[timers->length] = timer;
    sift_up(timers, timers->length++);
}

bool ms_timers_peek(const MsTimers *timers, MsTimer *out) {
    if (timers->length == 0) {
        return false;
    }
    *out = timers->items[0];
    return true;
}

void ms_timers_pop(MsTimers *timers) {
    if (timers->length == 0) {
        return;
    }
    timers->items[0] = timers->items[--timers->length];
    if (timers->length > 0) {
        sift_down(timers, 0);
    }
}

void ms_timers_retain(MsTimers *timers, bool (*keep)(void *context, MsTimer timer), void *context) {
    size_t kept = 0;
    for (size_t i = 0; i < timers->length; i++) {
        if (keep(context, timers->items[i])) {
            timers->items[kept++] = timers->items[i];
        }
    }
    timers->length = kept;
    for (size_t i = kept / 2; i > 0; i--) {
        sift_down(timers, i - 1);
    }
}

void ms_timers_free(MsTimers *timers) {
    msrt_free(timers->items);
    *timers = (MsTimers){0};
}
