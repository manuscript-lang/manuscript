/* Unit test of the pure data structures of runtime/core: the timer heap, the unstarted-work queue (and its owner against a thief), the frame tables, the record encoder and the release registry. */
#include <stdatomic.h>
#include <stdio.h>

#include "abi/layout.h"
#include "runtime/core/frames.h"
#include "runtime/core/queue.h"
#include "runtime/core/record.h"
#include "runtime/core/release.h"
#include "runtime/core/timers.h"
#include "runtime/sys/sys.h"

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
  uint64_t first = 0;
  uint64_t second = 0;
  uint64_t third = 0;
  CHECK(!ms_queue_push(0, 0, &a, false, &first));
  CHECK(!ms_queue_push(MS_MAX_ISOLATES, 1, &a, false, &first));
  CHECK(ms_queue_push(1, 1, &a, false, &first) && ms_queue_push(1, 2, &b, false, &second));
  CHECK(ms_queue_length(1) == 2 && ms_queue_oldest(1, 10) == 10); /* the first look dates both */
  CHECK(ms_queue_push(1, 3, &c, false, &third));
  CHECK(second == first + 1 && third == first + 2);
  CHECK(!ms_queue_remove(1, 2, third)); /* the sequence of another entry never matches */
  CHECK(ms_queue_remove(1, 2, second) && !ms_queue_remove(1, 2, second));
  CHECK(!ms_queue_steal(1, 14, 5, &id, &work)); /* seen 4 ago, the beat is 5 */
  CHECK(ms_queue_steal(1, 15, 5, &id, &work) && id == 1 && work == &a);
  CHECK(!ms_queue_remove(1, 1, first)); /* taken: its sequence is behind the head now */
  CHECK(ms_queue_oldest(1, 30) == 14 && ms_queue_length(1) == 1); /* the third was first seen by the look at 14 */
  uint64_t sequence = 0;
  for (uint64_t i = 10; i < 60; i++) { /* past the first capacity */
    CHECK(ms_queue_push(1, i, &a, i == 10, &sequence));
  }
  CHECK(ms_queue_remove(1, 59, sequence) && ms_queue_push(1, 59, &a, false, &sequence)); /* found after a grow */
  CHECK(ms_queue_steal(1, 0, -1, &id, &work) && id == 3); /* any age */
  CHECK(ms_queue_steal(1, 31, 1000, &id, &work) && id == 10); /* pushed aged: taken at its first look */
  CHECK(!ms_queue_steal(1, 31, 1000, &id, &work));
  ms_queue_release(1, drop);
  CHECK(dropped == 49 && ms_queue_length(1) == 0 && ms_queue_oldest(1, 40) == INT64_MAX);
  /* An owner that pushes and removes with nobody looking: removed entries are counted until the ring fills, then
   * the owner drops them itself, so the count stays under one ring and a look finds nothing. */
  size_t most = 0;
  for (uint64_t i = 100; i < 1100; i++) {
    CHECK(ms_queue_push(1, i, &a, false, &sequence) && ms_queue_remove(1, i, sequence));
    most = ms_queue_length(1) > most ? ms_queue_length(1) : most;
  }
  CHECK(most <= 16 && !ms_queue_steal(1, 50, -1, &id, &work) && ms_queue_length(1) == 0);
  /* One entry stays while the owner churns behind it: the ring grows once instead of losing it. */
  uint64_t kept = 0;
  CHECK(ms_queue_push(1, 5000, &b, false, &kept));
  for (uint64_t i = 6000; i < 6100; i++) {
    CHECK(ms_queue_push(1, i, &a, false, &sequence) && ms_queue_remove(1, i, sequence));
  }
  CHECK(ms_queue_steal(1, 60, -1, &id, &work) && id == 5000 && work == &b && !ms_queue_remove(1, 5000, kept));
  ms_queue_release(1, NULL);
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

static bool is_code(uintptr_t pc, const void *context) {
  (void)context;
  return pc == 0x1234;
}

/* A frame far larger than a page still has its saved record found, since a deep recursion of fat frames is a fault whose
 * trace must name the callers. */
static void test_scan_big_frame(void) {
  static uintptr_t stack[4096]; /* 32 KiB */
  const size_t record = 3000;    /* 24000 bytes above the stack pointer */
  stack[record] = (uintptr_t)&stack[record + 8]; /* the caller's frame record, above this one */
  stack[record + 1] = 0x1234;
  const uintptr_t low = (uintptr_t)&stack[0];
  const uintptr_t high = (uintptr_t)&stack[4096];
  CHECK(ms_frames_scan_record(low, 0, low, high, is_code, never, NULL) == (uintptr_t)&stack[record]);
}

