/* ms_sys_thread_* over pthreads for the core tests, which do not link libuv (the program's own is sys/thread.c). */
#define _DEFAULT_SOURCE 1
#include <pthread.h>
#include <time.h>

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

void ms_sys_sleep_ms(uint32_t ms) {
    const struct timespec delay = {.tv_sec = (time_t)(ms / 1000), .tv_nsec = (long)(ms % 1000) * 1000000L};
    (void)nanosleep(&delay, NULL);
}

struct MsSysSignal {
    pthread_mutex_t lock;
    pthread_cond_t cond;
    bool sent;
};

MsSysSignal *ms_sys_signal_new(void) {
    struct MsSysSignal *const signal = msrt_alloc(sizeof *signal);
    signal->sent = false;
    pthread_mutex_init(&signal->lock, NULL);
    pthread_cond_init(&signal->cond, NULL);
    return signal;
}

void ms_sys_signal_free(MsSysSignal *signal) {
    pthread_cond_destroy(&signal->cond);
    pthread_mutex_destroy(&signal->lock);
    msrt_free(signal);
}

bool ms_sys_signal_wait(MsSysSignal *signal, int64_t timeout_ns) {
    pthread_mutex_lock(&signal->lock);
    if (!signal->sent) {
        if (timeout_ns < 0) {
            pthread_cond_wait(&signal->cond, &signal->lock);
        } else {
            struct timespec until;
            clock_gettime(CLOCK_REALTIME, &until);
            const int64_t total = until.tv_nsec + timeout_ns;
            until.tv_sec += total / 1000000000;
            until.tv_nsec = total % 1000000000;
            pthread_cond_timedwait(&signal->cond, &signal->lock, &until);
        }
    }
    const bool sent = signal->sent;
    signal->sent = false;
    pthread_mutex_unlock(&signal->lock);
    return sent;
}

void ms_sys_signal_send(MsSysSignal *signal) {
    pthread_mutex_lock(&signal->lock);
    signal->sent = true;
    pthread_mutex_unlock(&signal->lock);
    pthread_cond_signal(&signal->cond);
}
