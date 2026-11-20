/* ms_sys_thread_* over pthreads for the core tests, which do not link libuv (the program's own is sys/thread.c). */
#define _DEFAULT_SOURCE 1
#include <pthread.h>

#include "ms_rt/alloc.h"
#include "ms_rt/sys.h"

struct MsSysThread {
    pthread_t thread;
    MsSysThreadFn start;
    void *argument;
};

static void *thread_main(void *argument) {
    struct MsSysThread *const thread = argument;
    thread->start(thread->argument);
    return NULL;
}

MsSysThread *ms_sys_thread_spawn(size_t stack, MsSysThreadFn start, void *arg) {
    (void)stack;
    struct MsSysThread *const thread = msrt_alloc(sizeof *thread);
    thread->start = start;
    thread->argument = arg;
    if (pthread_create(&thread->thread, NULL, thread_main, thread) != 0) {
        msrt_free(thread);
        return NULL;
    }
    return thread;
}

void ms_sys_thread_join(MsSysThread *thread) {
    (void)pthread_join(thread->thread, NULL);
    msrt_free(thread);
}
