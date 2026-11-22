/* compiler/lower/native_sig.c: looks a runtime native up in the generated table of signatures. */
#include "compiler/lower/native_sigs.h"

const MsNativeSig *ms_native_sig_find(MsSpan name) {
  for (unsigned at = 0; at < ms_native_sig_count; at++) {
    if (ms_span_is_text(name, ms_native_sigs[at].name)) {
      return &ms_native_sigs[at];
    }
  }
  return NULL;
}

const MsNativeSig *ms_native_sig_find_method(MsSpan type, MsSpan operation) {
  for (unsigned at = 0; at < ms_native_sig_count; at++) {
    const char *method = ms_native_sigs[at].method;
    if (method == NULL) {
      continue;
    }
    const MsSpan full = ms_span_of_text(method);
    MsSpan rest;
    if (ms_span_starts_with(full, type) && full.len > type.len && full.ptr[type.len] == '.' &&
        ms_span_slice(full, type.len + 1, full.len, &rest) && ms_span_equal(rest, operation)) {
      return &ms_native_sigs[at];
    }
  }
  return NULL;
}

const char *ms_native_repr_find(MsSpan type) {
  for (const MsNativeRepr *row = ms_native_reprs; row->type != NULL; row++) {
    if (ms_span_is_text(type, row->type)) {
      return row->repr;
    }
  }
  return NULL;
}
