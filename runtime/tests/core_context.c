/* Unit test of runtime/core/context.c: a stack switch both ways, a call on another stack, and a guard jump
 * that skips frames. Run under the sanitizers by `make c-test`. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../core/context.h"

enum { STACK_BYTES = 64 * 1024, ROUNDS = 1000 };

static uintptr_t main_sp;
static uintptr_t child_sp;
static unsigned counter;

static void expect(bool condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "core_context: failed: %s\n", what);
        exit(1);
    }
}

/* Runs on the child stack: counts each time it is resumed and switches back, forever. */
static void child_entry(void) {
    uintptr_t teb[MS_CTX_TEB_WORDS] = {0};
    for (;;) {
        counter++;
        ms_ctx_switch(&child_sp, main_sp, teb);
    }
}

#ifdef _WIN32
#include <malloc.h>
#define aligned_alloc(alignment, size) _aligned_malloc((size), (alignment))
#define aligned_free(pointer) _aligned_free(pointer)
#else
#define aligned_free(pointer) free(pointer)
#endif

static void test_switch(void) {
    uint8_t *const stack = aligned_alloc(16, STACK_BYTES);
    expect(stack != NULL, "stack allocated");
    memset(stack, 0, STACK_BYTES);
    child_sp = ms_ctx_initial_sp(stack + STACK_BYTES, child_entry);
    uintptr_t teb[MS_CTX_TEB_WORDS] = {0};
    for (unsigned round = 1; round <= ROUNDS; round++) {
        ms_ctx_switch(&main_sp, child_sp, teb);
        expect(counter == round, "the child ran once per switch");
    }
    aligned_free(stack);
}

static uintptr_t sp_inside;

static void record_stack_pointer(void *argument) {
    /* The frame address, not a local's: AddressSanitizer may move locals to a fake stack. */
    sp_inside = (uintptr_t)__builtin_frame_address(0);
    *(int *)argument = 42;
}

static void test_call_on_stack(void) {
    uint8_t *const stack = aligned_alloc(16, STACK_BYTES);
    expect(stack != NULL, "stack allocated");
    int value = 0;
    uintptr_t save = 0;
    uintptr_t teb[2 * MS_CTX_TEB_WORDS] = {0};
    ms_ctx_call_on_stack((uintptr_t)stack + STACK_BYTES, record_stack_pointer, &value, &save, teb);
    expect(value == 42, "the function ran");
    expect(sp_inside >= (uintptr_t)stack && sp_inside < (uintptr_t)stack + STACK_BYTES, "it ran on the new stack");
    aligned_free(stack);
}

static uintptr_t jump_slot;

static void jump_out(void) { ms_guard_jump(&jump_slot, 7, NULL); }
/* Through a pointer, so the compiler does not see that the deepest call never returns. */
static void (*volatile leave)(void) = jump_out;

static void jump_from_depth(void *argument) {
    const unsigned depth = *(unsigned *)argument;
    unsigned deeper = depth - 1;
    if (depth > 0) {
        jump_from_depth(&deeper);
    } else {
        leave();
    }
}

static void return_normally(void *argument) { *(int *)argument = 1; }

static void test_guard(void) {
    int ran = 0;
    expect(ms_guard_enter(&jump_slot, return_normally, &ran) == 0 && ran == 1, "a normal return gives 0");
    unsigned depth = 50;
    expect(ms_guard_enter(&jump_slot, jump_from_depth, &depth) == 7, "a jump returns its status from enter");
    expect(ms_guard_enter(&jump_slot, return_normally, &ran) == 0, "the slot can be used again");
}

int main(void) {
    test_switch();
    test_call_on_stack();
    test_guard();
    puts("core_context: ok");
    return 0;
}
