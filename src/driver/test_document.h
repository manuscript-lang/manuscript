/* driver/test_document.h: the `--json` document of `ms test` and `ms bench`. Port of `Document` in
 * crates/ms-cli/src/engine/testing.rs. */
#ifndef MS_DRIVER_TEST_DOCUMENT_H
#define MS_DRIVER_TEST_DOCUMENT_H

#include <stdio.h>

#include "base/strbuild.h"
#include "driver/json_value.h"
#include "driver/test_options.h"

/* The tests or benches a run executes: indices into the listing, in execution order. */
typedef struct TestPlan {
  size_t *selected;
  size_t count;
} TestPlan;

/* Selects what `--test` and `--filter` name. False when a `--test` names none, with `error` saying so. `noun` is
 * "test" or "bench". */
bool test_plan_select(MsArena *arena, const MsSpanList *names, const MsTestOptions *options, const char *noun,
                      TestPlan *plan, MsSpan *error);

/* Seeded Fisher-Yates, as the Rust CLI does it. */
void test_plan_shuffle(TestPlan *plan, int64_t seed);

/* One planned test or bench. */
typedef struct DocumentCase {
  MsSpan name, failure;
  const char *status; /* "passed", "failed", "skipped" or "not_run" */
  int64_t nanos;
  const MsJson *stats; /* a bench's statistics; NULL for a test */
} DocumentCase;

typedef struct TestDocument {
  bool bench, listed, completed, has_shuffle;
  size_t repeat; /* 0 leaves it out */
  int64_t shuffle_seed;
  MsSpan source_root;
  DocumentCase *cases;
  size_t count, available;
  int exit_code;
  MsSpan reason;      /* why the run ended early; empty for none */
  int64_t nanos;
  MsSpan output;      /* what the command printed to standard output */
  MsSpan diagnostics; /* the array's entries as `ms_json_diag` writes them; empty for none */
} TestDocument;

/* The position `file:line:column` that ends a failure's text (`\n  at f.ms:30:5`), or false. */
bool test_failure_position(MsSpan message, MsSpan *file, int64_t *line, int64_t *column);

/* Appends the `MST001` diagnostic of a failure that is not in the source (`phase` is "execution" or "build"), at
 * `file:line:1`, as an entry of `diagnostics`. */
void test_document_diagnostic(MsStrBuild *out, const char *phase, MsSpan message, MsSpan file, uint32_t line);

/* With `--json` a command's standard output is the document's `stdout` member, not the terminal: `into` collects it
 * (NULL ends the capture). */
void test_output_capture(MsStrBuild *into);
bool test_capturing(void);

/* Writes to `stream`; standard output goes to the capture while one is active. */
void test_print(FILE *stream, MsSpan text);

/* Writes the document, with what was printed so far as its `stdout`, when a capture is active. */
void test_document_finish(TestDocument *document);

/* A run that could not start: the message goes to standard error, and `--json` gets a document naming the phase
 * ("execution" or "build") with the diagnostic at `input:1:1`. Returns the failure status. */
int test_fail_early(MsArena *arena, MsSpan source_root, MsSpan input, bool bench, const char *phase, MsSpan message);

/* Appends the document and its closing newline. */
void test_document_write(const TestDocument *document, MsStrBuild *out);

#endif
