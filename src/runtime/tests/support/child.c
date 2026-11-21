#ifdef _WIN32
#include <windows.h>
#else
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#endif

#include <stdlib.h>
#include <string.h>

#include "child.h"

#ifndef _WIN32
extern char **environ;
#endif

struct MsTestChild {
#ifdef _WIN32
    HANDLE process;
    DWORD id;
#else
    pid_t id;
#endif
};

#ifdef _WIN32

/* The command line CreateProcess takes: every argument quoted. The test arguments hold no quotes. */
static char *command_line(char *const *argv) {
    size_t size = 1;
    for (size_t i = 0; argv[i] != NULL; i++) {
        size += strlen(argv[i]) + 3;
    }
    char *line = calloc(size, 1);
    size_t used = 0;
    for (size_t i = 0; line != NULL && argv[i] != NULL; i++) {
        const size_t length = strlen(argv[i]);
        if (i > 0) {
            line[used++] = ' ';
        }
        line[used++] = '"';
        memcpy(line + used, argv[i], length);
        used += length;
        line[used++] = '"';
    }
    return line;
}

MsTestChild *ms_test_child_start(const char *program, char *const *argv) {
    char *line = command_line(argv);
    MsTestChild *child = calloc(1, sizeof *child);
    STARTUPINFOA startup = {.cb = sizeof startup};
    PROCESS_INFORMATION info = {0};
    if (line == NULL || child == NULL ||
        !CreateProcessA(program, line, NULL, NULL, TRUE, CREATE_NEW_PROCESS_GROUP, NULL, NULL, &startup, &info)) {
        free(line);
        free(child);
        return NULL;
    }
    free(line);
    (void)CloseHandle(info.hThread);
    child->process = info.hProcess;
    child->id = info.dwProcessId;
    return child;
}

bool ms_test_child_interrupt(MsTestChild *child) { return GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, child->id) != 0; }

bool ms_test_child_terminate(MsTestChild *child) {
    (void)child;
    return false;
}

int ms_test_child_wait(MsTestChild *child, int seconds) {
    int status = -1;
    if (WaitForSingleObject(child->process, (DWORD)seconds * 1000) == WAIT_OBJECT_0) {
        DWORD code = 0;
        status = GetExitCodeProcess(child->process, &code) ? (int)code : -1;
    } else {
        (void)TerminateProcess(child->process, 1);
    }
    (void)CloseHandle(child->process);
    free(child);
    return status;
}

#else

MsTestChild *ms_test_child_start(const char *program, char *const *argv) {
    MsTestChild *child = calloc(1, sizeof *child);
    if (child == NULL) {
        return NULL;
    }
    posix_spawnattr_t attributes;
    (void)posix_spawnattr_init(&attributes);
    (void)posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETPGROUP);
    (void)posix_spawnattr_setpgroup(&attributes, 0);
    const int started = posix_spawn(&child->id, program, NULL, &attributes, argv, environ);
    (void)posix_spawnattr_destroy(&attributes);
    if (started != 0) {
        free(child);
        return NULL;
    }
    return child;
}

bool ms_test_child_interrupt(MsTestChild *child) { return kill(child->id, SIGINT) == 0; }

bool ms_test_child_terminate(MsTestChild *child) { return kill(child->id, SIGTERM) == 0; }

int ms_test_child_wait(MsTestChild *child, int seconds) {
    int status = 0;
    int result = -1;
    for (int waited = 0; waited < seconds * 100; waited++) {
        const pid_t done = waitpid(child->id, &status, WNOHANG);
        if (done == child->id) {
            result = WIFEXITED(status) ? WEXITSTATUS(status) : 1000 + WTERMSIG(status);
            break;
        }
        const struct timespec tick = {0, 10 * 1000 * 1000};
        (void)nanosleep(&tick, NULL);
    }
    if (result < 0) {
        (void)kill(child->id, SIGKILL);
        (void)waitpid(child->id, &status, 0);
    }
    free(child);
    return result;
}

#endif
