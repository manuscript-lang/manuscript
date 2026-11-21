/* Stack walking support: generated code keeps a frame pointer here, so the walk needs nothing native. */
#include "runtime/sys/sys.h"

bool ms_sys_frame_pointer_chain(void) { return true; }

bool ms_sys_has_unwind_data(uintptr_t pc) {
  (void)pc;
  return false;
}

void ms_sys_stack_bounds(uintptr_t *low, uintptr_t *high) {
  *low = 0;
  *high = 0;
}

bool ms_sys_native_start(uintptr_t anchor_pc, bool (*is_source)(uintptr_t, const void *), const void *context, size_t budget,
                         MsSysNativeStart *start) {
  (void)anchor_pc;
  (void)is_source;
  (void)context;
  (void)budget;
  (void)start;
  return false;
}
