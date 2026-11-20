/* Threads and sleeping on Linux and macOS. */
#include "ms_rt/sys.h"
#include "timespec.h"

/* Opaque storage larger than pthread_attr_t on every supported target. */
typedef struct MsThreadAttr {
    _Alignas(16) uint8_t bytes[128];
} MsThreadAttr;

extern void *malloc(size_t size);
extern void free(void *p);
extern int pthread_attr_init(MsThreadAttr *attr);
extern int pthread_attr_destroy(MsThreadAttr *attr);
extern int pthread_attr_setstacksize(MsThreadAttr *attr, size_t size);
extern int pthread_create(uintptr_t *thread, const MsThreadAttr *attr, void *(*start)(void *), void *arg);
extern int pthread_join(uintptr_t thread, void **result);
extern int sched_yield(void);
extern int nanosleep(const MsTimespec *request, MsTimespec *remaining);

#define MS_MILLISECONDS_PER_SECOND 1000
#define MS_NANOSECONDS_PER_MILLISECOND INT64_C(1000000)

/* What a new thread runs. Allocated by ms_sys_thread_spawn; the thread owns it from the start and frees it. */
typedef struct MsThreadStart {
    void (*function)(void *);
    void *argument;
} MsThreadStart;

static void *thread_trampoline(void *raw) {
    const MsThreadStart start = *(const MsThreadStart *)raw;
    free(raw);
    start.function(start.argument);
    return NULL;
}

uintptr_t ms_sys_thread_spawn(size_t stack, void (*start)(void *), void *arg) {
    MsThreadStart *const block = malloc(sizeof *block);
    if (block == NULL) {
        return 0;
    }
    *block = (MsThreadStart){.function = start, .argument = arg};

    MsThreadAttr attributes = {0};
    pthread_attr_init(&attributes);
    if (stack != 0) {
        pthread_attr_setstacksize(&attributes, stack);
    }
    uintptr_t thread = 0;
    const int status = pthread_create(&thread, &attributes, thread_trampoline, block);
    pthread_attr_destroy(&attributes);
    if (status != 0) {
        free(block);
        return 0;
    }
    return thread;
}

void ms_sys_thread_join(uintptr_t thread) { pthread_join(thread, NULL); }

void ms_sys_yield(void) { sched_yield(); }

void ms_sys_sleep_ms(uint32_t ms) {
    MsTimespec request = {
        .seconds = ms / MS_MILLISECONDS_PER_SECOND,
        .nanoseconds = (int64_t)(ms % MS_MILLISECONDS_PER_SECOND) * MS_NANOSECONDS_PER_MILLISECOND,
    };
    MsTimespec remaining = {0};
    while (nanosleep(&request, &remaining) != 0) {
        request = remaining; /* a signal interrupted the sleep: sleep the rest */
    }
}
