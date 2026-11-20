/* The child-process natives (runtime/std/process_spawn.c) against real children: `sh`, `cat` and `sleep`. */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "../std/abi.h"
#include "fake_rt.h"
#include "ms_rt/process.h"

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static MsStr text(const char *value) {
    MsStr out;
    msrt_string_from_bytes((const uint8_t *)value, strlen(value), &out);
    return out;
}

/* A list of strings; `count` of them. */
static MsVec strings(const char *const *values, size_t count) {
    MsStr *items = calloc(count + 1, sizeof *items);
    for (size_t i = 0; i < count; i++) {
        items[i] = text(values[i]);
    }
    return (MsVec){.ptr = items, .len = count, .cap = count};
}

static void strings_free(MsVec *list) {
    for (size_t i = 0; i < list->len; i++) {
        msrt_string_free((const MsStr *)list->ptr + i);
    }
    free(list->ptr);
}

static int64_t now_ms(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

/* What one `run` of `sh -c script` returned. */
typedef struct Ran {
    uint8_t status;
    MsCommandOut out;
} Ran;

typedef struct RunSpec {
    const char *script;
    const char *input;
    int64_t max_output;
    int64_t timeout_ns; /* negative: none */
    const char *cwd;
    const char *env_name;
    const char *env_value;
} RunSpec;

static Ran run_sh(const RunSpec *spec) {
    const char *argv[] = {"-c", spec->script};
    MsStr program = text("sh");
    MsStr cwd = text(spec->cwd != NULL ? spec->cwd : "");
    MsVec arguments = strings(argv, 2);
    MsVec names = strings(&spec->env_name, spec->env_name != NULL ? 1 : 0);
    MsVec values = strings(&spec->env_value, spec->env_name != NULL ? 1 : 0);
    MsVec input = {.ptr = (void *)(uintptr_t)spec->input, .len = spec->input != NULL ? strlen(spec->input) : 0};
    Ran ran = {0};
    MsStr err = {0};
    ran.status = msstd_process_command_run(&program, &arguments, &input, spec->max_output >= 0, spec->max_output,
                                           spec->timeout_ns >= 0, spec->timeout_ns, spec->cwd != NULL, &cwd, &names,
                                           &values, &ran.out, &err);
    strings_free(&arguments);
    strings_free(&names);
    strings_free(&values);
    msrt_string_free(&program);
    msrt_string_free(&cwd);
    msrt_string_free(&err);
    return ran;
}

static int same(const MsVec *bytes, const char *want) {
    return bytes->len == strlen(want) && (bytes->len == 0 || memcmp(bytes->ptr, want, bytes->len) == 0);
}

static void run_captures_output_and_exit_codes(void) {
    RunSpec spec = {.script = "cat; echo err >&2; exit 3", .input = "hello", .max_output = -1, .timeout_ns = -1};
    Ran ran = run_sh(&spec);
    CHECK(ran.status == STATUS_OK);
    CHECK(ran.out.exit_code == 3);
    CHECK(same(&ran.out.out, "hello"));
    CHECK(same(&ran.out.err, "err\n"));
    CHECK(ran.out.max_resident_bytes > 0);
    free(ran.out.out.ptr);
    free(ran.out.err.ptr);
    spec = (RunSpec){.script = "kill -9 $$", .max_output = -1, .timeout_ns = -1};
    ran = run_sh(&spec);
#ifdef _WIN32
    CHECK(ran.status == STATUS_OK && ran.out.exit_code != 0); /* the shell reports a status, not a signal (#4888) */
#else
    CHECK(ran.status == STATUS_OK && ran.out.exit_code == -1);
#endif
}

static void run_names_a_missing_program(void) {
    MsStr program = text("definitely-not-a-program");
    MsVec none = {0};
    MsCommandOut out = {0};
    MsStr err = {0};
    const uint8_t status = msstd_process_command_run(&program, &none, &none, 0, 0, 0, 0, 0, &program, &none, &none, &out, &err);
    CHECK(status == STATUS_NOT_FOUND);
    msrt_string_free(&program);
    msrt_string_free(&err);
}

static void run_limits_and_timeouts_kill_the_group(void) {
    RunSpec big = {.script = "yes | head -c 100000", .max_output = 1000, .timeout_ns = -1};
    CHECK(run_sh(&big).status == STATUS_OUTPUT_LIMIT);
    const int64_t start = now_ms();
    RunSpec slow = {.script = "sleep 30 & sleep 30", .max_output = -1, .timeout_ns = 100000000};
    CHECK(run_sh(&slow).status == STATUS_TIMED_OUT);
    CHECK(now_ms() - start < 5000);
    RunSpec background = {.script = "sleep 3 &", .max_output = -1, .timeout_ns = -1};
    CHECK(run_sh(&background).status == STATUS_FAILED);
}

static void run_applies_directory_and_environment(void) {
#ifdef _WIN32 /* the shell prints POSIX-style directories; the working directory is not checked here (#4888) */
    RunSpec spec = {.script = "echo \"$MS_PROBE\"", .max_output = -1, .timeout_ns = -1,
                    .env_name = "MS_PROBE", .env_value = "set"};
#else
    RunSpec spec = {.script = "pwd -P; echo \"$MS_PROBE\"", .max_output = -1, .timeout_ns = -1, .cwd = "/",
                    .env_name = "MS_PROBE", .env_value = "set"};
#endif
    Ran ran = run_sh(&spec);
    CHECK(ran.status == STATUS_OK);
#ifdef _WIN32
    CHECK(same(&ran.out.out, "set\n"));
#else
    CHECK(same(&ran.out.out, "/\nset\n"));
#endif
    free(ran.out.out.ptr);
    free(ran.out.err.ptr);
    spec = (RunSpec){.script = "true", .max_output = -1, .timeout_ns = -1, .cwd = "/definitely/not/here"};
    CHECK(run_sh(&spec).status == STATUS_NOT_FOUND);
}

/* `spawn` of `program` with its arguments; the handle goes to `*child`. */
static uint8_t spawn(const char *program_name, const char *const *argv, size_t count, int64_t modes[3], MsObj **child) {
    MsStr program = text(program_name);
    MsVec arguments = strings(argv, count);
    MsVec none = {0};
    MsStr cwd = {0};
    MsStr err = {0};
    const uint8_t status = msstd_process_command_spawn(&program, &arguments, modes[0], modes[1], modes[2], 0, &cwd, &none, &none, child, &err);
    strings_free(&arguments);
    msrt_string_free(&program);
    msrt_string_free(&err);
    return status;
}

static uint8_t wait_for(MsObj *child, int64_t timeout_ns, int64_t *code) {
    MsStr err = {0};
    const uint8_t status = msstd_process_subprocess_wait(child, 1, timeout_ns, code, &err);
    msrt_string_free(&err);
    return status;
}

static void subprocess_pipes_and_close(void) {
    int64_t modes[3] = {0, 0, 0};
    MsObj *child = NULL;
    CHECK(spawn("cat", NULL, 0, modes, &child) == STATUS_OK);
    int64_t code = 0;
    CHECK(wait_for(child, 20000000, &code) == STATUS_TIMED_OUT);
    const int in = (int)msstd_process_subprocess_stream_id(child, 0);
    const int out = (int)msstd_process_subprocess_stream_id(child, 1);
    CHECK(in >= 0 && out >= 0);
    CHECK(write(in, "ping", 4) == 4);
    close(in);
    CHECK(wait_for(child, 5000000000LL, &code) == STATUS_OK && code == 0);
    char buffer[8];
    CHECK(read(out, buffer, sizeof buffer) == 4 && memcmp(buffer, "ping", 4) == 0);
    close(out);
    CHECK(msstd_process_subprocess_pid(child) > 0);
    CHECK(msstd_process_subprocess_max_resident(child) > 0);
    msstd_process_subprocess_close(child);
    child->drop(child);
}

static void subprocess_terminate_and_discard(void) {
    const char *argv[] = {"30"};
    int64_t modes[3] = {2, 2, 2};
    MsObj *sleeper = NULL;
    CHECK(spawn("sleep", argv, 1, modes, &sleeper) == STATUS_OK);
    int64_t code = 0;
    CHECK(msstd_process_subprocess_stream_id(sleeper, 0) == -1);
    msstd_process_subprocess_terminate(sleeper);
    CHECK(wait_for(sleeper, 5000000000LL, &code) == STATUS_OK && code == -1);
    sleeper->drop(sleeper);
    MsObj *missing = NULL;
    CHECK(spawn("definitely-not-a-program", NULL, 0, modes, &missing) == STATUS_NOT_FOUND);
}

static void replace_rejects_empty_arguments(void) {
    MsStr program = text("true");
    MsVec none = {0};
    MsStr err = {0};
    CHECK(msstd_process_replace(&program, &none, &none, &none, &err) == STATUS_INVALID_INPUT);
    msrt_string_free(&program);
    msrt_string_free(&err);
}

int main(void) {
    run_captures_output_and_exit_codes();
    run_names_a_missing_program();
    run_limits_and_timeouts_kill_the_group();
    run_applies_directory_and_environment();
    subprocess_pipes_and_close();
    subprocess_terminate_and_discard();
    replace_rejects_empty_arguments();
    printf(failures == 0 ? "std_process: ok\n" : "std_process: %d failures\n", failures);
    return failures == 0 ? 0 : 1;
}
