/* Threads and sleeping on every platform, over libuv's portable thread API. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c11 */

#include <uv.h>

#include "ms_rt/sys.h"

struct MsSysThread {
    uv_thread_t thread;
};

MsSysThread *ms_sys_thread_spawn(size_t stack, MsSysThreadFn start, void *arg) {
    MsSysThread *const handle = ms_sys_malloc(sizeof *handle);
    if (handle == NULL) {
        return NULL;
    }
    const uv_thread_options_t options = {.flags = stack == 0 ? UV_THREAD_NO_FLAGS : UV_THREAD_HAS_STACK_SIZE,
                                         .stack_size = stack};
    if (uv_thread_create_ex(&handle->thread, &options, start, arg) != 0) {
        ms_sys_free(handle);
        return NULL;
    }
    return handle;
}

void ms_sys_thread_join(MsSysThread *thread) {
    (void)uv_thread_join(&thread->thread);
    ms_sys_free(thread);
}

void ms_sys_sleep_ms(uint32_t ms) { uv_sleep(ms); }
