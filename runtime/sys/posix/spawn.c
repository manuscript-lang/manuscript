/* Running a program to completion on Linux and macOS: posix_spawnp with the standard streams on pipes that are drained
 * together, so a program that fills one cannot block on it. */
#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include "ms_rt/sys_process.h"

extern char **environ;

enum { PIPE_READ = 0, PIPE_WRITE = 1, CHUNK = 4096 };

typedef struct Sink {
    char *data;
    size_t length;
    size_t capacity;
    int fd;
} Sink;

static bool sink_append(Sink *sink, const char *bytes, size_t count) {
    if (sink->length + count + 1 > sink->capacity) {
        size_t capacity = sink->capacity == 0 ? CHUNK : sink->capacity;
        while (sink->length + count + 1 > capacity) {
            capacity *= 2;
        }
        char *grown = realloc(sink->data, capacity);
        if (grown == NULL) {
            return false;
        }
        sink->data = grown;
        sink->capacity = capacity;
    }
    memcpy(sink->data + sink->length, bytes, count);
    sink->length += count;
    sink->data[sink->length] = '\0';
    return true;
}

/* Reads every open sink until each closes. */
static MsSysError drain(Sink *sinks, size_t count) {
    struct pollfd fds[2];
    size_t open_count = 0;
    for (size_t i = 0; i < count; i++) {
        fds[i] = (struct pollfd){.fd = sinks[i].fd, .events = POLLIN};
        open_count += sinks[i].fd >= 0 ? 1u : 0u;
    }
    char chunk[CHUNK];
    while (open_count > 0) {
        if (poll(fds, (nfds_t)count, -1) < 0) {
            if (errno == EINTR) {
                continue;
            }
            return errno;
        }
        for (size_t i = 0; i < count; i++) {
            if (fds[i].fd < 0 || (fds[i].revents & (POLLIN | POLLHUP | POLLERR)) == 0) {
                continue;
            }
            const ssize_t n = read(fds[i].fd, chunk, sizeof chunk);
            if (n > 0) {
                if (!sink_append(&sinks[i], chunk, (size_t)n)) {
                    return ENOMEM;
                }
            } else if (n == 0 || errno != EINTR) {
                fds[i].fd = -1;
                open_count--;
            }
        }
    }
    return 0;
}

static void close_pair(int pair[2]) {
    for (int i = 0; i < 2; i++) {
        if (pair[i] >= 0) {
            (void)close(pair[i]);
        }
    }
}

static MsSysError make_pipe(int pair[2]) {
    pair[0] = pair[1] = -1;
#ifdef __linux__
    return pipe2(pair, O_CLOEXEC) == 0 ? 0 : errno;
#else
    if (pipe(pair) != 0) {
        return errno;
    }
    for (int i = 0; i < 2; i++) {
        (void)fcntl(pair[i], F_SETFD, FD_CLOEXEC);
    }
    return 0;
#endif
}

/* This process's environment with `overrides` replacing or adding their names; malloc'd, as one array. */
static char **merged_environment(char *const *overrides) {
    size_t have = 0, extra = 0;
    while (environ[have] != NULL) {
        have++;
    }
    while (overrides != NULL && overrides[extra] != NULL) {
        extra++;
    }
    char **merged = malloc((have + extra + 1) * sizeof *merged);
    if (merged == NULL) {
        return NULL;
    }
    size_t used = 0;
    for (size_t i = 0; i < have; i++) {
        const char *equals = strchr(environ[i], '=');
        const size_t name = equals != NULL ? (size_t)(equals - environ[i]) : strlen(environ[i]);
        bool replaced = false;
        for (size_t k = 0; k < extra && !replaced; k++) {
            replaced = strncmp(overrides[k], environ[i], name) == 0 && overrides[k][name] == '=';
        }
        if (!replaced) {
            merged[used++] = environ[i];
        }
    }
    for (size_t k = 0; k < extra; k++) {
        merged[used++] = overrides[k];
    }
    merged[used] = NULL;
    return merged;
}

MsSysError ms_sys_process_run(char *const *argv, char *const *env, const char *cwd, bool merge, MsSysRun *run) {
    *run = (MsSysRun){.code = -1};
    int out_pipe[2], err_pipe[2];
    MsSysError failure = make_pipe(out_pipe);
    if (failure == 0 && !merge) {
        failure = make_pipe(err_pipe);
    } else {
        err_pipe[0] = err_pipe[1] = -1;
    }
    if (failure != 0) {
        close_pair(out_pipe);
        close_pair(err_pipe);
        return failure;
    }
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_adddup2(&actions, out_pipe[PIPE_WRITE], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, merge ? out_pipe[PIPE_WRITE] : err_pipe[PIPE_WRITE], STDERR_FILENO);
    if (cwd != NULL) {
#ifdef __APPLE__
        posix_spawn_file_actions_addchdir_np(&actions, cwd);
#elif defined(__GLIBC__) && (__GLIBC__ > 2 || __GLIBC_MINOR__ >= 29)
        posix_spawn_file_actions_addchdir_np(&actions, cwd);
#else
        posix_spawn_file_actions_destroy(&actions);
        close_pair(out_pipe);
        close_pair(err_pipe);
        return ms_sys_fs_error_of(MS_SYS_ERR_UNSUPPORTED);
#endif
    }
    pid_t pid = 0;
    char **environment = merged_environment(env);
    const int spawned = environment == NULL ? ENOMEM : posix_spawnp(&pid, argv[0], &actions, NULL, argv, environment);
    free(environment);
    posix_spawn_file_actions_destroy(&actions);
    (void)close(out_pipe[PIPE_WRITE]);
    if (err_pipe[PIPE_WRITE] >= 0) {
        (void)close(err_pipe[PIPE_WRITE]);
    }
    if (spawned != 0) {
        (void)close(out_pipe[PIPE_READ]);
        if (err_pipe[PIPE_READ] >= 0) {
            (void)close(err_pipe[PIPE_READ]);
        }
        return spawned;
    }
    Sink sinks[2] = {{.fd = out_pipe[PIPE_READ]}, {.fd = err_pipe[PIPE_READ]}};
    failure = drain(sinks, merge ? 1 : 2);
    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
    }
    (void)close(out_pipe[PIPE_READ]);
    if (err_pipe[PIPE_READ] >= 0) {
        (void)close(err_pipe[PIPE_READ]);
    }
    if (failure != 0) {
        free(sinks[0].data);
        free(sinks[1].data);
        return failure;
    }
    run->code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    run->out = sinks[0].data != NULL ? sinks[0].data : calloc(1, 1);
    run->out_length = sinks[0].length;
    if (!merge) {
        run->err = sinks[1].data != NULL ? sinks[1].data : calloc(1, 1);
        run->err_length = sinks[1].length;
    }
    return 0;
}

void ms_sys_process_run_free(MsSysRun *run) {
    free(run->out);
    free(run->err);
    *run = (MsSysRun){.code = -1};
}
