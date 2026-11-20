/* The runtime services the std natives call and the unit tests do not exercise: strings are plain malloc'd bytes, the
 * program has one task (so nothing parks and the pool is never used), and a stop request never arrives. Linked into
 * every runtime/tests/std_*.c test, which links all of runtime/std. */
#define _POSIX_C_SOURCE 200809L
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "ms_rt/start.h"
#include "../../std/abi.h"
#include "ms_rt/obj.h"
#include "ms_rt/process.h"
#include "ms_rt/string.h"
#include "ms_rt/sys.h"
#include "ms_sched.h"

void msrt_string_from_bytes(const uint8_t *ptr, size_t len, MsStr *out) {
    uint8_t *copy = malloc(len + 1);
    if (copy != NULL && len > 0) {
        memcpy(copy, ptr, len);
    }
    *out = (MsStr){.ptr_word = copy, .tagged = len};
}

void msrt_string_clone(const MsStr *s, MsStr *out) { msrt_string_from_bytes(ms_str_data(s), ms_str_len(s), out); }
void msrt_string_free(const MsStr *s) { free(s->ptr_word); }

/* The start-up records: a test program records no start time and was given no arguments. */
int64_t msrt_start_nanos(void) { return 0; }
void msrt_counts(uint64_t *out) { memset(out, 0, 7 * sizeof *out); }
void msrt_argv(MsVec *out) { *out = (MsVec){0}; }

void msrt_heap_stats(int64_t *out) { out[0] = out[1] = 0; }

/* A map of Strings to Strings as a list of pairs, for the one map a std native builds (the environment); the real
 * map is runtime/core/map.c, which these tests do not link. Only the first word of the map value is used, as a count. */
enum { STUB_MAP_LIMIT = 8192, STUB_MAP_BYTES = 56 };
typedef struct StubEntry {
    MsStr key, value;
} StubEntry;
static StubEntry stub_entries[STUB_MAP_LIMIT];

void msrt_map_new(MsMap *out) { memset(out, 0, STUB_MAP_BYTES); }

void msrt_map_add(MsMap *map, const MsTypeDesc *kd, const MsTypeDesc *vd, uint8_t *key, uint8_t *value) {
    (void)kd;
    (void)vd;
    size_t count = 0;
    memcpy(&count, map, sizeof count);
    memcpy(&stub_entries[count].key, key, sizeof(MsStr));
    memcpy(&stub_entries[count].value, value, sizeof(MsStr));
    count++;
    memcpy(map, &count, sizeof count);
}

const uint8_t *msrt_map_get_ptr(const MsMap *map, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key) {
    (void)kd;
    (void)vd;
    MsStr wanted;
    memcpy(&wanted, key, sizeof wanted);
    size_t count = 0;
    memcpy(&count, map, sizeof count);
    for (size_t i = 0; i < count; i++) {
        if (ms_str_len(&stub_entries[i].key) == ms_str_len(&wanted) &&
            memcmp(ms_str_data(&stub_entries[i].key), ms_str_data(&wanted), ms_str_len(&wanted)) == 0) {
            return (const uint8_t *)&stub_entries[i].value;
        }
    }
    return NULL;
}

void msrt_map_drop(MsMap *map, const MsTypeDesc *kd, const MsTypeDesc *vd) {
    (void)kd;
    (void)vd;
    size_t count = 0;
    memcpy(&count, map, sizeof count);
    for (size_t i = 0; i < count; i++) {
        free(stub_entries[i].key.ptr_word);
        free(stub_entries[i].value.ptr_word);
    }
    count = 0;
    memcpy(map, &count, sizeof count);
}

uint32_t msrt_task_wait_fd(int32_t fd, uint32_t events, int64_t timeout_ns) {
    (void)fd;
    (void)events;
    (void)timeout_ns;
    return 0;
}

