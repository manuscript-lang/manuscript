/* Helpers of the build steps (ms/build_tool.h): files and the tools they run. */
#include "ms/build_tool.h"

#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

bool ms_build_read(const char *path, MsBuf *out) {
    FILE *file = fopen(path, "rb");
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
    FILE *file = fopen(path, "wb");
    if (file == NULL) {
        return false;
    }
    const bool ok = len == 0 || fwrite(bytes, 1, len, file) == len;
    return fclose(file) == 0 && ok;
}

bool ms_build_run(const char *what, char *const *argv, const char *log, MsBuf *output) {
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, log, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO);
    pid_t pid = 0;
    const int spawned = posix_spawn(&pid, argv[0], &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    if (spawned != 0) {
        ms_buf_printf(output, "cannot run %s: %s", what, strerror(spawned));
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
