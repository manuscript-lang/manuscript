/* Helpers of the build steps (ms/build_tool.h): files and the programs they run, over the OS layer (runtime/sys). */
#include "ms/build_tool.h"

#include <stdlib.h>
#include <string.h>

#include "ms_rt/sys_fs.h"
#include "ms_rt/sys_process.h"

int ms_build_read_file(const char *path, MsBuf *out) {
    MsSysFd fd;
    MsSysError failure = ms_sys_fs_open(path, MS_SYS_O_READ, 0, &fd);
    uint8_t chunk[16384];
    size_t count = 1;
    while (failure == 0 && count > 0) {
        failure = ms_sys_fs_read(fd, chunk, sizeof chunk, &count);
        ms_buf_put(out, chunk, failure == 0 ? count : 0);
    }
    if (failure == 0 || count == 0) {
        ms_sys_fs_close_quietly(fd);
    }
    return failure;
}

bool ms_build_read(const char *path, MsBuf *out) { return ms_build_read_file(path, out) == 0; }

int ms_build_write_file(const char *path, const void *bytes, size_t len) {
    MsSysFd fd;
    MsSysError failure = ms_sys_fs_open(path, MS_SYS_O_WRITE | MS_SYS_O_CREATE | MS_SYS_O_TRUNCATE, 0666, &fd);
    if (failure != 0) {
        return failure;
    }
    for (size_t done = 0; failure == 0 && done < len;) {
        size_t count = 0;
        failure = ms_sys_fs_write(fd, (const uint8_t *)bytes + done, len - done, &count);
        done += count;
    }
    ms_sys_fs_close_quietly(fd);
    return failure;
}

bool ms_build_write(const char *path, const void *bytes, size_t len) { return ms_build_write_file(path, bytes, len) == 0; }

bool ms_build_is_file(const char *path) {
    MsSysStat info;
    return ms_sys_fs_stat(path, true, &info) == 0 && (info.mode & MS_SYS_S_IFMT) == MS_SYS_S_IFREG;
}

void ms_build_errno_text(int err_no, MsBuf *out) {
    char message[128];
    const size_t length = ms_sys_fs_error_text(err_no, message, sizeof message);
    ms_buf_put(out, message, length);
}

bool ms_build_run(const char *what, const char *const *argv, MsBuf *output) {
    return ms_build_run_in(what, argv, NULL, output);
}

bool ms_build_run_in(const char *what, const char *const *argv, const char *cwd, MsBuf *output) {
    MsSysRun run = {0};
    const MsSysError failure = ms_sys_process_run((char **)argv, NULL, cwd, true, &run); /* NOLINT(cppcoreguidelines-pro-type-const-cast) */
    if (failure != 0) {
        ms_buf_printf(output, "cannot run %s: ", what);
        ms_build_errno_text(failure, output);
        return false;
    }
    const bool ok = run.code == 0;
    if (!ok) {
        ms_buf_printf(output, "%s failed: ", what);
        size_t end = run.out_length;
        while (end > 0 && (run.out[end - 1] == '\n' || run.out[end - 1] == '\r' || run.out[end - 1] == ' ')) {
            end--;
        }
        ms_buf_put(output, run.out, end);
    }
    ms_sys_process_run_free(&run);
    return ok;
}

bool ms_build_have(const char *name) {
    const char *const argv[] = {name, "--version", NULL};
    MsSysRun run = {0};
    const MsSysError failure = ms_sys_process_run((char **)argv, NULL, NULL, true, &run); /* NOLINT(cppcoreguidelines-pro-type-const-cast) */
    if (failure == 0) {
        ms_sys_process_run_free(&run);
    }
    return failure == 0;
}

int ms_build_make_dir(char *pattern) {
    static const char letters[] = "abcdefghijklmnopqrstuvwxyz0123456789";
    const size_t length = strlen(pattern);
    if (length < 6 || strcmp(pattern + length - 6, "XXXXXX") != 0) {
        return ms_sys_fs_error_of(MS_SYS_ERR_INVALID);
    }
    for (int attempt = 0; attempt < 100; attempt++) {
        for (size_t i = 0; i < 6; i++) {
            pattern[length - 6 + i] = letters[ms_sys_fs_random() % (sizeof letters - 1)];
        }
        const MsSysError failure = ms_sys_fs_mkdir(pattern, 0700);
        if (failure == 0 || ms_sys_fs_error_kind(failure) != MS_SYS_ERR_EXISTS) {
            return failure;
        }
    }
    return ms_sys_fs_error_of(MS_SYS_ERR_EXISTS);
}

int ms_build_make_scratch(const char *prefix, MsBuf *path) {
    char *temp = NULL;
    size_t temp_length = 0;
    if (ms_sys_fs_temp_directory(&temp, &temp_length) == 0) {
        while (temp_length > 1 && (temp[temp_length - 1] == '/' || temp[temp_length - 1] == '\\')) {
            temp_length--;
        }
        ms_buf_put(path, temp, temp_length);
        free(temp);
    } else {
        ms_buf_puts(path, "/tmp");
    }
    ms_buf_printf(path, "/%s-XXXXXX", prefix);
    ms_buf_putc(path, 0);
    const int failure = ms_build_make_dir(path->data);
    path->len--;
    return failure;
}

void ms_build_unlink(const char *path) {
    if (ms_sys_fs_unlink(path) != 0) {
        const MsSysError ignored = ms_sys_fs_rmdir(path);
        (void)ignored;
    }
}

void ms_build_remove_tree(const char *path) {
    MsSysStat info;
    if (ms_sys_fs_stat(path, false, &info) != 0) {
        return;
    }
    if ((info.mode & MS_SYS_S_IFMT) != MS_SYS_S_IFDIR) {
        ms_build_unlink(path);
        return;
    }
    const MsSysError unlocked = ms_sys_fs_chmod(path, 0755);
    (void)unlocked;
    MsSysDir *dir = NULL;
    MsSysDirEntry entry;
    bool more = ms_sys_fs_dir_open(path, &dir) == 0;
    while (more && ms_sys_fs_dir_read(dir, &entry, &more) == 0 && more) {
        MsBuf child = {0};
        ms_buf_printf(&child, "%s/%.*s", path, (int)entry.name_length, entry.name);
        ms_buf_putc(&child, 0);
        ms_build_remove_tree(child.data);
        ms_buf_free(&child);
    }
    if (dir != NULL) {
        ms_sys_fs_dir_close(dir);
    }
    ms_build_unlink(path);
}

bool ms_build_make_path(const char *path) {
    const size_t length = strlen(path);
    char *copy = malloc(length + 1);
    if (copy == NULL) {
        return false;
    }
    memcpy(copy, path, length + 1);
    /* A drive and the root are not made. */
    const size_t root = length >= 2 && copy[1] == ':' ? 3 : 1;
    bool ok = true;
    for (size_t i = root; ok && i <= length; i++) {
        if (copy[i] != '/' && copy[i] != '\0') {
            continue;
        }
        const char saved = copy[i];
        copy[i] = '\0';
        const MsSysError failure = ms_sys_fs_mkdir(copy, 0777);
        ok = failure == 0 || ms_sys_fs_error_kind(failure) == MS_SYS_ERR_EXISTS;
        copy[i] = saved;
    }
    free(copy);
    return ok;
}
