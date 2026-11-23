/* Owns test_run.h. */
#include "cli/files.h"
#include "cli/test_run.h"

#include <stdio.h>

#include "base/dir.h"
#include "base/file.h"
#include "base/message.h"
#include "base/path.h"
#include "base/process.h"
#include "cli/test_records.h"
#include "cli/watch.h"

enum { GRACE_MS = 1000, NANOS_PER_MS = 1000000 };

/* What a run is doing while its process lives: the records read so far and the limit each test has. */
typedef struct Supervision {
  TestRecords *records;
  MsSpan results_path;
  uint64_t limit_ms; /* 0: no limit */
  bool killed;
} Supervision;

/* Reads new records; true when a running test is past its limit, which stops the process. */
static bool supervise(void *context) {
  Supervision *s = context;
  TestRecords *r = s->records;
  MsBytes bytes = {0};
  if (ms_file_read(s->results_path, &bytes)) {
    test_records_read(r, ms_bytes_span(&bytes));
  }
  ms_bytes_free(&bytes);
  const uint64_t now = watch_now_ms();
  bool late = false;
  for (size_t t = 0; s->limit_ms > 0 && t < r->total; t++) {
    if (r->running[t] && now - r->began_ms[t] >= s->limit_ms) {
      r->timed_out[t] = true;
      late = true;
    }
  }
  s->killed = s->killed || late;
  return late;
}

static MsSpan describe_exit(MsArena *arena, int status, bool timed_out) {
  if (timed_out) {
    return ms_span_of_text("was stopped because a test timed out");
  }
  return status < 0 ? ms_span_of_text("was terminated by a signal")
                    : ms_message_format(arena, "exited with status %z", (size_t)status);
}

typedef struct Together {
  TestRecords records;
  MsSpan ended;
  bool crashed; /* no test timed out */
} Together;

/* Runs the executable once for `indices`; the records it wrote are in `run`. */
static void run_together(const TestJob *job, const size_t *indices, size_t count, size_t files, Together *run) {
  MsArena *arena = job->arena;
  test_records_init(&run->records, arena, job->names->len, files);
  MsString directory = ms_string_empty();
  const MsString temp = ms_temp_dir();
  if (!ms_dir_make_temp(ms_string_span(&temp), ms_span_of_text("ms-test-results-"), &directory)) {
    run->ended = ms_span_of_text("cannot create a temporary directory");
    return;
  }
  const MsSpan folder = ms_arena_copy(arena, ms_string_span(&directory));
  MsStrBuild select = ms_strbuild_new();
  for (size_t i = 0; i < count; i++) {
    ms_strbuild_printf(&select, "%s%zu", i == 0 ? "" : ",", indices[i]);
  }
  const MsSpan results = ms_message_format(arena, "%S/results", folder, (MsSpan){0});
  const MsSpan printed = ms_message_format(arena, "%S/stdout", folder, (MsSpan){0});
  MsSpanList env = {0};
  ms_span_list_push(&env, ms_message_format(arena, "MS_TEST_SELECT=%S", ms_strbuild_span(&select), (MsSpan){0}));
  ms_span_list_push(&env, ms_message_format(arena, "MS_TEST_RESULTS=%S", results, (MsSpan){0}));
  const MsTestOptions *options = job->options;
  if (options->timeout_ms > 0) {
    ms_span_list_push(&env, ms_message_format(arena, "MS_TEST_TIMEOUT_NS=%z", (size_t)options->timeout_ms * NANOS_PER_MS));
  }
  if (options->runs > 0) {
    ms_span_list_push(&env, ms_message_format(arena, "MS_TEST_RUNS=%z", (size_t)options->runs));
  }
  if (options->has_seed) {
    ms_span_list_push(&env, ms_message_format(arena, "MS_TEST_SEED=%z", (size_t)options->seed));
  }
  if (options->fuzz_ms > 0) {
    ms_span_list_push(&env, ms_message_format(arena, "MS_TEST_FUZZ_MS=%z", (size_t)options->fuzz_ms));
  }
  MsSpanList argv = {0};
  ms_span_list_push(&argv, job->executable);
  for (size_t i = 0; i < options->program_count; i++) {
    ms_span_list_push(&argv, options->program[i]);
  }
  Supervision supervision = {.records = &run->records, .results_path = results,
                             .limit_ms = options->timeout_ms > 0 ? (uint64_t)options->timeout_ms + GRACE_MS : 0};
  const MsProcessSpec spec = {.argv = argv.ptr, .argc = argv.len, .directory = job->working, .env = env.ptr,
                              .envc = env.len, .log_path = printed, .inherit_error = true,
                              .supervise = supervise, .supervise_context = &supervision};
  MsStrBuild why = ms_strbuild_new();
  int status = 0;
  (void)fflush(stdout);
  if (ms_process_run(&spec, &status, &why)) {
    run->ended = describe_exit(arena, status, supervision.killed);
  } else {
    run->ended = ms_arena_copy(arena, ms_strbuild_span(&why));
  }
  run->crashed = !supervision.killed;
  const MsSpan output = ms_cli_read_text(arena, printed);
  (void)fwrite(output.ptr, 1, output.len, stdout);
  test_records_read(&run->records, ms_cli_read_text(arena, results));
  ms_path_remove_tree(folder);
  ms_string_release(&directory);
  ms_strbuild_free(&why);
  ms_strbuild_free(&select);
  ms_span_list_free(&env);
  ms_span_list_free(&argv);
}

TestEntry *test_entry_take(TestEntryList *results, size_t index) {
  for (size_t i = 0; i < results->len; i++) {
    if (results->ptr[i].index == index && !results->ptr[i].taken) {
      results->ptr[i].taken = true;
      return &results->ptr[i];
    }
  }
  return NULL;
}

