/* The driver: picks, per command, between running in C and handing the command to the Rust ms. */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <process.h>
#else
#include <unistd.h>
#include <sys/wait.h>
#endif

#include "ms/driver.h"

#define B(s) (1u << (s))
#define BUILD (B(MS_STAGE_PARSE) | B(MS_STAGE_CHECK) | B(MS_STAGE_LOWER) | B(MS_STAGE_EMIT) | B(MS_STAGE_LINK) | B(MS_STAGE_TOOL))

/* Stages each command needs. A command not listed needs only its own logic (MS_STAGE_TOOL). */
static const struct {
    const char *name;
    unsigned stages;
} commands[] = {
    {"build", BUILD},
    {"run", BUILD},
    {"test", BUILD},
    {"profile", BUILD},
    {"check", B(MS_STAGE_PARSE) | B(MS_STAGE_CHECK) | B(MS_STAGE_TOOL)},
    {"lint", B(MS_STAGE_PARSE) | B(MS_STAGE_CHECK) | B(MS_STAGE_TOOL)},
    {"fmt", B(MS_STAGE_PARSE) | B(MS_STAGE_FORMAT) | B(MS_STAGE_TOOL)},
    {"lsp", B(MS_STAGE_PARSE) | B(MS_STAGE_CHECK) | B(MS_STAGE_TOOL)},
    {"review", BUILD},
    {"verify", BUILD},
    {"help", B(MS_STAGE_TOOL)},
    {"version", B(MS_STAGE_TOOL)},
    {"--version", B(MS_STAGE_TOOL)},
    {"--help", B(MS_STAGE_TOOL)},
    {"-h", B(MS_STAGE_TOOL)},
    {"init", B(MS_STAGE_TOOL)},
    {"install", B(MS_STAGE_TOOL)},
    {"add", B(MS_STAGE_TOOL)},
    {"remove", B(MS_STAGE_TOOL)},
    {"explain", B(MS_STAGE_TOOL)},
    {"search_symbol", B(MS_STAGE_CHECK) | B(MS_STAGE_TOOL)},
};

unsigned ms_command_stages(const char *command) {
    for (size_t i = 0; i < sizeof commands / sizeof commands[0]; i++) {
        if (strcmp(commands[i].name, command) == 0) {
            return commands[i].stages;
        }
    }
    return 0;
}

bool ms_command_in_c(const char *command) {
    unsigned stages = ms_command_stages(command);
    if (stages == 0) {
        return false;
    }
    for (int s = 0; s < MS_STAGE_COUNT; s++) {
        if ((stages & B(s)) != 0 && ms_stage_impl((MsStage)s) != MS_IMPL_C) {
            return false;
        }
    }
    return true;
}

static char *rust_cli(const char *argv0) {
    const char *env = getenv("MS_RUST_CLI");
    if (env != NULL && *env != '\0') {
        return strdup(env);
    }
    const char *slash = strrchr(argv0, '/');
#ifdef _WIN32
    const char *back = strrchr(argv0, '\\');
    if (back != NULL && (slash == NULL || back > slash)) {
        slash = back;
    }
    const char *suffix = "ms-rust.exe";
#else
    const char *suffix = "ms-rust";
#endif
    size_t dir = slash == NULL ? 0 : (size_t)(slash - argv0) + 1;
    char *path = malloc(dir + strlen(suffix) + 1);
    memcpy(path, argv0, dir);
    strcpy(path + dir, suffix);
    return path;
}

static int hand_to_rust(const char *cli, char **argv) {
    argv[0] = (char *)cli;
#ifdef _WIN32
    intptr_t status = _spawnv(_P_WAIT, cli, (const char *const *)argv);
    if (status == -1) {
        fprintf(stderr, "ms: cannot run %s\n", cli);
        return 70;
    }
    return (int)status;
#else
    pid_t pid = fork();
    if (pid < 0) {
        fprintf(stderr, "ms: cannot start %s\n", cli);
        return 70;
    }
    if (pid == 0) {
        execv(cli, argv);
        fprintf(stderr, "ms: cannot run %s\n", cli);
        _exit(70);
    }
    int st = 0;
    if (waitpid(pid, &st, 0) < 0) {
        return 70;
    }
    /* Report a signal the way a shell does so the caller sees the same status as without us. */
    return WIFEXITED(st) ? WEXITSTATUS(st) : 128 + WTERMSIG(st);
#endif
}

int ms_driver_main(int argc, char **argv) {
    const char *command = argc > 1 ? argv[1] : "--help";
    bool trace = getenv("MS_DRIVER_TRACE") != NULL;
    bool in_c = ms_command_in_c(command);
    if (trace) {
        fprintf(stderr, "ms driver: %s -> %s\n", command, in_c ? "c" : "rust");
    }
    if (in_c) {
        /* No command is fully in C yet; the first one lands with its last stage. */
        fprintf(stderr, "ms: command %s is marked as C but has no C entry\n", command);
        return 70;
    }
    char *cli = rust_cli(argv[0]);
    int status = hand_to_rust(cli, argv);
    free(cli);
    return status;
}
