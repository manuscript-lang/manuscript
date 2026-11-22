/* Owns `ms bench` (bench_command.h): reads the arguments, checks the input with its bench files, selects the bench
 * blocks and lists them or reports that none match. Running the selected benches needs bench lowering in the back end,
 * which the C compiler does not have yet: that step reports "not implemented" (status 70). */
#include "driver/bench_command.h"

#include <stdio.h>

#include "base/message.h"
#include "driver/checked_input.h"
#include "driver/invocation.h"
#include "driver/test_options.h"

enum { STATUS_FAILED = 1, STATUS_NOT_IMPLEMENTED = 70 };

static void print_text(FILE *stream, MsSpan text) {
  (void)fwrite(text.ptr, 1, text.len, stream);
}

/* The names `--bench` and `--filter` select, in declaration order. False, with the message printed, when a `--bench`
 * names none. */
static bool select_benches(MsArena *arena, const MsSpanList *names, const MsTestOptions *options, MsSpanList *selected) {
  bool *found = MS_ARENA_NEW_ARRAY(arena, bool, options->names.len + 1);
  for (size_t i = 0; i < names->len; i++) {
    bool exact = options->names.len == 0;
    for (size_t n = 0; n < options->names.len; n++) {
      if (ms_span_equal(options->names.ptr[n], names->ptr[i])) {
        exact = true;
        found[n] = true;
      }
    }
    size_t at = 0;
    if (exact && (options->filter.len == 0 || ms_span_find(names->ptr[i], options->filter, &at))) {
      ms_span_list_push(selected, names->ptr[i]);
    }
  }
  for (size_t n = 0; n < options->names.len; n++) {
    if (!found[n]) {
      print_text(stderr, ms_message_format(arena, "unknown test \"%S\"; use --list to find full module::name identities\n",
                                           options->names.ptr[n], (MsSpan){0}));
      return false;
    }
  }
  return true;
}

static int bench_input(MsArena *arena, const MsInvocation *invocation) {
  MsCheckedInput checked = {0};
  if (!ms_checked_input_load(arena, &checked, invocation->filename, MS_INPUT_TESTS)) {
    const int status = invocation->json ? ms_checked_input_report_json(&checked) : ms_checked_input_report(&checked);
    ms_checked_input_free(&checked);
    return status;
  }
  MsTestOptions options;
  ms_test_options_parse(&invocation->arguments, &options);
  MsSpanList names = {0};
  MsSpanList selected = {0};
  ms_checked_input_test_names(arena, &checked, true, &names);
  int status = STATUS_FAILED;
  const bool filtered = options.filter.len > 0 || options.names.len > 0;
  if (!select_benches(arena, &names, &options, &selected)) {
    status = STATUS_FAILED;
  } else if (selected.len == 0 && filtered) {
    print_text(stdout, ms_message_format(arena, "no benches match selection (%z benches available); use --list to find "
                                                "full module::name identities\n", names.len));
  } else if (options.list) {
    for (size_t i = 0; i < selected.len; i++) {
      print_text(stdout, ms_message_format(arena, "%S\n", selected.ptr[i], (MsSpan){0}));
    }
    status = 0;
  } else if (selected.len == 0) {
    print_text(stdout, ms_span_of_text("no bench blocks found: add bench blocks to bench.ms or *_bench.ms files in the "
                                       "project, or pass a .ms file\n0 benches, 0 failed\n"));
    status = 0;
  } else {
    print_text(stderr, ms_span_of_text("ms bench: running bench blocks is not implemented yet\n"));
    status = STATUS_NOT_IMPLEMENTED;
  }
  ms_span_list_free(&selected);
  ms_span_list_free(&names);
  ms_test_options_free(&options);
  ms_checked_input_free(&checked);
  return status;
}

int ms_bench_command(int argc, char **argv) {
  MsArena arena = ms_arena_new();
  MsInvocation invocation = {0};
  int status = ms_invocation_parse(&arena, "bench", argc, argv, &invocation);
  if (status == 0) {
    status = bench_input(&arena, &invocation);
  }
  ms_invocation_free(&invocation);
  ms_arena_free(&arena);
  return status;
}
