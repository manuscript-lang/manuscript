/* Owns test_options.h. */
#include "driver/test_options.h"

#include "base/float_parse.h"

#include "base/duration.h"
#include "driver/invocation_rules.h"

enum { NANOS_PER_MS = 1000000 };

/* Splits `--name=value`; false for an argument with no `=`. */
static bool split_option(MsSpan arg, MsSpan *name, MsSpan *value) {
  for (size_t i = 0; i < arg.len; i++) {
    if (arg.ptr[i] == '=') {
      *name = ms_span_of(arg.ptr, i);
      *value = ms_span_of(arg.ptr + i + 1, arg.len - i - 1);
      return true;
    }
  }
  return false;
}

static int64_t integer(MsSpan value) {
  int64_t number = 0;
  return ms_invocation_parse_int(value, &number) ? number : 0;
}

static int64_t milliseconds(MsSpan value) {
  int64_t nanos = 0;
  return ms_duration_parse(value, &nanos) ? nanos / NANOS_PER_MS : 0;
}

/* Applies one `--name=value`; false when the name is not a selection option. */
static bool apply(MsTestOptions *options, MsSpan name, MsSpan value) {
  if (ms_span_is_text(name, "--test")) {
    ms_span_list_push(&options->names, value);
  } else if (ms_span_is_text(name, "--match")) {
    options->matching = value;
  } else if (ms_span_is_text(name, "--exclude")) {
    options->exclude = value;
  } else if (ms_span_is_text(name, "--filter")) {
    options->filter = value;
  } else if (ms_span_is_text(name, "--repeat")) {
    options->repeat = (size_t)integer(value);
  } else if (ms_span_is_text(name, "--shuffle")) {
    options->shuffled = true;
    options->shuffle_seed = integer(value);
  } else if (ms_span_is_text(name, "--runs")) {
    options->runs = integer(value);
  } else if (ms_span_is_text(name, "--seed")) {
    options->has_seed = true;
    options->seed = integer(value);
  } else if (ms_span_is_text(name, "--fuzz")) {
    options->fuzz_ms = milliseconds(value);
  } else if (ms_span_is_text(name, "--time")) {
    options->bench_time_ms = milliseconds(value);
  } else if (ms_span_is_text(name, "--samples")) {
    options->bench_samples = integer(value);
  } else if (ms_span_is_text(name, "--iterations")) {
    options->bench_iterations = integer(value);
  } else if (ms_span_is_text(name, "--baseline")) {
    options->baseline = value;
  } else if (ms_span_is_text(name, "--fail-over")) {
    options->has_fail_over = true;
    MsSpan number = value;
    if (number.len > 0 && number.ptr[number.len - 1] == '%') {
      number.len--;
    }
    if (ms_parse_float(number, &options->fail_over) != MS_PARSE_FLOAT_OK) {
      options->fail_over = 0;
    }
  } else if (ms_span_is_text(name, "--timeout")) {
    options->timeout_set = true;
    options->timeout_ms = milliseconds(value);
  } else {
    return false;
  }
  return true;
}

void ms_test_options_parse(const MsSpanList *arguments, MsTestOptions *out) {
  *out = (MsTestOptions){.repeat = 1, .timeout_ms = MS_TEST_DEFAULT_TIMEOUT_MS, .fail_over = 3.0};
  size_t at = 0;
  for (; at < arguments->len; at++) {
    const MsSpan arg = arguments->ptr[at];
    MsSpan name = {0};
    MsSpan value = {0};
    if (ms_span_is_text(arg, "--")) {
      at++;
      break;
    }
    if (ms_span_is_text(arg, "--list")) {
      out->list = true;
    } else if (ms_span_is_text(arg, "--fail-fast")) {
      out->fail_fast = true;
    } else if (ms_span_is_text(arg, "--ops")) {
      out->ops = true;
    } else if (!split_option(arg, &name, &value) || !apply(out, name, value)) {
      break;
    }
  }
  if (out->fuzz_ms > 0 && !out->timeout_set) {
    out->timeout_ms = 0; /* a fuzz budget applies to every property, so the default limit would cut it short */
  }
  for (; at < arguments->len && out->program_count < sizeof out->program / sizeof out->program[0]; at++) {
    out->program[out->program_count++] = arguments->ptr[at];
  }
}

void ms_test_options_free(MsTestOptions *options) {
  ms_span_list_free(&options->names);
}
