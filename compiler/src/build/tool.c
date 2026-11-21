/* Helpers of the build steps (ms/build_tool.h): files and the tools they run. */
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L /* strerror_r; libms.c defines it first for the whole unit */
#endif
#include "ms/build_tool.h"

#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

bool ms_build_read(const char *path, MsBuf *out) {
    FILE *file = fopen(path, "rbe");
    if (file == NULL) {
        return false;
    }
    char chunk[16384];
    size_t n;
    while ((n = fread(chunk, 1, sizeof chunk, file)) > 0) {
        ms_buf_put(out, chunk, n);
    }
    const bool ok = ferror(file) == 0;
    (void)fclose(file);
    return ok;
}

bool ms_build_write(const char *path, const void *bytes, size_t len) {
    FILE *file = fopen(path, "wbe");
    if (file == NULL) {
        return false;
    }
    const bool ok = len == 0 || fwrite(bytes, 1, len, file) == len;
    return fclose(file) == 0 && ok;
}

void ms_build_put_errno(MsBuf *out, int err_no) {
    char message[128] = "unknown error";
    if (strerror_r(err_no, message, sizeof message) != 0) {
        (void)snprintf(message, sizeof message, "errno %d", err_no);
    }
    ms_buf_puts(out, message);
}

/* `posix_spawn` takes mutable strings, so the arguments are copied rather than cast. */
static char **bt_copy_argv(const char *const *argv, MsBuf *strings, MsBuf *pointers) {
    size_t n = 0;
    while (argv[n] != NULL) {
        ms_buf_puts(strings, argv[n]);
        ms_buf_putc(strings, 0);
        n++;
    }
    char *at = strings->data;
    for (size_t i = 0; i < n; i++) {
        MS_VEC_PUSH(*pointers, char *, at);
        at += strlen(at) + 1;
    }
    MS_VEC_PUSH(*pointers, char *, NULL);
    return ms_buf_items(pointers);
}

bool ms_build_run(const char *what, const char *const *argv, const char *log, MsBuf *output) {
    MsBuf strings = {0}, pointers = {0};
    char **mutable_argv = bt_copy_argv(argv, &strings, &pointers);
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, log, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO);
    pid_t pid = 0;
    const int spawned = posix_spawn(&pid, mutable_argv[0], &actions, NULL, mutable_argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    ms_buf_free(&strings);
    ms_buf_free(&pointers);
    if (spawned != 0) {
        ms_buf_printf(output, "cannot run %s: ", what);
        ms_build_put_errno(output, spawned);
        return false;
    }
    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
    }
    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
        return true;
    }
    ms_buf_printf(output, "%s failed: ", what);
    MsBuf text = {0};
    (void)ms_build_read(log, &text);
    size_t end = text.len;
    while (end > 0 && (text.data[end - 1] == '\n' || text.data[end - 1] == '\r' || text.data[end - 1] == ' ')) {
        end--;
    }
    ms_buf_put(output, text.data, end);
    ms_buf_free(&text);
    return false;
}