/* A program built in two units passes one table block per unit; each names its own strings and scopes. */
static void test_frames_set(void) {
  static const uint8_t first_strings[] = "\0a.ms\0first\0inner";
  static const uint8_t second_strings[] = "\0b.ms\0second";
  const MsFuncEntry first_funcs[] = {{.address = 0x2000, .size = 0x100, .name_offset = 6, .file_offset = 1, .line = 20}};
  const MsLineEntry first_lines[] = {{.pc = 0x2000, .line = 21, .file_offset = UINT32_MAX},
                                     {.pc = 0x2040, .line = 5, .file_offset = UINT32_MAX}};
  const uint32_t first_line_scopes[] = {0, 1};
  const MsScopeEntry first_scopes[] = {{.name_offset = 12, .file_offset = UINT32_MAX, .parent = 0, .call_line = 22}};
  const MsFuncEntry second_funcs[] = {{.address = 0x1000, .size = 0x100, .name_offset = 6, .file_offset = 1, .line = 10}};
  const MsLineEntry second_lines[] = {{.pc = 0x1000, .line = 11, .file_offset = UINT32_MAX}};
  const uint32_t second_line_scopes[] = {0};
  const MsTables first = {.abi_version = 3, .funcs = first_funcs, .func_count = 1, .lines = first_lines, .line_count = 2,
                          .strings = first_strings, .strings_len = sizeof first_strings, .line_scopes = first_line_scopes,
                          .scopes = first_scopes, .scope_count = 1};
  const MsTables second = {.abi_version = 3, .funcs = second_funcs, .func_count = 1, .lines = second_lines, .line_count = 1,
                           .strings = second_strings, .strings_len = sizeof second_strings, .line_scopes = second_line_scopes};
  /* the layout of an MsTableSet of two parts, which the compiler writes as data */
  const struct {
    uint32_t abi_version;
    uint32_t count;
    const MsTables *parts[2];
  } both = {MS_TABLES_SET, 2, {&first, &second}};
  ms_frames_install((const MsTables *)&both);
  const uintptr_t addresses[] = {0x2050, 0x1010};
  MsFrameList list = {0};
  ms_frames_describe(addresses, 2, &list);
  /* 0x2050 lies in the inlined `inner` called from line 22 of `first`; 0x1010 in `second` of its own file */
  CHECK(list.count == 3 && list.frames[0].line == 5 && list.frames[0].function[0] == 'i');
  CHECK(list.frames[1].line == 22 && list.frames[1].function[0] == 'f' && list.frames[1].file[0] == 'a');
  CHECK(list.frames[2].line == 11 && list.frames[2].function[0] == 's' && list.frames[2].file[0] == 'b');
  ms_frames_release();
}

static void test_record(void) {
  const MsFaultRecord record = {.pid = 7, .kind = MS_FAULT_KIND_DEADLOCK, .message = ms_span_of_text("boom")};
  uint8_t out[128];
  const size_t needed = ms_fault_record_encode(&record, NULL, 0);
  CHECK(needed == 4 + 1 + 4 + 1 + 1 + 4 + 4 + 4 + 4 + 4);
  CHECK(ms_fault_record_encode(&record, out, sizeof out) == needed);
  CHECK(out[0] == 'M' && out[4] == 2 && out[5] == 7 && out[9] == MS_FAULT_KIND_DEADLOCK);
}

static int released[4];
static int released_count = 0;

static void release_first(void) { released[released_count++] = 1; }
static void release_second(void) { released[released_count++] = 2; }

static void test_release(void) {
  ms_release_at_exit(release_first);
  ms_release_at_exit(release_second);
  ms_release_at_exit(release_first); /* already registered: not added again */
  ms_release_run();
  CHECK(released_count == 2 && released[0] == 2 && released[1] == 1); /* the newest first */
  ms_release_run();
  CHECK(released_count == 2); /* each runs once */
}

/* An owner pushes entries and removes each without the lock while a thief takes the oldest: every entry goes to
 * exactly one of them. */
enum { RACE_ENTRIES = 200000, RACE_ISOLATE = 2 };
static atomic_bool race_done;
static _Atomic uint64_t race_stolen;
static _Atomic uint64_t race_stolen_sum;

static void race_thief(void *unused) {
  (void)unused;
  uint64_t id = 0;
  void *work = NULL;
  while (!atomic_load(&race_done) || ms_queue_length(RACE_ISOLATE) != 0) {
    if (ms_queue_steal(RACE_ISOLATE, 0, -1, &id, &work)) {
      atomic_fetch_add(&race_stolen, 1);
      atomic_fetch_add(&race_stolen_sum, id);
      CHECK(work == &race_done);
    }
  }
}

static void test_queue_race(void) {
  MsSysThread *const thief = ms_sys_thread_spawn(0, race_thief, NULL);
  CHECK(thief != NULL);
  if (thief == NULL) {
    return;
  }
  uint64_t removed = 0;
  uint64_t removed_sum = 0;
  uint64_t sequence[4] = {0};
  for (uint64_t id = 1; id <= RACE_ENTRIES; id++) {
    CHECK(ms_queue_push(RACE_ISOLATE, id, &race_done, false, &sequence[id % 4]));
    if (id % 4 == 0) { /* newest first, as a waiter that runs its own work removes them */
      for (uint64_t back = 0; back < 4; back++) {
        if (ms_queue_remove(RACE_ISOLATE, id - back, sequence[(id - back) % 4])) {
          removed++;
          removed_sum += id - back;
        }
      }
    }
  }
  atomic_store(&race_done, true);
  ms_sys_thread_join(thief);
  const uint64_t total = (uint64_t)RACE_ENTRIES * (RACE_ENTRIES + 1) / 2;
  CHECK(removed + atomic_load(&race_stolen) == RACE_ENTRIES);
  CHECK(removed_sum + atomic_load(&race_stolen_sum) == total);
  ms_queue_release(RACE_ISOLATE, NULL);
}

int main(void) {
  test_timers();
  test_queue();
  test_queue_race();
  test_frames();
  test_frames_set();
  test_scan_big_frame();
  test_record();
  test_release();
  return failures == 0 ? 0 : 1;
}
