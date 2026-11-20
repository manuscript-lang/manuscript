/* The @std/fs natives over the OS layer and the runtime's scheduler. This file holds the pool admission that every
 * large copy goes through; the path operations, files, walks and watches are in the fs_*.c files beside it. */
#include "ms_rt/fs.h"

#include "ms_sched.h"

uint8_t msstd_fs_admit(int64_t bytes) {
    size_t size = bytes > 0 ? (size_t)bytes : 0;
    bool cancelled = false;
    const bool held = ms_sched_pool_admit(size, &cancelled);
    if (cancelled) {
        /* Nothing is held here, so the cancel is delivered at once. */
        ms_sched_cancel_return();
        return 0;
    }
    return held ? 1 : 0;
}

void msstd_fs_release(void) { ms_sched_pool_release(); }