/* The file number of each test: files numbered in order of their first test; a name is `file::test`. */
static size_t file_numbers(MsArena *arena, const MsSpanList *names, size_t **numbers) {
  MsSpanList seen = {0};
  *numbers = MS_ARENA_NEW_ARRAY(arena, size_t, names->len + 1);
  for (size_t n = 0; n < names->len; n++) {
    const MsSpan name = names->ptr[n];
    size_t end = 0;
    while (end + 1 < name.len && !(name.ptr[end] == ':' && name.ptr[end + 1] == ':')) {
      end++;
    }
    const MsSpan file = ms_span_of(name.ptr, end < name.len ? end : name.len);
    size_t at = 0;
    while (at < seen.len && !ms_span_equal(seen.ptr[at], file)) {
      at++;
    }
    if (at == seen.len) {
      ms_span_list_push(&seen, file);
    }
    (*numbers)[n] = at;
  }
  const size_t count = seen.len;
  ms_span_list_free(&seen);
  return count;
}

static bool has_result(const TestEntryList *results, size_t index) {
  for (size_t i = 0; i < results->len; i++) {
    if (results->ptr[i].index == index) {
      return true;
    }
  }
  return false;
}

typedef struct Ended {
  bool *ended;     /* by file */
  MsSpan *why;     /* by file: the failure of the test the file ended on */
  MsSpan *later;   /* by file: why its later tests did not run */
} Ended;

/* Marks the file of test `index` ended when the run says so: it faulted, the test timed out, or the process crashed
 * while the test ran (the culprit is not known, so every running test's file ends). */
static void mark_ended(const TestJob *job, const Together *run, size_t index, size_t file, Ended *e) {
  const TestRecords *r = &run->records;
  if (e->ended[file]) {
    return;
  }
  if (r->faulted[file]) {
    e->why[file] = r->fault_message[file];
    e->later[file] = ms_span_of_text("an earlier test in this file faulted");
  } else if (r->timed_out[index]) {
    e->why[file] = ms_message_format(job->arena, "timed out after %zms; a test that never waits is stopped with its "
                                                 "process",
                                     (size_t)job->options->timeout_ms, (MsSpan){0});
    e->later[file] = ms_span_of_text("an earlier test in this file timed out");
  } else if (run->crashed && r->running[index]) {
    e->why[file] = ms_message_format(job->arena, "the test process %S while this test ran", run->ended, (MsSpan){0});
    e->later[file] = ms_message_format(job->arena, "the test process %S while an earlier test in this file ran",
                                       run->ended, (MsSpan){0});
  } else {
    return;
  }
  e->ended[file] = true;
}

/* Gives test `index`, whose file ended, the outcome that ending implies. */
static void end_test(const TestRecords *r, size_t index, size_t file, const Ended *e, TestEntryList *results) {
  TestOutcome outcome = {.kind = TEST_NOT_RUN, .message = e->later[file]};
  if (r->started[index]) {
    outcome.kind = TEST_FAILED;
    outcome.message = e->why[file];
    outcome.output = r->faulted[file] ? r->fault_output[file] : (MsSpan){0};
    outcome.fault = r->faulted[file] ? r->fault_object[file] : (MsSpan){0};
  }
  test_entry_list_push(results, (TestEntry){.index = index, .outcome = outcome});
}

/* Settles the tests of ended files; returns the others, which run again in a new process. */
static size_t settle(const TestJob *job, const Together *run, size_t *remaining, size_t left, const size_t *files,
                     TestEntryList *results) {
  Ended e = {.ended = MS_ARENA_NEW_ARRAY(job->arena, bool, run->records.files + 1),
             .why = MS_ARENA_NEW_ARRAY(job->arena, MsSpan, run->records.files + 1),
             .later = MS_ARENA_NEW_ARRAY(job->arena, MsSpan, run->records.files + 1)};
  for (size_t i = 0; i < left; i++) {
    if (!has_result(&run->records.results, remaining[i])) {
      mark_ended(job, run, remaining[i], files[remaining[i]], &e);
    }
  }
  size_t next = 0;
  for (size_t i = 0; i < left; i++) {
    const size_t index = remaining[i];
    if (has_result(&run->records.results, index)) {
      continue;
    }
    if (e.ended[files[index]]) {
      end_test(&run->records, index, files[index], &e, results);
    } else {
      remaining[next++] = index;
    }
  }
  return next;
}

void test_run_all(const TestJob *job, const size_t *indices, size_t count, TestEntryList *results) {
  size_t *files = NULL;
  const size_t file_count = file_numbers(job->arena, job->names, &files);
  size_t *remaining = MS_ARENA_NEW_ARRAY(job->arena, size_t, count + 1);
  size_t left = count;
  for (size_t i = 0; i < count; i++) {
    remaining[i] = indices[i];
  }
  while (left > 0) {
    Together run = {0};
    run_together(job, remaining, left, file_count, &run);
    for (size_t i = 0; i < run.records.results.len; i++) {
      test_entry_list_push(results, run.records.results.ptr[i]);
    }
    const size_t next = settle(job, &run, remaining, left, files, results);
    if (next == left) {
      for (size_t i = 0; i < next; i++) {
        test_entry_list_push(results, (TestEntry){.index = remaining[i],
                                                  .outcome = {.kind = TEST_FAILED,
                                                              .message = ms_message_format(
                                                                  job->arena, "the test process %S before this test "
                                                                              "started", run.ended, (MsSpan){0})}});
      }
      break;
    }
    left = next;
  }
}
