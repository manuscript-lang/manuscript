/* Unit test of the pure data structures of runtime/core: the timer heap, the unstarted-work queue, the frame tables and the record encoder. */
#include <stdio.h>

#include "abi/layout.h"
#include "runtime/core/frames.h"
#include "runtime/core/queue.h"
#include "runtime/core/record.h"
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

static bool never(uintptr_t pc, const void *context) {
  (void)pc;
  (void)context;
  return false;
}

/* Two functions given out of address order, as a linker may leave them; a line range and a name blob. */
static void test_frames(void) {
  static const uint8_t strings[] = "\0a.ms\0first\0second";
  const MsFuncEntry funcs[] = {{.address = 0x2000, .size = 0x100, .name_offset = 12, .file_offset = 1, .line = 20},
                               {.address = 0x1000, .size = 0x100, .name_offset = 6, .file_offset = 1, .line = 10}};
  const MsLineEntry lines[] = {{.pc = 0x2000, .line = 21, .file_offset = UINT32_MAX},
                               {.pc = 0x1000, .line = 11, .file_offset = UINT32_MAX}};
  const MsTables tables = {.abi_version = 2,
                           .funcs = funcs,
                           .func_count = 2,
                           .lines = lines,
                           .line_count = 2,
                           .strings = strings,
                           .strings_len = sizeof strings};
  ms_frames_install(&tables);
  CHECK(ms_frames_tables() != &tables); /* out of order: a sorted copy */
  const uintptr_t addresses[] = {0x2010, 0x1010, 0x1010, 0x9000};
  MsFrameList list = {0};
  ms_frames_describe(addresses, 4, &list);
  CHECK(list.count == 2 && list.frames[0].line == 21 && list.frames[1].line == 11);
  CHECK(list.frames[0].function[0] == 's' && list.frames[1].repeated == 1);
  CHECK(ms_frames_find_function(ms_frames_tables(), 0x1000) == NULL); /* the call lies before the function */
  CHECK(ms_frames_scan_record(0, 0, 0, 0, never, never, NULL) == 0);
  ms_frames_release();
  CHECK(ms_frames_tables() == NULL);
}

static void test_record(void) {
  const MsFaultRecord record = {.pid = 7, .kind = MS_FAULT_KIND_DEADLOCK, .message = ms_span_of_text("boom")};
  uint8_t out[128];
  const size_t needed = ms_fault_record_encode(&record, NULL, 0);
  CHECK(needed == 4 + 1 + 4 + 1 + 1 + 4 + 4 + 4 + 4);
  CHECK(ms_fault_record_encode(&record, out, sizeof out) == needed);
  CHECK(out[0] == 'M' && out[4] == 1 && out[5] == 7 && out[9] == MS_FAULT_KIND_DEADLOCK);
}

int main(void) {
  test_timers();
  test_queue();
  test_frames();
  test_record();
  return failures == 0 ? 0 : 1;
}
