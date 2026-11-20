/* The driver: picks, per command, between running in C and handing the command to the Rust ms. */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#ifdef _WIN32
#include <process.h>
#else
#include <unistd.h>
#include <sys/wait.h>
#endif

#include "ms/check_run.h"
#include "ms/cmd.h"
#include "ms/driver.h"
#include "ms/std_embed.h"
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

/* `ms check FILE.ms [--json]`: the one target and optional --json; anything else is a handover. */
int ms_cmd_check(int argc, char **argv) {
    const char *target = NULL;
    bool json = false;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--json") == 0 && !json) {
            json = true;
        } else if (argv[i][0] != '-' && target == NULL) {
            target = argv[i];
        } else {
            return MS_CMD_HANDOVER;
        }
    }
    const size_t n = target == NULL ? 0 : strlen(target);
    struct stat st;
    if (n < 4 || strcmp(target + n - 3, ".ms") != 0 || stat(target, &st) != 0 || !S_ISREG(st.st_mode)) {
        return MS_CMD_HANDOVER;
    }
    uint32_t nstd = 0;
    const MsStdFile *std_files = ms_std_embedded(&nstd);
    MsBuf out = {0}, err = {0};
    const int status = ms_check_run(std_files, nstd, target, json, &out, &err);
    if (status != MS_CHECK_HANDOVER) {
        if (out.len != 0) {
            fwrite(out.data, 1, out.len, stdout);
        }
        if (err.len != 0) {
            fwrite(err.data, 1, err.len, stderr);
        }
    }
    ms_buf_free(&out);
    ms_buf_free(&err);
    return status == MS_CHECK_HANDOVER ? MS_CMD_HANDOVER : status;
}

/* Commands whose own logic (the TOOL stage) is in C: they run when the other stages they need are. */
static const struct {
    const char *name;
    int (*run)(int argc, char **argv);
} c_commands[] = {
    {"check", ms_cmd_check},
};

static int (*c_command(const char *name))(int, char **) {
    for (size_t i = 0; i < sizeof c_commands / sizeof c_commands[0]; i++) {
        if (strcmp(c_commands[i].name, name) == 0) {
            return c_commands[i].run;
        }
    }
    return NULL;
}

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
        const bool tool_in_c = stage == MS_STAGE_TOOL && c_command(command) != NULL;
        if ((stages & B(stage)) != 0 && table->impl[stage] != MS_IMPL_C && !tool_in_c) {
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
        int (*const run)(int, char **) = c_command(command);
        if (run == NULL) {
            fprintf(stderr, "ms: command %s is marked as C but has no C entry\n", command);
            return 70;
        }
        const int status = run(argc - 1, argv + 1);
        if (status != MS_CMD_HANDOVER) {
            return status;
        }
        if (trace) {
            fprintf(stderr, "ms driver: %s -> rust (handover)\n", command);
        }
    }
    char *cli = cli_override != NULL && *cli_override != '\0' ? copy_string(cli_override)
                                                               : sibling_rust_cli(argv[0]);
    const int status = run_rust_cli(cli, argc, argv);
    free(cli);
    return status;
}
