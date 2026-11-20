/* Threads and sleeping on Linux and macOS. */
#include "ms_rt/sys.h"

/* Opaque storage larger than pthread_attr_t on every supported target. */
typedef struct {
    _Alignas(16) uint8_t bytes[128];
} mssys_attr;

struct mssys_timespec_s {
    int64_t sec;
    int64_t nsec;
};

extern void *malloc(size_t size);
extern void free(void *p);
extern int pthread_attr_init(mssys_attr *attr);
extern int pthread_attr_destroy(mssys_attr *attr);
extern int pthread_attr_setstacksize(mssys_attr *attr, size_t size);
extern int pthread_create(uintptr_t *thread, const mssys_attr *attr, void *(*start)(void *), void *arg);
extern int pthread_join(uintptr_t thread, void **ret);
extern int nanosleep(const struct mssys_timespec_s *req, struct mssys_timespec_s *rem);

struct start {
    void (*fn)(void *);
    void *arg;
};

static void *trampoline(void *p) {
    struct start s = *(struct start *)p;
    free(p);
    s.fn(s.arg);
    return NULL;
}

uintptr_t mssys_thread_spawn(size_t stack, void (*start)(void *), void *arg) {
    struct start *s = malloc(sizeof *s);
    if (s == NULL) {
        return 0;
    }
    s->fn = start;
    s->arg = arg;
    mssys_attr attr;
    pthread_attr_init(&attr);
    if (stack != 0) {
        pthread_attr_setstacksize(&attr, stack);
    }
    uintptr_t tid = 0;
    int rc = pthread_create(&tid, &attr, trampoline, s);
    pthread_attr_destroy(&attr);
    if (rc != 0) {
        free(s);
        return 0;
    }
    return tid;
}

void mssys_thread_join(uintptr_t thread) { pthread_join(thread, NULL); }

void mssys_sleep_ms(uint32_t ms) {
    struct mssys_timespec_s req = {ms / 1000, (int64_t)(ms % 1000) * 1000000}, rem;
    while (nanosleep(&req, &rem) != 0) {
        req = rem; /* interrupted by a signal: sleep the rest */
    }
}
