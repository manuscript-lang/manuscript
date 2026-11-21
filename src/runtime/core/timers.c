/* A binary min-heap of timers. See timers.h. */
#include "runtime/core/timers.h"

static bool earlier(MsTimer a, MsTimer b) {
  return a.deadline < b.deadline || (a.deadline == b.deadline && a.handle < b.handle);
}

static void sift_up(MsTimerList *heap, size_t index) {
  MsTimer *const items = heap->ptr;
  const MsTimer moving = items[index];
  while (index > 0) {
    const size_t parent = (index - 1) / 2;
    if (!earlier(moving, items[parent])) {
      break;
    }
    items[index] = items[parent];
    index = parent;
  }
  items[index] = moving;
}

static void sift_down(MsTimerList *heap, size_t index) {
  MsTimer *const items = heap->ptr;
  const MsTimer moving = items[index];
  for (;;) {
    size_t child = 2 * index + 1;
    if (child >= heap->len) {
      break;
    }
    if (child + 1 < heap->len && earlier(items[child + 1], items[child])) {
      child++;
    }
    if (!earlier(items[child], moving)) {
      break;
    }
    items[index] = items[child];
    index = child;
  }
  items[index] = moving;
}

void ms_timers_push(MsTimers *timers, MsTimer timer) {
  ms_timer_list_push(&timers->heap, timer);
  sift_up(&timers->heap, timers->heap.len - 1);
}

bool ms_timers_peek(const MsTimers *timers, MsTimer *out) {
  return ms_timer_list_get(&timers->heap, 0, out);
}

void ms_timers_pop(MsTimers *timers) {
  MsTimerList *const heap = &timers->heap;
  MsTimer last;
  if (!ms_timer_list_pop(heap, &last) || heap->len == 0) {
    return;
  }
  heap->ptr[0] = last;
  sift_down(heap, 0);
}

void ms_timers_retain(MsTimers *timers, bool (*keep)(void *context, MsTimer timer), void *context) {
  MsTimerList *const heap = &timers->heap;
  size_t kept = 0;
  for (size_t i = 0; i < heap->len; i++) {
    if (keep(context, heap->ptr[i])) {
      heap->ptr[kept++] = heap->ptr[i];
    }
  }
  ms_timer_list_truncate(heap, kept);
  for (size_t i = kept / 2; i > 0; i--) {
    sift_down(heap, i - 1);
  }
}

void ms_timers_free(MsTimers *timers) { ms_timer_list_free(&timers->heap); }
