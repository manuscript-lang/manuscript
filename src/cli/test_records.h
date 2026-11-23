/* cli/test_records.h: the records the test harness appends to its results file. */
#ifndef MS_CLI_TEST_RECORDS_H
#define MS_CLI_TEST_RECORDS_H

#include "cli/test_run.h"

/* One run of the executable as its records report it. Arrays are by test index, or by file number. */
typedef struct TestRecords {
  MsArena *arena;
  size_t total, files;
  bool *started, *running, *timed_out;   /* by test */
  uint64_t *began_ms;                    /* by test: when the host saw it start */
  size_t *running_file;                  /* by test */
  MsSpan *pending_output;                /* by test: output recorded before its result */
  bool *faulted;                         /* by file */
  MsSpan *fault_message, *fault_output; /* by file */
  MsSpan *fault_object;                  /* by file: the fault record as a `fault` object, or empty */
  TestEntryList results;
  size_t consumed;                       /* bytes of the file already parsed */
} TestRecords;

void test_records_init(TestRecords *records, MsArena *arena, size_t total, size_t files);

/* Parses what `text` (the whole results file) gained since the last call. */
void test_records_read(TestRecords *records, MsSpan text);

#endif
