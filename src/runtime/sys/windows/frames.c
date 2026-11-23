/* Native stack walking on Windows, for fault reports. Generated code carries no unwind data, so the walk uses
 * the system's data for the runtime's own frames to reach the first frame of generated code, and the portable
 * scan (ms_frames_scan_record) for the rest. */
#include "runtime/sys/sys.h"
#include "runtime/sys/windows/context.h"
#include "runtime/sys/windows/winapi.h"

// NOLINTBEGIN(readability-identifier-naming): the names are Win32's
MS_WINAPI void RtlCaptureContext(void *context);
MS_WINAPI void *RtlLookupFunctionEntry(uintptr_t pc, uintptr_t *image, void *history);
MS_WINAPI void *RtlVirtualUnwind(uint32_t kind, uintptr_t image, uintptr_t pc, void *entry, void *context,
                 void **handler_data, uintptr_t *establisher, void *pointers);
MS_WINAPI void GetCurrentThreadStackLimits(uintptr_t *low, uintptr_t *high);
// NOLINTEND(readability-identifier-naming)

enum { MAX_NATIVE_FRAMES = 256 };

void ms_sys_stack_bounds(uintptr_t *low, uintptr_t *high) { GetCurrentThreadStackLimits(low, high); }

bool ms_sys_frame_pointer_chain(void) { return false; }

bool ms_sys_has_unwind_data(uintptr_t pc) {
  uintptr_t image = 0;
  return RtlLookupFunctionEntry(pc, &image, NULL) != NULL;
}

/* Accounts the logical frames of the native prefix: nothing is charged until the anchor is reached, then every
 * frame costs one. Returns false when the budget is spent. */
static bool charge_frame(bool *counting, size_t *remaining, bool is_anchor) {
  if (*counting) {
    if (*remaining == 0) {
      return false;
    }
    (*remaining)--;
    return true;
  }
  if (is_anchor) {
    *counting = true;
  }
  return true;
}

bool ms_sys_native_start(uintptr_t anchor_pc, bool (*is_source)(uintptr_t, const void *), const void *context, size_t budget,
             MsSysNativeStart *start) {
  uintptr_t anchor_image = 0;
  void *const anchor = RtlLookupFunctionEntry(anchor_pc, &anchor_image, NULL);
  if (anchor == NULL) {
    static const char note[] = "probe: anchor has no unwind entry\n";
    ms_sys_stderr_write(ms_span_of_text(note));
    return false;
  }
  uintptr_t low = 0;
  uintptr_t high = 0;
  ms_sys_stack_bounds(&low, &high);
  Context registers = {0};
  RtlCaptureContext(registers.bytes);
  bool counting = false;
  size_t remaining = budget;
  for (int step = 0; step < MAX_NATIVE_FRAMES; step++) {
    const uintptr_t pc = context_word(&registers, CONTEXT_PC);
    const uintptr_t sp = context_word(&registers, CONTEXT_SP);
    if (pc == 0 || sp < low || sp >= high || sp % sizeof(uintptr_t) != 0) {
      return false;
    }
    if (is_source(pc, context)) {
      /* A missing anchor must never grant this first source frame a fresh budget. */
      if (!counting) {
        return false;
      }
      *start = (MsSysNativeStart){.pc = pc, .sp = sp, .fp = context_word(&registers, CONTEXT_FP), .budget = remaining};
      return true;
    }
    uintptr_t image = 0;
    void *const entry = RtlLookupFunctionEntry(pc, &image, NULL);
    if (entry == NULL || !charge_frame(&counting, &remaining, entry == anchor)) {
      return false;
    }
    void *handler_data = NULL;
    uintptr_t establisher = 0;
    (void)RtlVirtualUnwind(0, image, pc, entry, registers.bytes, &handler_data, &establisher, NULL);
    const uintptr_t next_sp = context_word(&registers, CONTEXT_SP);
    const uintptr_t next_pc = context_word(&registers, CONTEXT_PC);
    if (next_sp < sp || (next_sp == sp && next_pc == pc)) {
      return false;
    }
  }
  return false;
}
