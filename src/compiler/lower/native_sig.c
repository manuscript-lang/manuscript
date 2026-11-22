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
