/* runtime/core/index_fault.c: the faults of a bad index. The messages are part of the observable behaviour. */
#include "runtime/core/index_fault.h"

#include "base/strbuild.h"
#include "runtime/core/fault.h"

MS_NORETURN void msrt_index_fault(int64_t index, int64_t length) {
  MsStrBuild message = ms_strbuild_new();
  ms_strbuild_append_text(&message, "index ");
  ms_strbuild_append_i64(&message, index);
  ms_strbuild_append_text(&message, " out of range for length ");
  ms_strbuild_append_i64(&message, length);
  ms_strbuild_append_text(&message, "; use get_or(index, default) to avoid the fault");
  ms_fault(MS_FAULT_KIND_INDEX_OUT_OF_RANGE, ms_strbuild_span(&message));
}

MS_NORETURN void msrt_collection_index_fault(const char *operation, int64_t length, int64_t index) {
  MsStrBuild message = ms_strbuild_new();
  ms_strbuild_append_text(&message, operation);
  if (length == 0) {
    ms_strbuild_append_text(&message, ": index has no valid value for an empty collection, found ");
  } else {
    ms_strbuild_append_text(&message, ": index must be between ");
    ms_strbuild_append_i64(&message, -length);
    ms_strbuild_append_text(&message, " and ");
    ms_strbuild_append_i64(&message, length - 1);
    ms_strbuild_append_text(&message, " (negative indexes count from the end), found ");
  }
  ms_strbuild_append_i64(&message, index);
  ms_fault(MS_FAULT_KIND_INDEX_OUT_OF_RANGE, ms_strbuild_span(&message));
}

/* The name of a list mutator and the highest index it accepts. */
static const char *mutator_name(int64_t operation, int64_t length, int64_t *highest) {
  *highest = length - 1;
  switch (operation) {
  case 0:
    *highest = length;
    return "List.insert";
  case 1:
    return "List.remove";
  case 3:
    return "List.swap";
  case 4:
    return "List.replace";
  default:
    return "List.set";
  }
}

MS_NORETURN void msrt_list_index_fault(int64_t operation, int64_t index, int64_t length) {
  int64_t highest = 0;
  const char *name = mutator_name(operation, length, &highest);
  if (operation != 0 && length == 0) {
    msrt_collection_index_fault(name, 0, index);
  }
  MsStrBuild message = ms_strbuild_new();
  ms_strbuild_append_text(&message, name);
  ms_strbuild_append_text(&message, ": index must be between ");
  ms_strbuild_append_i64(&message, -length);
  ms_strbuild_append_text(&message, " and ");
  ms_strbuild_append_i64(&message, highest);
  ms_strbuild_append_text(&message, " (negative indexes count from the end), found ");
  ms_strbuild_append_i64(&message, index);
  ms_fault(MS_FAULT_KIND_INDEX_OUT_OF_RANGE, ms_strbuild_span(&message));
}
