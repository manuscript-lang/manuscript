/* The unstarted-work queue: order, removal from the middle, stealing by age, and owner against thieves. */
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>

#include "queue.h"

static int failures;
#define CHECK(cond)                                                              \
    do {                                                                         \
        if (!(cond)) {                                                           \
            fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #cond); \
            failures++;                                                          \
        }                                                                        \
    } while (0)

static void order_and_age(void) {
    CHECK(ms_queue_push(1, 10, NULL, 100));
    CHECK(ms_queue_push(1, 11, NULL, 200));
    CHECK(ms_queue_push(1, 12, NULL, 300));
    CHECK(ms_queue_length(1) == 3);
    CHECK(ms_queue_oldest(1) == 100);
    uint64_t id = 0;
    void *work = NULL;
    CHECK(!ms_queue_steal(1, 99, &id, &work)); /* nothing old enough */
    CHECK(ms_queue_steal(1, 150, &id, &work) && id == 10);
    CHECK(ms_queue_remove(1, 12)); /* the newest, by its owner */
    CHECK(!ms_queue_remove(1, 12));
    CHECK(ms_queue_remove(1, 11));
    CHECK(ms_queue_length(1) == 0 && ms_queue_oldest(1) == INT64_MAX);
    CHECK(!ms_queue_steal(1, INT64_MAX, &id, &work));
    ms_queue_release(1, NULL);
}

static void middle_removal(void) {
    for (uint64_t i = 1; i <= 100; i++) {
        CHECK(ms_queue_push(2, i, NULL, (int64_t)i));
    }
    for (uint64_t i = 2; i <= 99; i++) {
        CHECK(ms_queue_remove(2, i)); /* leaves 1 and 100 */
    }
    uint64_t id = 0;
    void *work = NULL;
    CHECK(ms_queue_steal(2, INT64_MAX, &id, &work) && id == 1);
    CHECK(ms_queue_steal(2, INT64_MAX, &id, &work) && id == 100);
    CHECK(!ms_queue_steal(2, INT64_MAX, &id, &work));
    ms_queue_release(2, NULL);
}

enum { TOTAL = 20000 };
static _Atomic uint64_t taken_sum;
static _Atomic int owner_done;

static void *thief(void *unused) {
    (void)unused;
    uint64_t id = 0;
    void *work = NULL;
    while (!atomic_load(&owner_done) || ms_queue_length(3) > 0) {
        if (ms_queue_steal(3, INT64_MAX, &id, &work)) {
            atomic_fetch_add(&taken_sum, id);
        }
    }
    return NULL;
}

/* The owner pushes TOTAL entries and removes some itself; every id is run exactly once (by the owner or a thief). */
static void owner_against_thieves(void) {
    pthread_t threads[3];
    for (int i = 0; i < 3; i++) {
        pthread_create(&threads[i], NULL, thief, NULL);
    }
    uint64_t own_sum = 0;
    for (uint64_t i = 1; i <= TOTAL; i++) {
        CHECK(ms_queue_push(3, i, NULL, (int64_t)i));
        if (i % 3 == 0 && ms_queue_remove(3, i)) {
            own_sum += i;
        }
    }
    atomic_store(&owner_done, 1);
    for (int i = 0; i < 3; i++) {
        pthread_join(threads[i], NULL);
    }
    CHECK(own_sum + atomic_load(&taken_sum) == (uint64_t)TOTAL * (TOTAL + 1) / 2);
    ms_queue_release(3, NULL);
}

int main(void) {
    order_and_age();
    middle_removal();
    owner_against_thieves();
    if (failures != 0) {
        return 1;
    }
    puts("core_queue ok");
    return 0;
}
