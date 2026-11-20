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
#include "ms_rt/safe.h"

#define B(stage) (1u << (stage))
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

bool ms_command_in_c(const MsStageTable *table, const char *command) {
    const unsigned stages = ms_command_stages(command);
    if (stages == 0) {
        return false;
    }
    for (int stage = 0; stage < MS_STAGE_COUNT; stage++) {
        if ((stages & B(stage)) != 0 && table->impl[stage] != MS_IMPL_C) {
            return false;
        }
    }
    return true;
}

#ifdef _WIN32
#define PATH_SEPARATORS "/\\"
static const char rust_cli_name[] = "ms-rust.exe";
#else
#define PATH_SEPARATORS "/"
static const char rust_cli_name[] = "ms-rust";
#endif

/* A malloc'd copy of `text`; the caller frees it. */
static char *copy_string(const char *text) {
    const size_t size = strlen(text) + 1;
    char *copy = malloc(size);
    if (copy == NULL) {
        abort();
    }
    memcpy(copy, text, size);
    return copy;
}

/* The Rust ms beside this executable. Returns a malloc'd path; the caller frees it. */
static char *sibling_rust_cli(const char *self) {
    size_t directory_length = 0;
    for (size_t i = 0; self[i] != '\0'; i++) {
        if (strchr(PATH_SEPARATORS, self[i]) != NULL) {
            directory_length = i + 1;
        }
    }
    size_t size = 0;
    if (!ms_size_add(directory_length, sizeof rust_cli_name, &size)) {
        abort();
    }
    char *path = malloc(size);
    if (path == NULL) {
        abort();
    }
    memcpy(path, self, directory_length);
    memcpy(path + directory_length, rust_cli_name, sizeof rust_cli_name);
    return path;
}

/* Runs `cli` with the arguments of `argv` (its own argv[0] replaced) and waits. Returns its exit
 * status, or 128 plus the signal that ended it. */
static int run_rust_cli(char *cli, int argc, char **argv) {
    char **args = calloc((size_t)argc + 1, sizeof *args);
    if (args == NULL) {
        abort();
    }
    args[0] = cli;
    for (int i = 1; i < argc; i++) {
        args[i] = argv[i];
    }
#ifdef _WIN32
    const intptr_t status = _spawnv(_P_WAIT, cli, (const char *const *)args);
    free(args);
    if (status == -1) {
        fprintf(stderr, "ms: cannot run %s\n", cli);
        return 70;
    }
    return (int)status;
#else
    const pid_t pid = fork();
    if (pid < 0) {
        free(args);
        fprintf(stderr, "ms: cannot start %s\n", cli);
        return 70;
    }
    if (pid == 0) {
        execv(cli, args);
        fprintf(stderr, "ms: cannot run %s\n", cli);
        _exit(70);
    }
    free(args);
    int wait_status = 0;
    if (waitpid(pid, &wait_status, 0) < 0) {
        return 70;
    }
    return WIFEXITED(wait_status) ? WEXITSTATUS(wait_status) : 128 + WTERMSIG(wait_status);
#endif
}

int ms_driver_main(int argc, char **argv) {
    // Environment reads happen once, here, before any thread exists.
    // NOLINTBEGIN(concurrency-mt-unsafe): single-threaded start-up.
    const char *stages_spec = getenv("MS_STAGES");
    const char *cli_override = getenv("MS_RUST_CLI");
    const bool trace = getenv("MS_DRIVER_TRACE") != NULL;
    // NOLINTEND(concurrency-mt-unsafe)

    MsStageTable table = ms_stage_table_default();
    if (stages_spec != NULL && !ms_stage_table_override(&table, stages_spec)) {
        fprintf(stderr, "ms: MS_STAGES must look like parse=rust,check=c\n");
        return 2;
    }
    const char *command = argc > 1 ? argv[1] : "--help";
    const bool in_c = ms_command_in_c(&table, command);
    if (trace) {
        fprintf(stderr, "ms driver: %s -> %s\n", command, in_c ? "c" : "rust");
    }
    if (in_c) {
        /* No command is fully in C yet; the first one lands with its last stage. */
        fprintf(stderr, "ms: command %s is marked as C but has no C entry\n", command);
        return 70;
    }
    char *cli = cli_override != NULL && *cli_override != '\0' ? copy_string(cli_override)
                                                               : sibling_rust_cli(argv[0]);
    const int status = run_rust_cli(cli, argc, argv);
    free(cli);
    return status;
}
