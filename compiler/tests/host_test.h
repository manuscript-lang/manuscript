/* What the project tests need of the host, over the OS layer (ms_rt/sys_fs.h) so one test runs on every platform: a
 * temporary root, directories, links, environment variables and git repositories built without a work tree. */
#ifndef MS_TEST_HOST_H
#define MS_TEST_HOST_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/project.h"
#include "ms_rt/sys_fs.h"
#include "ms_rt/sys_process.h"

/* A new empty directory under the temporary directory, named `<name>-<random>`, in `root`, with `/` separators and
 * every link resolved. False when none could be made. */
static inline bool host_make_root(char *root, size_t size, const char *name) {
    char *temporary = NULL;
    size_t length = 0;
    if (ms_sys_fs_temp_directory(&temporary, &length) != 0) {
        return false;
    }
    MsArena arena = {0};
    bool made = false;
    for (int attempt = 0; attempt < 16 && !made; attempt++) {
        const char *candidate = ms_arena_fmt(&arena, "%.*s/%s-%08x", (int)length, temporary, name, (unsigned)ms_sys_fs_random()).ptr;
        candidate = ms_path_clean(&arena, candidate);
        if (ms_sys_fs_mkdir(candidate, 0700) == 0) {
            const char *resolved;
            MsProjectError err = {0};
            made = ms_path_eval_symlinks(&arena, candidate, &resolved, &err) && strlen(resolved) < size;
            if (made) {
                memcpy(root, resolved, strlen(resolved) + 1);
            }
        }
    }
    free(temporary);
    ms_arena_free(&arena);
    return made;
}

static inline void host_mkdir(const char *path) {
    const MsSysError ignored = ms_sys_fs_mkdir(path, 0700);
    (void)ignored;
}

/* A symbolic link at `path` to `target`. */
static inline bool host_symlink(const char *target, const char *path) { return ms_sys_fs_symlink(target, path) == 0; }

static inline bool host_exists(const char *path) {
    MsSysStat info;
    return ms_sys_fs_stat(path, false, &info) == 0;
}

#ifndef _WIN32
int setenv(const char *name, const char *value, int overwrite); /* POSIX; the tests build as strict C11 */
#endif

static inline void host_set_env(const char *name, const char *value) {
#ifdef _WIN32
    (void)_putenv_s(name, value); /* the C library's getenv does not see SetEnvironmentVariable */
#else
    (void)setenv(name, value, 1);
#endif
}

/* Removes `path` whole, read-only entries included. */
static inline void host_remove_tree(const char *path) {
    MsArena arena = {0};
    const char *error;
    if (!ms_remove_all(&arena, path, &error)) {
        fprintf(stderr, "cannot remove %s: %s\n", path, error);
    }
    ms_arena_free(&arena);
}

/* ---- git repositories without a work tree ---- */

/* One file of a commit: `mode` is "100644" for a file and "120000" for a symbolic link whose target is `content`. */
typedef struct HostFile {
    const char *path;
    const char *content;
    const char *mode;
} HostFile;

static inline bool host_git(MsArena *a, const char *repository, const char *const *args, size_t count, const char **output) {
    char **argv = MS_NEW_N(a, char *, count + 8);
    size_t used = 0;
    static const char *const prefix[] = {"git", "-c", "user.email=t@example.com", "-c", "user.name=t", "-c", "core.autocrlf=false"};
    for (size_t i = 0; i < sizeof prefix / sizeof prefix[0]; i++) {
        argv[used++] = ms_arena_strndup(a, prefix[i], strlen(prefix[i]));
    }
    for (size_t i = 0; i < count; i++) {
        argv[used++] = ms_arena_strndup(a, args[i], strlen(args[i]));
    }
    argv[used] = NULL;
    MsSysRun run;
    if (ms_sys_process_run(argv, NULL, repository, true, &run) != 0) {
        fprintf(stderr, "cannot run git\n");
        return false;
    }
    const bool ok = run.code == 0;
    if (!ok) {
        fprintf(stderr, "git %s failed: %s\n", args[0], run.out);
    }
    if (output != NULL) {
        *output = ms_arena_strndup(a, run.out, run.out_length);
    }
    ms_sys_process_run_free(&run);
    return ok;
}

#define HOST_GIT(a, repository, output, ...) \
    host_git((a), (repository), (const char *const[]){__VA_ARGS__}, sizeof((const char *const[]){__VA_ARGS__}) / sizeof(char *), (output))

static inline bool host_git_init(MsArena *a, const char *repository) {
    return ms_sys_fs_mkdir(repository, 0700) == 0 && HOST_GIT(a, repository, NULL, "init", "-q", "-b", "main");
}

/* Commits exactly `files` (the index is replaced, no work tree is touched, so names Windows cannot create and links
 * need no privilege) and tags the commit `tag`. `scratch` is a directory outside the repository for blob files. */
static inline bool host_git_commit(MsArena *a, const char *repository, const char *scratch, const HostFile *files, size_t count,
                                   const char *tag) {
    bool ok = HOST_GIT(a, repository, NULL, "read-tree", "--empty");
    for (size_t i = 0; ok && i < count; i++) {
        const char *blob = ms_arena_fmt(a, "%s/blob", scratch).ptr;
        FILE *f = fopen(blob, "wb");
        if (f == NULL) {
            return false;
        }
        (void)fwrite(files[i].content, 1, strlen(files[i].content), f);
        (void)fclose(f);
        const char *hash = NULL;
        ok = HOST_GIT(a, repository, &hash, "hash-object", "-w", blob);
        if (ok) {
            size_t n = strlen(hash);
            while (n > 0 && (hash[n - 1] == '\n' || hash[n - 1] == '\r')) {
                n--;
            }
            const char *entry = ms_arena_fmt(a, "%s,%.*s,%s", files[i].mode, (int)n, hash, files[i].path).ptr;
            ok = HOST_GIT(a, repository, NULL, "update-index", "--add", "--cacheinfo", entry);
        }
    }
    return ok && HOST_GIT(a, repository, NULL, "commit", "-q", "--allow-empty", "-m", tag) && HOST_GIT(a, repository, NULL, "tag", tag);
}

#endif
