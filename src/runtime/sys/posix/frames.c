/* Stack walking support: generated code keeps a frame pointer here, so the walk needs nothing native. */
#include "runtime/sys/sys.h"

bool ms_sys_frame_pointer_chain(void) { return true; }

void ms_sys_stack_bounds(uintptr_t *low, uintptr_t *high) {
  *low = 0;
  *high = 0;
}

void ms_sys_unwind(const void *registers, uintptr_t low, uintptr_t high, bool (*visit)(uintptr_t, void *), void *context,
                   size_t max_frames) {
  (void)registers;
  (void)low;
  (void)high;
  (void)visit;
  (void)context;
  (void)max_frames;
}
