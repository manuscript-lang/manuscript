/* Unit test of faults and their reports (src/runtime/core: fault.c, fault_record.c, frames.c): source frames from the
 * compiler's tables (inlining, repeats, glue, unsorted tables), the frame-pointer chain across stack segments, the
 * record the CLI reads, and the fault path itself: cleanups in order, a fault inside a cleanup, the guard that
 * receives the report, and the process end (in a child process, since it never returns). Run under the sanitizers
 * by `make c-test`. */
#define _GNU_SOURCE /* mkstemp and setenv */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include "ms_rt/alloc.h"
#include "ms_rt/sys.h"
#include "../core/fault.h"
#include "../core/scheduler.h"

static void expect(bool condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "core_fault: failed: %s\n", what);
        exit(1);
    }
}

static MsBytes bytes_of(const char *text) { return ms_bytes_of((const uint8_t *)text, strlen(text)); }

/* ---- tables ---- */

enum { BLOB_BYTES = 256 };
static char blob[BLOB_BYTES];
static size_t blob_length = 1; /* offset 0 is an empty name */

static uint32_t blob_add(const char *name) {
    const size_t length = strlen(name) + 1;
    expect(blob_length + length <= BLOB_BYTES, "the blob has room");
    const uint32_t offset = (uint32_t)blob_length;
    memcpy(blob + blob_length, name, length);
    blob_length += length;
    return offset;
}

static MsFuncEntry funcs[2];
static MsLineEntry lines[5];
static uint32_t line_scopes[5];
static MsScopeEntry scopes[1];
static MsTables tables;

/* main.ms: `main` at 0x1000 (line 5 from 0x1000, line 6 from 0x1010 where `inner` from lib.ms is inlined), and
 * `helper` at 0x1100 whose range at 0x1140 has no position (compiler glue). */
static void build_tables(void) {
    const uint32_t main_file = blob_add("main.ms");
    const uint32_t lib_file = blob_add("lib.ms");
    const uint32_t main_name = blob_add("main");
    const uint32_t helper_name = blob_add("helper");
    const uint32_t inner_name = blob_add("inner");
    funcs[0] = (MsFuncEntry){.address = 0x1000, .size = 0x100, .name_offset = main_name, .file_offset = main_file, .line = 4};
    funcs[1] = (MsFuncEntry){.address = 0x1100, .size = 0x100, .name_offset = helper_name, .file_offset = lib_file, .line = 10};
    lines[0] = (MsLineEntry){.pc = 0x1000, .line = 5, .file_offset = UINT32_MAX};
    lines[1] = (MsLineEntry){.pc = 0x1010, .line = 6, .file_offset = UINT32_MAX};
    lines[2] = (MsLineEntry){.pc = 0x1100, .line = 11, .file_offset = UINT32_MAX};
    lines[3] = (MsLineEntry){.pc = 0x1140, .line = 0, .file_offset = UINT32_MAX};
    lines[4] = (MsLineEntry){.pc = 0x1180, .line = 12, .file_offset = UINT32_MAX};
    line_scopes[1] = 1;
    scopes[0] = (MsScopeEntry){.name_offset = inner_name, .file_offset = lib_file, .parent = 0, .call_line = 7};
    tables = (MsTables){.abi_version = MS_TABLES_WITH_SCOPES,
                        .funcs = funcs,
                        .func_count = 2,
                        .lines = lines,
                        .line_count = 5,
                        .strings = (const uint8_t *)blob,
                        .strings_len = blob_length,
                        .line_scopes = line_scopes,
                        .scopes = scopes,
                        .scope_count = 1};
}

static void check_frame(const MsFrame *frame, const char *file, uint32_t line, const char *function, uint32_t repeated,
                        const char *what) {
    expect(strcmp(frame->file, file) == 0 && frame->line == line && strcmp(frame->function, function) == 0 &&
               frame->repeated == repeated,
           what);
}

static void test_find_function(void) {
    expect(ms_frames_find_function(&tables, 0x1001) == &funcs[0], "a return address inside main");
    expect(ms_frames_find_function(&tables, 0x1100) == &funcs[0], "the call ends just before the return address");
    expect(ms_frames_find_function(&tables, 0x1101) == &funcs[1], "inside helper");
    expect(ms_frames_find_function(&tables, 0x1201) == NULL, "past the last function");
    expect(ms_frames_find_function(&tables, 0x1000) == NULL, "before the first function");
}

