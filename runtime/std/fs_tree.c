/* The helpers the tree operations of @std/fs share (fs_tree.h). Everything is plain malloc data. */
#include <stdlib.h>
#include <string.h>

#include "fs_tree.h"

MsSysError ms_fs_stat_bytes(MsBytes path, bool follow, MsSysStat *out) {
    MsFsPath text;
    if (!ms_fs_path_init(&text, path)) {
        return ms_sys_fs_error_of(MS_SYS_ERR_INVALID);
    }
    const MsSysError error = ms_sys_fs_stat(text.text, follow, out);
    ms_fs_path_free(&text);
    return error;
}

bool ms_fs_absolute(MsBytes path, MsFsBuffer *out) {
    if (ms_fs_is_absolute(path)) {
        return ms_fs_buffer_append(out, path.ptr, path.len);
    }
    char *cwd = NULL;
    size_t length = 0;
    if (ms_sys_fs_current_directory(&cwd, &length) != 0) {
        return ms_fs_buffer_append(out, path.ptr, path.len);
    }
    const bool joined = ms_fs_path_join(ms_bytes_of((const uint8_t *)cwd, length), path, out);
    free(cwd);
    return joined;
}

bool ms_fs_within_path(MsBytes source, MsBytes target, bool *within) {
    MsFsBuffer clean_source = {0};
    MsFsBuffer clean_target = {0};
    const bool cleaned = ms_fs_path_clean(source, &clean_source) && ms_fs_path_clean(target, &clean_target);
    if (cleaned) {
        const MsBytes prefix = ms_fs_buffer_view(&clean_source);
        const MsBytes whole = ms_fs_buffer_view(&clean_target);
        const bool rooted = prefix.len > 0 && ms_fs_is_separator(prefix.ptr[prefix.len - 1]);
        const bool inside = ms_bytes_starts_with(whole, prefix) && (rooted || whole.len == prefix.len || ms_fs_is_separator(whole.ptr[prefix.len]));
        *within = inside;
    }
    ms_fs_buffer_free(&clean_source);
    ms_fs_buffer_free(&clean_target);
    return cleaned;
}

bool ms_fs_names_push(MsFsBuffer *names, MsBytes name) {
    return ms_fs_buffer_append(names, (const uint8_t *)&name.len, sizeof name.len) && ms_fs_buffer_append(names, name.ptr, name.len);
}

bool ms_fs_names_next(const MsFsBuffer *names, size_t *cursor, MsBytes *name) {
    size_t length = 0;
    if (*cursor >= names->length || names->length - *cursor < sizeof length) {
        return false;
    }
    memcpy(&length, names->data + *cursor, sizeof length);
    const size_t start = *cursor + sizeof length;
    if (names->length - start < length) {
        return false;
    }
    *name = ms_bytes_of(names->data + start, length);
    *cursor = start + length;
    return true;
}

static bool names_collect(MsSysDir *dir, MsFsBuffer *names, MsFsFail *fail, MsBytes directory) {
    for (;;) {
        MsSysDirEntry entry;
        bool found = false;
        const MsSysError error = ms_sys_fs_dir_read(dir, &entry, &found);
        if (error != 0) {
            ms_fs_fail_errno_at(fail, error, "open", directory);
            return false;
        }
        if (!found) {
            return true;
        }
        if (!ms_fs_names_push(names, ms_bytes_of((const uint8_t *)entry.name, entry.name_length))) {
            ms_fs_fail_text(fail, "out of memory");
            return false;
        }
    }
}

bool ms_fs_names_read(MsBytes directory, MsFsBuffer *names, MsFsFail *fail) {
    MsFsPath text;
    if (!ms_fs_path_init(&text, directory)) {
        ms_fs_fail_status(fail, STATUS_INVALID_INPUT);
        return false;
    }
    MsSysDir *dir = NULL;
    const MsSysError error = ms_sys_fs_dir_open(text.text, &dir);
    ms_fs_path_free(&text);
    if (error != 0) {
        ms_fs_fail_errno_at(fail, error, "open", directory);
        return false;
    }
    const bool done = names_collect(dir, names, fail, directory);
    ms_sys_fs_dir_close(dir);
    return done;
}

void ms_fs_arguments_set(MsFsArguments *arguments, MsBytes first, MsBytes second) {
    msrt_string_from_bytes(first.ptr, first.len, &arguments->first);
    msrt_string_from_bytes(second.ptr, second.len, &arguments->second);
    arguments->live = true;
}

void ms_fs_arguments_free(MsFsArguments *arguments) {
    if (arguments->live) {
        msrt_string_free(&arguments->first);
        msrt_string_free(&arguments->second);
        arguments->live = false;
    }
}

bool ms_fs_names_contain(const MsFsBuffer *names, MsBytes name) {
    size_t cursor = 0;
    MsBytes entry;
    while (ms_fs_names_next(names, &cursor, &entry)) {
        if (ms_bytes_equal(entry, name)) {
            return true;
        }
    }
    return false;
}
