/* Child processes and directories of the build steps on POSIX hosts (ms/build_tool.h). */
#include "ms/build_tool.h"

#if !defined(_WIN32)

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

void ms_build_errno_text(int err_no, MsBuf *out) {
    char message[128] = "unknown error";
    if (strerror_r(err_no, message, sizeof message) != 0) {
        (void)snprintf(message, sizeof message, "errno %d", err_no);
    }
    ms_buf_puts(out, message);
}

bool ms_build_run(const char *what, const char *const *argv, const char *log, MsBuf *output) {
    return ms_build_run_in(what, argv, NULL, log, output);
}

bool ms_build_run_in(const char *what, const char *const *argv, const char *cwd, const char *log, MsBuf *output) {
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    if (cwd != NULL) {
#ifdef __APPLE__
        posix_spawn_file_actions_addchdir_np(&actions, cwd);
#else
        (void)cwd; /* only the macOS link runs a tool elsewhere */
#endif
    }
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, log, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO);
    pid_t pid = 0;
    const int spawned = posix_spawnp(&pid, argv[0], &actions, NULL, (char *const *)argv, environ) /* NOLINT(cppcoreguidelines-pro-type-const-cast) */;
    posix_spawn_file_actions_destroy(&actions);
    if (spawned != 0) {
        ms_buf_printf(output, "cannot run %s: ", what);
        ms_build_errno_text(spawned, output);
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

bool ms_build_have(const char *name) {
    // NOLINTNEXTLINE(concurrency-mt-unsafe): read before any thread starts.
    const char *path = getenv("PATH");
    const size_t length = strlen(name);
    while (path != NULL && *path != 0) {
        const char *end = strchr(path, ':');
        const size_t n = end != NULL ? (size_t)(end - path) : strlen(path);
        MsBuf candidate = {0};
        ms_buf_printf(&candidate, "%.*s/%s", (int)(n == 0 ? 1 : n), n == 0 ? "." : path, name);
        ms_buf_putc(&candidate, 0);
        const bool found = access(candidate.data, X_OK) == 0;
        ms_buf_free(&candidate);
        if (found && length > 0) {
            return true;
        }
        path = end != NULL ? end + 1 : NULL;
    }
    return false;
}

bool ms_build_make_dir(char *pattern) { return mkdtemp(pattern) != NULL; }

void ms_build_unlink(const char *path) {
    if (unlink(path) != 0) {
        (void)rmdir(path);
    }
}

void ms_build_remove_tree(const char *path) {
    DIR *dir = opendir(path);
    if (dir != NULL) {
        for (const struct dirent *entry = readdir(dir); entry != NULL; entry = readdir(dir)) {
            if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
                continue;
            }
            MsBuf child = {0};
            ms_buf_printf(&child, "%s/%s", path, entry->d_name);
            ms_buf_putc(&child, 0);
            struct stat st;
            if (lstat(child.data, &st) == 0 && S_ISDIR(st.st_mode)) {
                ms_build_remove_tree(child.data);
            } else {
                (void)unlink(child.data);
            }
            ms_buf_free(&child);
        }
        (void)closedir(dir);
    }
    (void)rmdir(path);
}

bool ms_build_make_path(const char *path) {
    char partial[4096];
    const size_t length = strlen(path);
    if (length >= sizeof partial) {
        return false;
    }
    memcpy(partial, path, length + 1);
    for (size_t i = 1; i <= length; i++) {
        if (partial[i] != '/' && partial[i] != 0) {
            continue;
        }
        const char saved = partial[i];
        partial[i] = 0;
        if (mkdir(partial, 0777) != 0 && errno != EEXIST) {
            return false;
        }
        partial[i] = saved;
    }
    return true;
}

#endif