static void test_describe(void) {
    expect(ms_frames_install(&tables), "tables install");
    MsFrameList list = {0};
    /* The inlined callee comes first, then the function it was inlined into, at the line of the inlined call. */
    const uintptr_t inlined[] = {0x1015};
    ms_frames_describe(inlined, 1, &list);
    expect(list.count == 2, "an inlined call is two frames");
    check_frame(&list.frames[0], "lib.ms", 6, "inner", 0, "the inlined callee");
    check_frame(&list.frames[1], "main.ms", 7, "main", 0, "the caller at the line of the call");

    /* Identical consecutive frames (recursion) collapse into one with a count; glue has no frame. */
    MsFrameList repeated = {0};
    const uintptr_t recursion[] = {0x1005, 0x1005, 0x1005, 0x1145, 0x1105};
    ms_frames_describe(recursion, 5, &repeated);
    expect(repeated.count == 2, "recursion collapses, glue is skipped");
    check_frame(&repeated.frames[0], "main.ms", 5, "main", 2, "three identical frames are one with two repeats");
    check_frame(&repeated.frames[1], "lib.ms", 11, "helper", 0, "the next function");

    /* The innermost frame in a range without a position takes the nearest earlier line. */
    MsFrameList innermost = {0};
    const uintptr_t at_glue[] = {0x1145};
    ms_frames_describe(at_glue, 1, &innermost);
    expect(innermost.count == 1, "the raising frame keeps a position");
    check_frame(&innermost.frames[0], "lib.ms", 11, "helper", 0, "the nearest earlier line");

    /* A report keeps 32 frames and says the rest were omitted. */
    MsFrameList truncated = {0};
    uintptr_t many[MS_FRAMES_REPORT_MAX + 4];
    for (size_t i = 0; i < MS_COUNT_OF(many); i++) {
        many[i] = (i % 2 == 0) ? 0x1005 : 0x1105;
    }
    ms_frames_describe(many, MS_COUNT_OF(many), &truncated);
    expect(truncated.count == MS_FRAMES_REPORT_MAX && truncated.truncated, "a long trace is cut");
}

static void test_unsorted_tables(void) {
    MsFuncEntry swapped[2] = {funcs[1], funcs[0]};
    MsLineEntry shuffled[5] = {lines[4], lines[0], lines[3], lines[1], lines[2]};
    uint32_t shuffled_scopes[5] = {0, 0, 0, 1, 0};
    MsTables unsorted = tables;
    unsorted.funcs = swapped;
    unsorted.lines = shuffled;
    unsorted.line_scopes = shuffled_scopes;
    expect(ms_frames_install(&unsorted), "unsorted tables install");
    expect(ms_frames_tables() != &unsorted, "they are copied");
    MsFrameList list = {0};
    const uintptr_t inlined[] = {0x1015, 0x1105};
    ms_frames_describe(inlined, 2, &list);
    expect(list.count == 3, "the same frames as sorted tables give");
    check_frame(&list.frames[0], "lib.ms", 6, "inner", 0, "scopes follow their lines");
    check_frame(&list.frames[2], "lib.ms", 11, "helper", 0, "functions are found by address");
    expect(ms_frames_install(&tables), "sorted tables install");
    expect(ms_frames_tables() == &tables, "sorted tables are used as they are");
}

/* ---- the frame-pointer chain ---- */

typedef struct VisitLog {
    uintptr_t seen[8];
    size_t count;
} VisitLog;

static bool log_visit(uintptr_t return_address, void *context) {
    VisitLog *const log = context;
    log->seen[log->count++] = return_address;
    return log->count < MS_COUNT_OF(log->seen);
}

