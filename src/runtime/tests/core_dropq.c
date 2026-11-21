/* Unit test of the drop worklist (src/runtime/core/dropq.c): nesting up to the limit runs inline, deeper drops are
 * deferred and drained in constant stack by the outermost leave, and the grown copy runs its job. */
#include <stdio.h>
#include <stdlib.h>

#include "../core/dropq.h"
#include "ms_rt/alloc.h"
#include "ms_rt/dropq.h"

static void expect(bool condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "core_dropq: failed: %s\n", what);
        exit(1);
    }
}

typedef struct Node {
    struct Node *next;
} Node;

static size_t dropped;
static size_t deepest;
static size_t current;

/* The drop glue of a chain: every node is dropped through the worklist, as generated code does. */
static void drop_node(uint8_t *block) {
    Node *const node = (Node *)(void *)block;
    Node *const next = node->next;
    node->next = NULL;
    dropped++;
    if (next == NULL) {
        return;
    }
    current++;
    if (current > deepest) {
        deepest = current;
    }
    if (msrt_drop_enter() != 0) {
        msrt_drop_defer(drop_node, (uint8_t *)next);
    } else {
        drop_node((uint8_t *)next);
        msrt_free(next);
        msrt_drop_leave();
    }
    current--;
}

static void test_deep_chain(void) {
    enum { LENGTH = 100000 };
    Node *head = NULL;
    for (size_t i = 0; i < LENGTH; i++) {
        Node *const node = msrt_alloc(sizeof *node);
        node->next = head;
        head = node;
    }
    expect(msrt_drop_enter() == 0, "the outermost enter runs");
    drop_node((uint8_t *)head);
    msrt_free(head);
    msrt_drop_leave();
    expect(dropped == LENGTH, "every node was dropped");
    expect(deepest < 1000, "the stack held a bounded number of levels");
}

static int copied;

static void copy_value(const uint8_t *src, uint8_t *dst) { *dst = (uint8_t)(*src + 1); }

static void test_grown_copy(void) {
    const uint8_t src = 41;
    uint8_t dst = 0;
    msrt_slot_copy_grown(copy_value, &src, &dst);
    copied = dst;
    expect(copied == 42, "the copy ran");
}

int main(void) {
    msrt_heap_claim();
    test_deep_chain();
    test_grown_copy();
    msdrop_reset();
    puts("core_dropq: ok");
    return 0;
}
