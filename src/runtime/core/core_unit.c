/* Unit test of the pure data structures of runtime/core: the timer heap and the unstarted-work queue. */
#include <stdio.h>

#include "abi/layout.h"
#include "runtime/core/queue.h"
#include "runtime/core/timers.h"

static int failures = 0;

#define CHECK(condition)                                                                                     \
  do {                                                                                                       \
    if (!(condition)) {                                                                                      \
      (void)fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #condition);                                  \
      failures++;                                                                                            \
    }                                                                                                        \
  } while (0)

static bool keep_even(void *context, MsTimer timer) {
  (void)context;
  return timer.handle % 2 == 0;
}

static void test_timers(void) {
  MsTimers timers = {0};
  MsTimer top;
  CHECK(!ms_timers_peek(&timers, &top));
  for (uint64_t i = 0; i < 100; i++) {
    ms_timers_push(&timers, (MsTimer){.deadline = (int64_t)((i * 37) % 101), .handle = i});
  }
  ms_timers_retain(&timers, keep_even, NULL);
  int64_t previous = -1;
  size_t count = 0;
  while (ms_timers_peek(&timers, &top)) {
    CHECK(top.deadline >= previous && top.handle % 2 == 0);
    previous = top.deadline;
    ms_timers_pop(&timers);
    count++;
  }
  CHECK(count == 50);
  ms_timers_pop(&timers);
  ms_timers_free(&timers);
}

static int dropped = 0;
static void drop(void *work) {
  (void)work;
  dropped++;
}

static void test_queue(void) {
  int a;
  int b;
  int c;
  uint64_t id = 0;
  void *work = NULL;
  CHECK(!ms_queue_push(0, 0, &a, 1));
  CHECK(!ms_queue_push(MS_MAX_ISOLATES, 1, &a, 1));
  CHECK(ms_queue_push(1, 1, &a, 10) && ms_queue_push(1, 2, &b, 20) && ms_queue_push(1, 3, &c, 30));
  CHECK(ms_queue_length(1) == 3 && ms_queue_oldest(1) == 10);
  CHECK(ms_queue_remove(1, 2) && !ms_queue_remove(1, 2));
  CHECK(!ms_queue_steal(1, 5, &id, &work));
  CHECK(ms_queue_steal(1, 10, &id, &work) && id == 1 && work == &a);
  CHECK(ms_queue_oldest(1) == 30 && ms_queue_length(1) == 1);
  for (uint64_t i = 10; i < 60; i++) { /* past the first capacity */
    CHECK(ms_queue_push(1, i, &a, 40));
  }
  ms_queue_release(1, drop);
  CHECK(dropped == 51 && ms_queue_length(1) == 0 && ms_queue_oldest(1) == INT64_MAX);
}

int main(void) {
  test_timers();
  test_queue();
  return failures == 0 ? 0 : 1;
}