static void test_walk_chain(void) {
    /* Two frame records one above the other, then one with no return address. */
    _Alignas(16) uintptr_t stack[16] = {0};
    stack[0] = (uintptr_t)&stack[4];
    stack[1] = 0xaaa1;
    stack[4] = (uintptr_t)&stack[8];
    stack[5] = 0xbbb2;
    stack[8] = (uintptr_t)&stack[12];
    stack[9] = 0;
    const MsStackWindow window = {.low = (uintptr_t)stack, .high = (uintptr_t)(stack + 16)};
    VisitLog log = {0};
    ms_frames_walk_chain((uintptr_t)stack, window, log_visit, &log);
    expect(log.count == 2 && log.seen[0] == 0xaaa1 && log.seen[1] == 0xbbb2, "the chain ends at a zero return address");

    /* A frame pointer outside the window ends the walk. */
    VisitLog outside = {0};
    const MsStackWindow narrow = {.low = (uintptr_t)stack, .high = (uintptr_t)(stack + 5)};
    ms_frames_walk_chain((uintptr_t)stack, narrow, log_visit, &outside);
    expect(outside.count == 1, "a record outside the stack ends the walk");

    /* A link that does not go up ends it, so a corrupt chain cannot loop. */
    stack[4] = (uintptr_t)&stack[0];
    VisitLog loop = {0};
    ms_frames_walk_chain((uintptr_t)stack, window, log_visit, &loop);
    expect(loop.count == 2, "a link going down is the last frame");

    uintptr_t captured[4] = {0};
    stack[4] = (uintptr_t)&stack[8];
    expect(ms_frames_capture((uintptr_t)stack, 0, window, captured, 1) == 1 && captured[0] == 0xaaa1, "capture stops at capacity");
}

static void test_walk_across_segments(void) {
    /* The task grew into a second segment: the frame pointer of the inner frames is in the new segment, whose chain
     * cell leads back to the old one. */
    _Alignas(16) uintptr_t memory[64] = {0};
    uintptr_t *const old_segment = memory + 32;
    uintptr_t *const new_segment = memory;
    new_segment[0] = (uintptr_t)&old_segment[4]; /* the inner frame's saved frame pointer points into the old segment */
    new_segment[1] = 0x111;
    old_segment[4] = (uintptr_t)&old_segment[8];
    old_segment[5] = 0x222;
    old_segment[8] = 0;
    old_segment[9] = 0;
    uintptr_t cell[4] = {(uintptr_t)old_segment, (uintptr_t)(old_segment + 32), 0, 0};
    const MsStackWindow window = {.low = (uintptr_t)new_segment, .high = (uintptr_t)(new_segment + 32), .chain = (uintptr_t)cell};
    VisitLog log = {0};
    ms_frames_walk_chain((uintptr_t)new_segment, window, log_visit, &log);
    expect(log.count == 2 && log.seen[0] == 0x111 && log.seen[1] == 0x222, "the walk follows the chain cell");
}

static bool is_source(uintptr_t pc, void *context) {
    (void)context;
    return pc == 0x1005;
}

static bool is_native(uintptr_t pc, void *context) {
    (void)context;
    return pc == 0x9009;
}

static void test_scan_record(void) {
    _Alignas(16) uintptr_t stack[32] = {0};
    /* A record the frame register does not point at: locals first, then the record. */
    stack[3] = 0x7777;
    stack[6] = (uintptr_t)&stack[12];
    stack[7] = 0x1005;
    const uintptr_t low = (uintptr_t)stack;
    const uintptr_t high = (uintptr_t)(stack + 32);
    expect(ms_frames_scan_record(low, 0, low, high, is_source, is_native, NULL) == (uintptr_t)&stack[6], "found above sp");
    /* The register points at a record returning into native code: the walk ends. */
    stack[6] = (uintptr_t)&stack[12];
    stack[7] = 0x9009;
    stack[10] = (uintptr_t)&stack[14];
    stack[11] = 0x1005;
    expect(ms_frames_scan_record(low, (uintptr_t)&stack[6], low, high, is_source, is_native, NULL) == 0, "native caller ends it");
    expect(ms_frames_scan_record(low, 0, low, high, is_source, is_native, NULL) == (uintptr_t)&stack[10], "or the scan goes on");
}

/* ---- the record ---- */

