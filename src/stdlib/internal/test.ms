export extern fn msstd_test_repr[T](value T) String

// A new, empty capture of standard output for the test runner.
export extern fn msrt_test_capture_new() Int

// Sends the standard output of the running task, and of the tasks and promises it
// starts from now on, to capture `id` (0: standard output).
export extern fn msrt_test_capture_set(id Int) Void

// Returns and clears what capture `id` has collected.
export extern fn msrt_test_capture_take(id Int) String

// Ends capture `id`; later output of its tasks goes to standard output.
export extern fn msrt_test_capture_free(id Int) Void

// The capture the running task's standard output goes to, or 0.
export extern fn msrt_test_capture_current() Int

// Bounds the running task's waits for one test (`on`), or lifts the bound: from
// `MS_TEST_TIMEOUT_NS` from now (unset or 0: no bound) each fails with ETIMEDOUT, as a
// promise timeout does.
export extern fn msrt_test_deadline(on Bool) Void

// A borrowed copy of `text` whose last byte is the last byte of readable memory; the
// next page is unreadable, so a read past the end faults every time.
export extern fn msrt_test_edge_string(text String) String

// The encoded fault record of the last task under capture `id` that faulted, or "";
// taking it clears it.
export extern fn msrt_test_capture_fault(id Int) String

// Appends `text` to the file at `path` (the test runner's results file), whole.
export extern fn msrt_test_record(path, text String) Void