bool ms_sched_cancel_pending(void) { return false; }
void ms_sched_cancel_return(void) {}
void ms_sched_stop_hold(void) {}
void ms_sched_stop_release(void) {}
bool ms_sched_read_limit_passed(void) { return false; }
bool ms_sched_on_pool_thread(void) { return false; }
bool ms_sched_pool_alone(void) { return true; }
bool ms_sched_pool_admit(size_t bytes, bool *cancelled) {
    (void)bytes;
    *cancelled = false;
    return false;
}
void ms_sched_pool_release(void) {}
MsSchedWait ms_sched_pool_run_shielded(MsSchedJobFn run, void *data) {
    run(data);
    return MS_SCHED_DONE;
}

size_t msrt_cleanup_push(void (*run)(uint8_t *), uint8_t *argument);
void msrt_cleanup_discard(size_t handle);
uint8_t msrt_rollback_needed(void);
void msrt_string_empty(MsStr *out);

/* The unit tests never leave program code by a jump, so a cleanup is never run. */
size_t msrt_cleanup_push(void (*run)(uint8_t *), uint8_t *argument) {
    (void)run;
    (void)argument;
    return 1;
}
void msrt_cleanup_discard(size_t handle) { (void)handle; }
uint8_t msrt_rollback_needed(void) { return 0; }
void msrt_string_empty(MsStr *out) { *out = (MsStr){.ptr_word = NULL, .tagged = 0}; }
int32_t ms_sched_stdout_error(void) { return 0; }
void ms_sched_flush_stdout(void) {}

/* Tokens count posts under one lock: a park takes one, or waits for a post or the timeout. */
enum { STUB_TOKENS = 64 };
static pthread_mutex_t token_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t token_posted = PTHREAD_COND_INITIALIZER;
static uint64_t token_pending[STUB_TOKENS + 1];
static uint64_t token_issued;

uint64_t msrt_token_new(uint32_t flags) {
    (void)flags;
    pthread_mutex_lock(&token_lock);
    const uint64_t token = token_issued % STUB_TOKENS + 1;
    token_issued++;
    token_pending[token] = 0;
    pthread_mutex_unlock(&token_lock);
    return token;
}
void msrt_token_free(uint64_t token) { (void)token; }
void msrt_token_post_remote(uint64_t token, uint64_t value) {
    (void)value;
    pthread_mutex_lock(&token_lock);
    token_pending[token]++;
    pthread_cond_broadcast(&token_posted);
    pthread_mutex_unlock(&token_lock);
}
uint32_t msrt_token_park(uint64_t token, int64_t timeout_ns, uint64_t *value) {
    *value = 0;
    struct timespec until;
    clock_gettime(CLOCK_REALTIME, &until);
    until.tv_sec += (time_t)(timeout_ns / 1000000000);
    until.tv_nsec += (long)(timeout_ns % 1000000000);
    if (until.tv_nsec >= 1000000000) {
        until.tv_sec++;
        until.tv_nsec -= 1000000000;
    }
    uint32_t result = 0;
    pthread_mutex_lock(&token_lock);
    while (token_pending[token] == 0 && result == 0) {
        if (timeout_ns < 0) {
            pthread_cond_wait(&token_posted, &token_lock);
        } else if (pthread_cond_timedwait(&token_posted, &token_lock, &until) != 0) {
            result = MS_WAIT_TIMEOUT;
        }
    }
    if (token_pending[token] != 0) {
        token_pending[token] = 0;
    }
    pthread_mutex_unlock(&token_lock);
    return result;
}

/* The stream table is the Rust runtime's; a test reads the descriptor itself, so its id is the descriptor. */
int64_t msrt_streams_open(int64_t fd, int64_t flags);
int64_t msrt_streams_open(int64_t fd, int64_t flags) {
    (void)flags;
    return fd;
}

/* A read wait runs inline: the unit tests have no scheduler to park on. */
MsSchedWait ms_sched_pool_run(MsSchedJobFn run, MsSchedJobFn release, void *data, int64_t timeout_ns) {
    (void)release;
    (void)timeout_ns;
    run(data);
    return MS_SCHED_DONE;
}

uint32_t msrt_task_sleep(int64_t ns) {
    (void)ns;
    return 0;
}

void msrt_process_on_exit(void (*hook)(void)) { (void)hook; }
