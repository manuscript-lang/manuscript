/* Unit test of the staged fault ABI (src/runtime/core/fault_abi.c): the faults generated code raises, the cleanup
 * stack, shields, the unwinding byte and msrt_guard_call, over the C fault path. Run under the sanitizers by
 * `make c-test`. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "ms_rt/sys.h"
#include "../core/fault_abi.h"
#include "../core/scheduler.h"

static void expect(bool condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "core_fault_abi: failed: %s\n", what);
        exit(1);
    }
}

static void exit_hook(int status) { _exit(status); }

/* Runs `raise` guarded and checks that its fault's message starts with `message`. */
static void expect_fault(void (*raise)(uint8_t *), const char *message) {
    MsStr text = {0};
    expect(msrt_guard_call(raise, NULL, &text) == 1, "the fault ends the guarded call");
    const size_t length = ms_str_len(&text);
    const uint8_t *const data = ms_str_data(&text);
    expect(length >= strlen(message) && memcmp(data, message, strlen(message)) == 0, message);
    ms_str_release(&text);
}

static void raise_index(uint8_t *unused) { (void)unused; msrt_index_fault(7, 3); }
static void raise_insert(uint8_t *unused) { (void)unused; msrt_list_index_fault(0, 9, 4); }
static void raise_remove_empty(uint8_t *unused) { (void)unused; msrt_list_index_fault(1, 0, 0); }
static void raise_set(uint8_t *unused) { (void)unused; msrt_list_index_fault(2, -9, 4); }
static void raise_none(uint8_t *unused) { (void)unused; msrt_fault_unwrap_none(); }
static void raise_div(uint8_t *unused) { (void)unused; msrt_fault_div_zero(); }
static void raise_div_overflow(uint8_t *unused) { (void)unused; msrt_fault_div_overflow(INT64_MIN, -1); }
static void raise_raw(uint8_t *unused) { (void)unused; msrt_fault((const uint8_t *)"raw", 3); }
static void raise_kind(uint8_t *unused) { (void)unused; msfault_raise(MS_FAULT_KIND_OVERFLOW, (const uint8_t *)"kinded", 6); }
static void raise_hook(uint8_t *unused) { (void)unused; ms_fault_hook(MS_FAULT_KIND_FAULT, "from the hook"); }

static void test_messages(void) {
    expect_fault(raise_index, "index 7 out of range for length 3; pass a default");
    expect_fault(raise_insert, "List.insert: index must be between -4 and 4 (negative indexes count from the end), found 9");
    expect_fault(raise_remove_empty, "List.remove: index has no valid value for an empty collection, found 0");
    expect_fault(raise_set, "List.set: index must be between -4 and 3 (negative indexes count from the end), found -9");
    expect_fault(raise_none, "called Optional.get() on none");
    expect_fault(raise_div, "division by zero; right must be nonzero, found 0");
    expect_fault(raise_div_overflow, "division overflow; found left -9223372036854775808 and right -1; result must be between");
    expect_fault(raise_raw, "raw");
    expect_fault(raise_kind, "kinded");
    expect_fault(raise_hook, "from the hook");
}

static void return_normally(uint8_t *unused) { (void)unused; }

static uint8_t order[8];
static size_t order_length;
static void note(uint8_t *argument) { order[order_length++] = (uint8_t)(uintptr_t)argument; }
static void raise_with_cleanups(uint8_t *unused) {
    (void)unused;
    (void)msrt_cleanup_push(note, (uint8_t *)(uintptr_t)1);
    (void)msrt_cleanup_push(note, (uint8_t *)(uintptr_t)2);
    msrt_fault((const uint8_t *)"x", 1);
}

static void test_guard_and_cleanups(void) {
    expect(msrt_guard_call(return_normally, NULL, NULL) == 0, "a call that returns is ok");
    MsStr text = {0};
    expect(msrt_guard_call(return_normally, NULL, &text) == 0 && ms_str_len(&text) == 0, "and leaves no message");
    ms_str_release(&text);
    expect(msrt_rollback_needed() == 0, "no guard and no cleanup: no rollback");
    order_length = 0;
    expect(msrt_guard_call(raise_with_cleanups, NULL, NULL) == 1, "faulted");
    expect(order_length == 2 && order[0] == 2 && order[1] == 1, "cleanups run newest first");
    expect(msrt_cleanup_base() == 0, "and the stack is empty afterwards");
    const size_t first = msrt_cleanup_push(note, (uint8_t *)(uintptr_t)7);
    expect(msrt_rollback_needed() == 1, "a registered cleanup needs rollback");
    msrt_cleanup_cancel(first);
    msrt_cleanup_discard(first);
    expect(msrt_cleanup_base() == 0 && msrt_rollback_needed() == 0, "discarding empties the stack");
}

static void test_shields_and_unwinding(void) {
    msrt_shield_enter();
    expect(ms_shielded(), "inside a shield");
    msrt_shield_exit();
    expect(!ms_shielded(), "and out of it");
    expect(msrt_unwinding() == 0, "not unwinding");
    msrt_unwinding_resume();
    expect(msrt_unwinding() == 1 && msrt_isolate_hdr()->unwinding == 1, "resume marks the task unwinding");
    msrt_unwinding_pause();
    expect(msrt_unwinding() == 0, "pause clears it");
    msrt_cancel_edges();
    ms_sched_cancel_return();
    expect(msrt_unwinding() == 1, "with cancel edges a cancel is delivered by return");
    msrt_unwinding_pause();
}

int main(void) {
    const MsSchedHooks hooks = {.exit_process = exit_hook};
    const MsPollOps poll_ops = {0};
    ms_sched_set_hooks(&hooks, &poll_ops);
    test_messages();
    test_guard_and_cleanups();
    test_shields_and_unwinding();
    puts("core_fault_abi: ok");
    ms_sched_teardown();
    return 0;
}
