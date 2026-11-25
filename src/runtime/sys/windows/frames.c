/* Native stack walking on Windows, for fault reports and the profiler. The frame register does not point at the saved
 * record there, so the walk uses the system's unwind data, which the compiler emits for generated code too (`uwtable`). */
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

enum { POINTER_BYTES = sizeof(uintptr_t) };

/* The innermost frame of a suspended thread may be a leaf, which has no unwind data: its return address is where the
 * ABI keeps it. */
static bool unwind_leaf(Context *registers, uintptr_t high) {
#if defined(__x86_64__)
  const uintptr_t sp = context_word(registers, CONTEXT_SP);
  if (sp + POINTER_BYTES > high) {
    return false;
  }
  const uintptr_t pc = *(const uintptr_t *)(const void *)sp; // NOLINT(performance-no-int-to-ptr)
  const uintptr_t next = sp + POINTER_BYTES;
  __builtin_memcpy(registers->bytes + CONTEXT_PC, &pc, sizeof pc);
  __builtin_memcpy(registers->bytes + CONTEXT_SP, &next, sizeof next);
  return true;
#else
  const uintptr_t pc = context_word(registers, CONTEXT_LR);
  (void)high;
  __builtin_memcpy(registers->bytes + CONTEXT_PC, &pc, sizeof pc);
  return true;
#endif
}

void ms_sys_unwind(const void *registers, uintptr_t low, uintptr_t high, bool (*visit)(uintptr_t, void *), void *context,
                   size_t max_frames) {
  Context here = {0};
  if (registers == NULL) {
    RtlCaptureContext(here.bytes);
    ms_sys_stack_bounds(&low, &high);
  } else {
    __builtin_memcpy(here.bytes, registers, sizeof here.bytes);
  }
  for (size_t step = 0; step <= max_frames; step++) {
    const uintptr_t pc = context_word(&here, CONTEXT_PC);
    const uintptr_t sp = context_word(&here, CONTEXT_SP);
    if (pc == 0 || sp < low || sp >= high || sp % POINTER_BYTES != 0) {
      return;
    }
    uintptr_t image = 0;
    void *const entry = RtlLookupFunctionEntry(pc, &image, NULL);
    if (entry != NULL) {
      void *handler_data = NULL;
      uintptr_t establisher = 0;
      (void)RtlVirtualUnwind(0, image, pc, entry, here.bytes, &handler_data, &establisher, NULL);
    } else if (step != 0 || !unwind_leaf(&here, high)) {
      return; /* only the innermost frame can be a leaf */
    }
    const uintptr_t next_pc = context_word(&here, CONTEXT_PC);
    const uintptr_t next_sp = context_word(&here, CONTEXT_SP);
    if (next_pc == 0 || next_sp <= sp || !visit(next_pc, context)) {
      return;
    }
  }
}
