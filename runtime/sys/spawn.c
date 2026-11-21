/* Running a program to completion, on every platform, over libuv: uv_spawn with the standard streams on pipes, driven
 * by a private loop until the program has exited and both pipes have closed. A merged run reads both pipes into one buffer, in the order the data arrives (ms_rt/sys_process.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c11 */
#ifdef __APPLE__
#define _DARWIN_C_SOURCE
#endif

#include <stdlib.h>
#include <string.h>
#include <uv.h>

#include "ms_rt/sys_process.h"

typedef struct Buffer {
    char *data;
    size_t length;
    size_t capacity;
    bool failed;
} Buffer;

/* One pipe and the buffer it fills; a merged run points both pipes at one buffer. */
typedef struct Sink {
    uv_pipe_t pipe;
    Buffer *into;
} Sink;

typedef struct Run {
    int32_t code;
    bool exited;
} Run;

static void on_alloc(uv_handle_t *handle, size_t suggested, uv_buf_t *buffer) {
    (void)handle;
    char *memory = malloc(suggested);
    *buffer = uv_buf_init(memory, memory == NULL ? 0 : (unsigned int)suggested);
}

static void on_close(uv_handle_t *handle) { (void)handle; }

static void on_read(uv_stream_t *stream, ssize_t count, const uv_buf_t *buffer) {
    Buffer *into = ((Sink *)stream)->into;
    if (count > 0) {
        const size_t needed = into->length + (size_t)count + 1;
        if (needed > into->capacity) {
            size_t capacity = into->capacity == 0 ? 4096 : into->capacity;
            while (needed > capacity) {
                capacity *= 2;
            }
            char *grown = realloc(into->data, capacity);
            if (grown == NULL) {
                into->failed = true;
            } else {
                into->data = grown;
                into->capacity = capacity;
            }
        }
        if (!into->failed) {
            memcpy(into->data + into->length, buffer->base, (size_t)count);
            into->length += (size_t)count;
            into->data[into->length] = '\0';
        }
    } else if (count < 0) {
        if (count != UV_EOF) {
            into->failed = true;
        }
        uv_close((uv_handle_t *)stream, on_close);
    }
    free(buffer->base);
}

static void on_process_exit(uv_process_t *process, int64_t status, int signal) {
    Run *run = process->data;
    run->code = signal != 0 ? -1 : (int32_t)status;
    run->exited = true;
    uv_close((uv_handle_t *)process, on_close);
}

static bool same_name(const char *left, const char *right, size_t length) {
#ifdef _WIN32
    return _strnicmp(left, right, length) == 0; /* environment names ignore case on Windows */
#else
    return strncmp(left, right, length) == 0;
#endif
}

/* This process's environment with `overrides` replacing or adding their names, as one malloc'd array whose strings
 * are malloc'd too (free with free_environment). */
static char **merged_environment(char *const *overrides) {
    uv_env_item_t *items = NULL;
    int have = 0;
    if (uv_os_environ(&items, &have) != 0) {
        return NULL;
    }
    size_t extra = 0;
    while (overrides != NULL && overrides[extra] != NULL) {
        extra++;
    }
    char **merged = calloc((size_t)have + extra + 1, sizeof *merged);
    size_t used = 0;
    for (int i = 0; merged != NULL && i < have; i++) {
        const size_t name = strlen(items[i].name);
        bool replaced = false;
        for (size_t k = 0; k < extra && !replaced; k++) {
            replaced = same_name(overrides[k], items[i].name, name) && overrides[k][name] == '=';
        }
        if (replaced) {
            continue;
        }
        const size_t value = strlen(items[i].value);
        char *entry = malloc(name + value + 2);
        if (entry == NULL) {
            break;
        }
        memcpy(entry, items[i].name, name);
        entry[name] = '=';
        memcpy(entry + name + 1, items[i].value, value + 1);
        merged[used++] = entry;
    }
    uv_os_free_environ(items, have);
    for (size_t k = 0; merged != NULL && k < extra; k++) {
        merged[used++] = strdup(overrides[k]);
    }
    return merged;
}

static void free_environment(char **environment) {
    for (size_t i = 0; environment != NULL && environment[i] != NULL; i++) {
        free(environment[i]);
    }
    free(environment);
}

static MsSysError host_error(int result) {
    switch (result) {
    case UV_ENOENT: return ms_sys_fs_error_of(MS_SYS_ERR_NOT_FOUND);
    case UV_EACCES:
    case UV_EPERM: return ms_sys_fs_error_of(MS_SYS_ERR_PERMISSION);
    case UV_EINVAL: return ms_sys_fs_error_of(MS_SYS_ERR_INVALID);
    default: return ms_sys_fs_error_of(MS_SYS_ERR_IO);
    }
}

MsSysError ms_sys_process_run(char **argv, char *const *env, const char *cwd, bool merge, MsSysRun *run) {
    *run = (MsSysRun){.code = -1};
    uv_loop_t loop;
    int result = uv_loop_init(&loop);
    if (result != 0) {
        return host_error(result);
    }
    Buffer out_text = {0}, err_text = {0};
    Sink out = {.into = &out_text}, err = {.into = merge ? &out_text : &err_text};
    Run state = {0};
    uv_process_t process = {.data = &state};
    char **environment = merged_environment(env);
    if (environment == NULL) {
        (void)uv_loop_close(&loop);
        return ms_sys_fs_error_of(MS_SYS_ERR_IO);
    }
    (void)uv_pipe_init(&loop, &out.pipe, 0);
    (void)uv_pipe_init(&loop, &err.pipe, 0);
    uv_stdio_container_t stdio[3];
    stdio[0].flags = UV_IGNORE;
    stdio[1].flags = (uv_stdio_flags)(UV_CREATE_PIPE | UV_WRITABLE_PIPE);
    stdio[1].data.stream = (uv_stream_t *)&out.pipe;
    stdio[2].flags = (uv_stdio_flags)(UV_CREATE_PIPE | UV_WRITABLE_PIPE);
    stdio[2].data.stream = (uv_stream_t *)&err.pipe;
    uv_process_options_t options = {.exit_cb = on_process_exit, .file = argv[0], .args = argv, .env = environment, .cwd = cwd,
                                    .stdio_count = 3, .stdio = stdio};
    result = uv_spawn(&loop, &process, &options);
    free_environment(environment);
    if (result == 0) {
        (void)uv_read_start((uv_stream_t *)&out.pipe, on_alloc, on_read);
        (void)uv_read_start((uv_stream_t *)&err.pipe, on_alloc, on_read);
    } else {
        uv_close((uv_handle_t *)&out.pipe, on_close);
        uv_close((uv_handle_t *)&err.pipe, on_close);
    }
    (void)uv_run(&loop, UV_RUN_DEFAULT);
    (void)uv_loop_close(&loop);
    if (result != 0) {
        return host_error(result);
    }
    if (out_text.failed || err_text.failed) {
        free(out_text.data);
        free(err_text.data);
        return ms_sys_fs_error_of(MS_SYS_ERR_IO);
    }
    run->code = state.code;
    run->out = out_text.data != NULL ? out_text.data : calloc(1, 1);
    run->out_length = out_text.length;
    if (!merge) {
        run->err = err_text.data != NULL ? err_text.data : calloc(1, 1);
        run->err_length = err_text.length;
    }
    return 0;
}

void ms_sys_process_run_free(MsSysRun *run) {
    free(run->out);
    free(run->err);
    *run = (MsSysRun){.code = -1};
}