static void test_record_encode(void) {
    MsFrameList frames = {0};
    frames.frames[0] = (MsFrame){.file = "a.ms", .function = "f", .line = 3, .repeated = 2};
    frames.count = 1;
    frames.truncated = true;
    uint8_t note_bytes[] = {'n'};
    const MsFaultNote notes[] = {{.bytes = note_bytes, .length = 1}};
    const MsFaultRecord record = {.pid = 7,
                                  .kind = MS_FAULT_KIND_OVERFLOW,
                                  .message = bytes_of("hi"),
                                  .frames = &frames,
                                  .notes = notes,
                                  .note_count = 1,
                                  .has_site = true,
                                  .site = bytes_of("s:1:2")};
    static const uint8_t expected[] = {
        'M', 'S', 'F', 'R', 1, /* magic, version */
        7, 0, 0, 0,            /* pid */
        5,                     /* kind: overflow */
        3,                     /* flags: truncated, has a site */
        2, 0, 0, 0, 'h', 'i',  /* message */
        1, 0, 0, 0,            /* one frame */
        4, 0, 0, 0, 'a', '.', 'm', 's', 3, 0, 0, 0, 1, 0, 0, 0, 'f', 2, 0, 0, 0,
        1, 0, 0, 0,            /* one cleanup fault */
        1, 0, 0, 0, 'n',
        5, 0, 0, 0, 's', ':', '1', ':', '2', /* the site */
    };
    uint8_t out[sizeof expected + 8] = {0};
    expect(ms_fault_record_encode(&record, NULL, 0) == sizeof expected, "the size is known without a buffer");
    expect(ms_fault_record_encode(&record, out, sizeof expected - 1) == sizeof expected, "a short buffer reports the size");
    expect(ms_fault_record_encode(&record, out, sizeof out) == sizeof expected, "the encoding has its size");
    expect(memcmp(out, expected, sizeof expected) == 0, "the bytes are the record format");
}

/* ---- the fault path ---- */

static char log_text[16];
static size_t log_length;
static bool drops_seen;

static void log_char(char c) {
    expect(log_length + 1 < sizeof log_text, "the log has room");
    log_text[log_length++] = c;
    log_text[log_length] = 0;
}

static void log_cleanup(uint8_t *argument) {
    log_char((char)(uintptr_t)argument);
    drops_seen = drops_seen || ms_unwind_drops();
}

static void faulting_cleanup(uint8_t *argument) {
    (void)argument;
    ms_fault(MS_FAULT_KIND_FAULT, bytes_of("second"));
}

static void fault_with_cleanups(void *argument) {
    (void)argument;
    (void)ms_cleanup_push(log_cleanup, (void *)(uintptr_t)'a');
    (void)ms_cleanup_push(faulting_cleanup, NULL);
    (void)ms_cleanup_push(log_cleanup, (void *)(uintptr_t)'b');
    ms_fault(MS_FAULT_KIND_FAULT, bytes_of("first"));
}

static void overflow(void *argument) {
    (void)argument;
    ms_fault(MS_FAULT_KIND_OVERFLOW, bytes_of("boom"));
}

static void out_of_memory(void *argument) {
    (void)argument;
    ms_fault_out_of_memory(4096);
}

static void test_guarded_fault(void) {
    MsFaultText text = {0};
    expect(ms_guard_call(overflow, NULL, &text) == MS_GUARD_FAULT, "a fault ends the guarded call");
    expect(text.length == 4 && memcmp(text.bytes, "boom", 4) == 0, "the report is the message");
    expect(text.detail != NULL && text.detail->kind == MS_FAULT_KIND_OVERFLOW && text.detail->message_length == 4,
           "the family and the message length travel with it");
    expect(text.detail->frames.count == 0, "no tables, no frames");
    ms_fault_text_free(&text);
    expect(text.bytes == NULL && text.detail == NULL, "freeing empties the report");
    expect(ms_task_running()->unwind.flight == NULL, "no fault is in progress afterwards");
}

static void test_cleanups_and_nested_fault(void) {
    log_length = 0;
    log_text[0] = 0;
    MsFaultText text = {0};
    expect(ms_guard_call(fault_with_cleanups, NULL, &text) == MS_GUARD_FAULT, "faulted");
    expect(strcmp(log_text, "ba") == 0, "cleanups run last in, first out, and a failing one does not stop the rest");
    expect(drops_seen, "drop cleanups act while a guarded task is being left");
    expect(!ms_unwind_drops(), "and stop acting after the guard");
    expect(text.length == strlen("first\ncleanup fault: second") &&
               memcmp(text.bytes, "first\ncleanup fault: second", text.length) == 0,
           "the cleanup's fault is part of the report");
    expect(text.detail->message_length == 5 && text.detail->note_count == 1 && text.detail->notes[0].length == 6,
           "and a note of the record");
    MsFaultText copy = ms_fault_text_clone(&text);
    ms_fault_text_free(&text);
    expect(copy.length == strlen("first\ncleanup fault: second") && copy.detail->note_count == 1 &&
               memcmp(copy.detail->notes[0].bytes, "second", 6) == 0,
           "a copy outlives the report it was made from");
    ms_fault_text_free(&copy);
}

