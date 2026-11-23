// C port of the promise modes of main.ms: the floor for start-and-wait. A promise is a row in a table with a
// generation, its work is a heap closure, a start pushes the row on a locked queue, and a wait takes its own
// entry back and runs it on the waiter's stack, as the Manuscript runtime does when nobody else took the work.
// Every table and queue access is bounds checked. `./async-c inline 1000000`, `./async-c batch 1000000`.
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct Closure {
  int64_t (*code)(struct Closure *);
  int64_t captured;
} Closure;

typedef struct Row {
  Closure *work;
  int64_t result;
  uint32_t generation;
  uint32_t queued_at; /* index in the queue + 1, 0 when not queued */
  uint8_t state;      /* 0 free, 1 pending, 2 done */
} Row;

enum { ROWS = 256, QUEUE = 256 };

static Row rows[ROWS];
static uint32_t free_rows[ROWS];
static uint32_t free_count;
static uint32_t queue[QUEUE];
static uint32_t queue_len;
static atomic_flag queue_lock = ATOMIC_FLAG_INIT;

static void fail(const char *text) {
  (void)fprintf(stderr, "%s\n", text);
  exit(1);
}

static void lock(void) {
  while (atomic_flag_test_and_set_explicit(&queue_lock, memory_order_acquire)) {
  }
}

static void unlock(void) { atomic_flag_clear_explicit(&queue_lock, memory_order_release); }

static Row *row_of(uint64_t id) {
  const uint32_t index = (uint32_t)id;
  if (index >= ROWS || rows[index].state == 0 || rows[index].generation != (uint32_t)(id >> 32)) {
    fail("no such promise");
  }
  return &rows[index];
}

static uint64_t promise_start(Closure *work) {
  if (free_count == 0) {
    fail("promise table full");
  }
  const uint32_t index = free_rows[--free_count];
  Row *const row = &rows[index];
  row->work = work;
  row->state = 1;
  lock();
  if (queue_len >= QUEUE) {
    fail("queue full");
  }
  queue[queue_len++] = index;
  row->queued_at = queue_len;
  unlock();
  return (uint64_t)row->generation << 32 | index;
}

static int64_t promise_wait(uint64_t id) {
  Row *const row = row_of(id);
  if (row->state == 1) {
    lock();
    const uint32_t at = row->queued_at;
    if (at == 0 || at > queue_len) {
      fail("promise not queued");
    }
    const uint32_t last = queue[queue_len - 1];
    queue[at - 1] = last;
    rows[last].queued_at = at;
    queue_len--;
    row->queued_at = 0;
    unlock();
    Closure *const work = row->work;
    row->work = NULL;
    row->result = work->code(work);
    free(work);
    row->state = 2;
  }
  const int64_t result = row->result;
  row->state = 0;
  row->generation++;
  if (free_count >= ROWS) {
    fail("promise freed twice");
  }
  free_rows[free_count++] = (uint32_t)(row - rows);
  return result;
}

static int64_t work(Closure *closure) { return closure->captured * 2 + 1; }

static uint64_t start_work(int64_t value) {
  Closure *const closure = malloc(sizeof *closure);
  if (closure == NULL) {
    fail("out of memory");
  }
  *closure = (Closure){.code = work, .captured = value};
  return promise_start(closure);
}

static int64_t now_ns(void) {
  struct timespec at;
  (void)clock_gettime(CLOCK_MONOTONIC, &at);
  return (int64_t)at.tv_sec * 1000000000 + at.tv_nsec;
}

int main(int argc, char **argv) {
  if (argc < 3) {
    fail("usage: async-c <inline|batch> <n>");
  }
  const int64_t n = strtoll(argv[2], NULL, 10);
  for (uint32_t i = 0; i < ROWS; i++) {
    free_rows[free_count++] = ROWS - 1 - i;
  }
  const int64_t begin = now_ns();
  int64_t total = 0;
  if (strcmp(argv[1], "inline") == 0) {
    for (int64_t i = 0; i < n; i++) {
      total += promise_wait(start_work(i));
    }
  } else if (strcmp(argv[1], "batch") == 0) {
    uint64_t ids[64];
    for (int64_t done = 0; done < n; done += 64) {
      for (int64_t i = 0; i < 64; i++) {
        ids[i] = start_work(done + i);
      }
      for (int64_t i = 0; i < 64; i++) {
        total += promise_wait(ids[i]);
      }
    }
  } else {
    fail("unknown mode");
  }
  printf("%s total %lld ns/op %lld\n", argv[1], (long long)total, (long long)((now_ns() - begin) / n));
  return 0;
}