static void test_out_of_memory_report(void) {
    for (int round = 0; round < 2; round++) {
        MsFaultText text = {0};
        expect(ms_guard_call(out_of_memory, NULL, &text) == MS_GUARD_FAULT, "faulted");
        static const char want[] = "out of memory: could not allocate 4096 bytes; hold less data at once, or process it in chunks or as a stream";
        expect(text.length == sizeof want - 1 && memcmp(text.bytes, want, text.length) == 0, "the size is in the message");
        expect(text.detail->kind == MS_FAULT_KIND_OUT_OF_MEMORY, "the family is out of memory");
        ms_fault_text_free(&text);
    }
}

__attribute__((noinline)) static void fault_at_site(void *argument) {
    (void)argument;
    ms_fault(MS_FAULT_KIND_FAULT, bytes_of("boom"));
}

static MsFuncEntry site_funcs[1];
static MsLineEntry site_lines[1];
static MsTables site_tables;

static void test_report_names_the_raising_frame(void) {
    const uint32_t file = blob_add("site.ms");
    const uint32_t name = blob_add("site");
    /* The table covers only the start of the function: the call to ms_fault is within it, its callers are not. */
    site_funcs[0] = (MsFuncEntry){.address = (uintptr_t)fault_at_site, .size = 64, .name_offset = name, .file_offset = file, .line = 40};
    site_lines[0] = (MsLineEntry){.pc = (uintptr_t)fault_at_site, .line = 42, .file_offset = UINT32_MAX};
    site_tables = (MsTables){.abi_version = MS_TABLES_WITH_SCOPES - 1,
                             .funcs = site_funcs,
                             .func_count = 1,
                             .lines = site_lines,
                             .line_count = 1,
                             .strings = (const uint8_t *)blob,
                             .strings_len = blob_length};
    expect(ms_frames_install(&site_tables), "tables install");
    MsFaultText text = {0};
    expect(ms_guard_call(fault_at_site, NULL, &text) == MS_GUARD_FAULT, "faulted");
    static const char want[] = "boom\n  at site.ms:42 in site";
    expect(text.length == sizeof want - 1 && memcmp(text.bytes, want, text.length) == 0, "the report names the frame");
    expect(text.detail->frames.count == 1 && text.detail->message_length == 4, "one frame, and the record's message is the text before it");

    /* The frames a task was started from are added under their own line. */
    const uintptr_t started[] = {(uintptr_t)fault_at_site + 8};
    ms_fault_text_add_started(&text, started, 1);
    static const char with_started[] = "boom\n  at site.ms:42 in site\n  task started by:\n  at site.ms:42 in site";
    expect(text.length == sizeof with_started - 1 && memcmp(text.bytes, with_started, text.length) == 0, "started frames follow");
    expect(text.detail->started.count == 1 && text.detail->message_length == 4, "the record keeps them apart");
    ms_fault_text_free(&text);

    uintptr_t captured[4] = {0};
    expect(ms_fault_capture_frames(captured, MS_COUNT_OF(captured)) >= 1, "frames can be captured to describe later");
    expect(ms_frames_install(&tables), "tables install");
}

/* ---- ending the process, in a child ---- */

static void exit_hook(int status) { _exit(status); }

static void flush_hook(void) { (void)!write(2, "[flushed]", 9); }

static void install_hooks(void) {
    const MsSchedHooks hooks = {.exit_process = exit_hook, .flush_output = flush_hook};
    const MsPollOps poll_ops = {0};
    ms_sched_set_hooks(&hooks, &poll_ops);
}

static size_t read_file(const char *path, uint8_t *out, size_t capacity) {
    const int fd = open(path, O_RDONLY);
    expect(fd >= 0, "the file exists");
    const ssize_t count = read(fd, out, capacity);
    close(fd);
    return count < 0 ? 0 : (size_t)count;
}

typedef void (*ChildBody)(void);

/* Runs `body` in a child whose standard error and record go to files, and checks its exit status. */
static void run_child(ChildBody body, int status, const char *want_error, uint8_t kind, const char *want_message) {
    char error_path[] = "/tmp/ms_fault_error_XXXXXX";
    char record_path[] = "/tmp/ms_fault_record_XXXXXX";
    const int error_fd = mkstemp(error_path);
    const int record_fd = mkstemp(record_path);
    expect(error_fd >= 0 && record_fd >= 0, "temporary files");
    close(record_fd);
    const pid_t child = fork();
    expect(child >= 0, "fork");
    if (child == 0) {
        dup2(error_fd, 2);
        setenv("MS_FAULT_RECORD", record_path, 1);
        body();
        _exit(99);
    }
    int wait_status = 0;
    expect(waitpid(child, &wait_status, 0) == child && WIFEXITED(wait_status), "the child ended normally");
    expect(WEXITSTATUS(wait_status) == status, "its exit status is the fault's");
    uint8_t text[4096] = {0};
    const size_t text_length = read_file(error_path, text, sizeof text - 1);
    expect(text_length == strlen(want_error) && memcmp(text, want_error, text_length) == 0, "standard error has the report");
    uint8_t record[4096] = {0};
    const size_t record_length = read_file(record_path, record, sizeof record);
    expect(record_length >= 15 && memcmp(record, "MSFR", 4) == 0 && record[4] == 1, "a record was written");
    uint32_t pid = 0;
    memcpy(&pid, record + 5, 4);
    expect(pid == (uint32_t)child, "it names the process that wrote it");
    expect(record[9] == kind, "and the family");
    const size_t message_length = strlen(want_message);
    expect(record_length >= 15 + message_length && memcmp(record + 15, want_message, message_length) == 0,
           "and the message");
    close(error_fd);
    unlink(error_path);
    unlink(record_path);
}

static void child_unguarded_fault(void) {
    install_hooks();
    ms_fault(MS_FAULT_KIND_INDEX_OUT_OF_RANGE, bytes_of("bad index"));
}

static void child_stack_overflow_status(void) {
    install_hooks();
    ms_fault(MS_FAULT_KIND_STACK_OVERFLOW, bytes_of("deep"));
}

static void child_fatal(void) {
    install_hooks();
    ms_fault_fatal(MS_FAULT_KIND_OUT_OF_MEMORY, bytes_of("out of memory"));
}

static void faulting_cleanup_in_oom(uint8_t *argument) {
    (void)argument;
    ms_fault_out_of_memory(8);
}

static void child_second_out_of_memory(void) {
    install_hooks();
    (void)ms_cleanup_push(faulting_cleanup_in_oom, NULL);
    ms_fault_out_of_memory(4096);
}

static void child_test_record(void) {
    ms_fault_record_write(MS_FAULT_KIND_TEST_FAILURE, bytes_of("expected 1"), true, bytes_of("t.ms:3:4"));
    _exit(1);
}

int main(void) {
    install_hooks();
    build_tables();
    test_find_function();
    test_describe();
    test_unsorted_tables();
    test_walk_chain();
    test_walk_across_segments();
    test_scan_record();
    test_record_encode();
    test_guarded_fault();
    test_cleanups_and_nested_fault();
    test_out_of_memory_report();
    test_report_names_the_raising_frame();
    run_child(child_unguarded_fault, MS_EXIT_ABORT, "[flushed]bad index\n", MS_FAULT_KIND_INDEX_OUT_OF_RANGE, "bad index");
    run_child(child_stack_overflow_status, MS_EXIT_STACK_OVERFLOW, "[flushed]deep\n", MS_FAULT_KIND_STACK_OVERFLOW, "deep");
    run_child(child_fatal, MS_EXIT_NO_MEMORY, "[flushed]out of memory\n", MS_FAULT_KIND_OUT_OF_MEMORY, "out of memory");
    run_child(child_second_out_of_memory, MS_EXIT_NO_MEMORY,
              "[flushed]out of memory: could not allocate 8 bytes; hold less data at once, or process it in chunks or as a stream\n",
              MS_FAULT_KIND_OUT_OF_MEMORY, "out of memory: could not allocate 8 bytes");
    run_child(child_test_record, MS_EXIT_TEST_FAILURE, "", MS_FAULT_KIND_TEST_FAILURE, "expected 1");
    ms_frames_release();
    puts("core_fault: ok");
    ms_sched_teardown();
    return 0;
}
