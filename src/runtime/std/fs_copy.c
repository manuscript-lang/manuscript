/* `copy` of @std/fs: a file or a tree under the caller's options, with an optional filter closure asking about each
 * (source, destination). It runs on the runtime thread because the filter is program code; the system calls block, as
 * the operation has always done. Everything it owns is in one Copier, which a cleanup frees if the filter leaves by a
 * jump. */
#include <stdlib.h>
#include <string.h>

#include "fs_tree.h"
#include "ms_rt/fs.h"

enum { COPY_BUFFER_BYTES = 65536, COPY_MAX_DEPTH = 1024, COPY_MODE_MASK = 07777, COPY_DIRECTORY_MODE = 0700 };

enum {
    FLAG_RECURSIVE = 1,
    FLAG_REPLACE = 2,
    FLAG_ERROR_ON_EXISTS = 4,
    FLAG_DEREFERENCE = 8,
    FLAG_PRESERVE = 16,
    FLAG_VERBATIM = 32
};

typedef enum { CLONE_NONE, CLONE_TRY, CLONE_FORCE } CloneMode;

typedef struct Copier {
    MsFsFail fail;
    int64_t flags;
    CloneMode clone;
    int64_t entries; /* left to copy */
    int64_t bytes;   /* left to copy */
    MsFsClosure *filter;
    MsFsBuffer destination; /* the destination root with its existing ancestors resolved through links */
    MsFsBuffer ancestors;   /* the canonical source directories being copied, as names */
    MsFsArguments arguments;
} Copier;

static void copier_free(Copier *copier) {
    ms_fs_fail_free(&copier->fail);
    ms_fs_buffer_free(&copier->destination);
    ms_fs_buffer_free(&copier->ancestors);
    ms_fs_arguments_free(&copier->arguments);
}

static void copier_cleanup(uint8_t *argument) {
    copier_free((Copier *)__builtin_assume_aligned(argument, _Alignof(Copier)));
}

static bool has_flag(const Copier *copier, int64_t flag) { return (copier->flags & flag) != 0; }

/* ---- failures ---- */

static bool fail_status(Copier *copier, uint8_t status) {
    ms_fs_fail_status(&copier->fail, status);
    return false;
}

static bool fail_memory(Copier *copier) {
    ms_fs_fail_text(&copier->fail, "out of memory");
    return false;
}

static bool fail_at(Copier *copier, MsSysError error, const char *operation, MsBytes path) {
    ms_fs_fail_errno_at(&copier->fail, error, operation, path);
    return false;
}

static bool is_kind(MsSysError error, MsSysErrorKind kind) { return ms_sys_fs_error_kind(error) == kind; }

/* ---- single system calls on a byte path ---- */

typedef MsSysError (*ModeCall)(const char *path, uint32_t mode);

static MsSysError call_with_mode(MsBytes path, ModeCall call, uint32_t mode) {
    MsFsPath text;
    if (!ms_fs_path_init(&text, path)) {
        return ms_sys_fs_error_of(MS_SYS_ERR_INVALID);
    }
    const MsSysError error = call(text.text, mode);
    ms_fs_path_free(&text);
    return error;
}

static MsSysError open_path(MsBytes path, int32_t flags, uint32_t mode, MsSysFd *fd) {
    MsFsPath text;
    if (!ms_fs_path_init(&text, path)) {
        return ms_sys_fs_error_of(MS_SYS_ERR_INVALID);
    }
    const MsSysError error = ms_sys_fs_open(text.text, flags, mode, fd);
    ms_fs_path_free(&text);
    return error;
}

static bool stat_at(Copier *copier, MsBytes path, bool follow, const char *operation, MsSysStat *out) {
    const MsSysError error = ms_fs_stat_bytes(path, follow, out);
    return error == 0 || fail_at(copier, error, operation, path);
}

static bool chmod_path(Copier *copier, MsBytes path, uint32_t mode) {
    const MsSysError error = call_with_mode(path, ms_sys_fs_chmod, mode & COPY_MODE_MASK);
    return error == 0 || fail_at(copier, error, "chmod", path);
}

static bool chtimes(Copier *copier, MsBytes path, const MsSysStat *info) {
    MsFsPath text;
    if (!ms_fs_path_init(&text, path)) {
        return fail_status(copier, STATUS_INVALID_INPUT);
    }
    const MsSysError error = ms_sys_fs_set_times(text.text, info->accessed, info->modified, true);
    ms_fs_path_free(&text);
    return error == 0 || fail_at(copier, error, "chtimes", path);
}

/* Removes `path`, a path that is already gone being fine. */
static bool remove_ignoring_missing(Copier *copier, MsBytes path) {
    MsFsPath text;
    if (!ms_fs_path_init(&text, path)) {
        return fail_status(copier, STATUS_INVALID_INPUT);
    }
    const MsSysError error = ms_fs_remove_one(text.text);
    ms_fs_path_free(&text);
    return error == 0 || is_kind(error, MS_SYS_ERR_NOT_FOUND) || fail_at(copier, error, "remove", path);
}

static bool canonical_of(Copier *copier, MsBytes path, MsFsBuffer *out) {
    const MsSysError error = ms_fs_eval_symlinks(path, out);
    return error == 0 || fail_at(copier, error, "lstat", path);
}

/* ---- the destination ---- */

/* The canonical source, where a link that is not followed is its parent's canonical path and its own name. */
static bool source_canonical(Copier *copier, MsBytes source, MsFsBuffer *out) {
    MsSysStat info;
    const bool is_link = !has_flag(copier, FLAG_DEREFERENCE) && ms_fs_stat_bytes(source, false, &info) == 0 && ms_fs_stat_is_link(&info);
    if (!is_link) {
        return canonical_of(copier, source, out);
    }
    MsFsBuffer parent = {0};
    MsFsBuffer real_parent = {0};
    bool ok = ms_fs_path_dir(source, &parent) || fail_memory(copier);
    const MsSysError error = ok ? ms_fs_eval_symlinks(ms_fs_buffer_view(&parent), &real_parent) : 0;
    if (error != 0) {
        ok = fail_at(copier, error, "lstat", source);
    }
    if (ok && !ms_fs_path_join(ms_fs_buffer_view(&real_parent), ms_fs_path_base(source), out)) {
        ok = fail_memory(copier);
    }
    ms_fs_buffer_free(&parent);
    ms_fs_buffer_free(&real_parent);
    return ok;
}

typedef enum { CLIMB_FOUND, CLIMB_UP, CLIMB_FAILED } Climb;

/* Moves `ancestor` one directory up while it does not exist, remembering the names climbed in `suffix`. */
static Climb climb_once(Copier *copier, MsFsBuffer *ancestor, MsFsBuffer *suffix) {
    const MsBytes current = ms_fs_buffer_view(ancestor);
    MsSysStat info;
    const MsSysError error = ms_fs_stat_bytes(current, false, &info);
    if (error == 0) {
        return CLIMB_FOUND;
    }
    if (!is_kind(error, MS_SYS_ERR_NOT_FOUND)) {
        fail_at(copier, error, "lstat", current);
        return CLIMB_FAILED;
    }
    MsFsBuffer parent = {0};
    MsFsBuffer joined = {0};
    Climb result = CLIMB_UP;
    const MsBytes name = ms_fs_path_base(current);
    const bool parted = ms_fs_path_dir(current, &parent);
    const bool at_top = parted && parent.length == current.len && memcmp(parent.data, current.ptr, current.len) == 0;
    const bool grown = parted && !at_top &&
                       (suffix->length == 0 ? ms_fs_buffer_append(&joined, name.ptr, name.len) : ms_fs_path_join(name, ms_fs_buffer_view(suffix), &joined));
    if (!parted || (!at_top && !grown)) {
        fail_memory(copier);
        result = CLIMB_FAILED;
    } else if (at_top) {
        fail_status(copier, STATUS_INVALID_INPUT);
        result = CLIMB_FAILED;
    }
    if (result == CLIMB_UP) {
        ms_fs_buffer_free(suffix);
        ms_fs_buffer_free(ancestor);
        *suffix = joined;
        *ancestor = parent;
        return CLIMB_UP;
    }
    ms_fs_buffer_free(&parent);
    ms_fs_buffer_free(&joined);
    return result;
}

/* The canonical form of the existing `ancestor`; a dangling link is its parent's canonical path and its own name. */
static bool resolve_ancestor(Copier *copier, const MsFsBuffer *ancestor, MsFsBuffer *real) {
    const MsBytes current = ms_fs_buffer_view(ancestor);
    const MsSysError error = ms_fs_eval_symlinks(current, real);
    if (error == 0) {
        return true;
    }
    MsFsBuffer parent = {0};
    bool ok = is_kind(error, MS_SYS_ERR_NOT_FOUND) && ms_fs_path_dir(current, &parent) && parent.length != current.len;
    if (!ok) {
        ms_fs_buffer_free(&parent);
        return fail_at(copier, error, "lstat", current);
    }
    MsFsBuffer real_parent = {0};
    const MsSysError parent_error = ms_fs_eval_symlinks(ms_fs_buffer_view(&parent), &real_parent);
    if (parent_error != 0) {
        ok = fail_at(copier, parent_error, "lstat", ms_fs_buffer_view(&parent));
    } else if (!ms_fs_path_join(ms_fs_buffer_view(&real_parent), ms_fs_path_base(current), real)) {
        ok = fail_memory(copier);
    }
    ms_fs_buffer_free(&parent);
    ms_fs_buffer_free(&real_parent);
    return ok;
}

/* `resolveDestination`: the destination with the links of its existing ancestors resolved. */
static bool resolve_destination(Copier *copier, MsBytes destination, MsFsBuffer *out) {
    MsFsBuffer ancestor = {0};
    MsFsBuffer suffix = {0};
    bool ok = ms_fs_buffer_append(&ancestor, destination.ptr, destination.len) || fail_memory(copier);
    Climb climb = ok ? CLIMB_UP : CLIMB_FAILED;
    while (climb == CLIMB_UP) {
        climb = climb_once(copier, &ancestor, &suffix);
    }
    ok = climb == CLIMB_FOUND;
    MsFsBuffer real = {0};
    ok = ok && resolve_ancestor(copier, &ancestor, &real);
    if (ok && suffix.length > 0) {
        MsFsBuffer whole = {0};
        ok = ms_fs_path_join(ms_fs_buffer_view(&real), ms_fs_buffer_view(&suffix), &whole) || fail_memory(copier);
        ms_fs_buffer_free(&real);
        real = whole;
    }
    if (ok) {
        *out = real;
        real = (MsFsBuffer){0};
    }
    ms_fs_buffer_free(&real);
    ms_fs_buffer_free(&ancestor);
    ms_fs_buffer_free(&suffix);
    return ok;
}

/* Rejects a destination inside the source and keeps the resolved destination. */
static bool check_destination(Copier *copier, MsBytes source, MsBytes destination) {
    MsFsBuffer canonical = {0};
    bool ok = source_canonical(copier, source, &canonical) && resolve_destination(copier, destination, &copier->destination);
    bool within = false;
    if (ok && !ms_fs_within_path(ms_fs_buffer_view(&canonical), ms_fs_buffer_view(&copier->destination), &within)) {
        ok = fail_memory(copier);
    }
    if (ok && within) {
        ok = fail_status(copier, STATUS_INVALID_INPUT);
    }
    ms_fs_buffer_free(&canonical);
    return ok;
}

/* ---- files ---- */

/* Copies `input` to `output`, charging the byte budget. */
static bool copy_stream(Copier *copier, MsSysFd input, MsSysFd output, MsBytes destination) {
    uint8_t *buffer = malloc(COPY_BUFFER_BYTES);
    if (buffer == NULL) {
        return fail_memory(copier);
    }
    bool ok = true;
    while (ok) {
        size_t count = 0;
        MsSysError error = 0;
        if (ms_fs_poll_cancel(&copier->fail)) {
            ok = false;
            break;
        }
        error = ms_sys_fs_read(input, buffer, COPY_BUFFER_BYTES, &count);
        if (error != 0) {
            ok = fail_at(copier, error, "read", ms_bytes_of(NULL, 0));
        } else if (count == 0) {
            break;
        } else if ((int64_t)count > copier->bytes) {
            ok = fail_status(copier, STATUS_LIMIT_EXCEEDED);
        } else {
            size_t done = 0;
            while (ok && done < count) {
                size_t written = 0;
                const MsSysError write_error = ms_sys_fs_write(output, buffer + done, count - done, &written);
                if (write_error != 0) {
                    ok = fail_at(copier, write_error, "write", destination);
                } else if (written == 0) {
                    ms_fs_fail_text(&copier->fail, "short write");
                    ok = false;
                }
                done += written;
            }
            copier->bytes -= (int64_t)count;
        }
    }
    free(buffer);
    return ok;
}

/* Copies the bytes of `input` into a new `destination` with the source's permission bits. */
static bool copy_contents(Copier *copier, MsSysFd input, MsBytes destination, const MsSysStat *info) {
    MsSysFd output = MS_SYS_FD_INVALID;
    const MsSysError open_error = open_path(destination, MS_SYS_O_WRITE | MS_SYS_O_CREATE | MS_SYS_O_EXCLUSIVE, info->mode & COPY_MODE_MASK, &output);
    if (open_error != 0) {
        return fail_at(copier, open_error, "open", destination);
    }
    bool ok = copy_stream(copier, input, output, destination);
    if (ok) {
        const MsSysError error = ms_sys_fs_chmod_fd(output, info->mode & COPY_MODE_MASK);
        ok = error == 0 || fail_at(copier, error, "chmod", destination);
    }
    const MsSysError close_error = ms_sys_fs_close(output);
    if (ok && close_error != 0) {
        ok = fail_at(copier, close_error, "close", destination);
    }
    return ok;
}

/* Shares the extents of `input` with a new `destination`; a failure removes the file it created. */
static bool clone_into(MsFsFail *fail, MsSysFd input, MsBytes destination, const MsSysStat *info) {
    MsSysFd output = MS_SYS_FD_INVALID;
    MsSysError error = open_path(destination, MS_SYS_O_WRITE | MS_SYS_O_CREATE | MS_SYS_O_EXCLUSIVE, info->mode & COPY_MODE_MASK, &output);
    if (error != 0) {
        ms_fs_fail_errno_at(fail, error, "open", destination);
        return false;
    }
    error = ms_sys_fs_clone_file(output, input);
    ms_sys_fs_close_quietly(output);
    if (error == 0) {
        return true;
    }
    MsFsPath text;
    if (ms_fs_path_init(&text, destination)) {
        const MsSysError ignored = ms_sys_fs_unlink(text.text);
        (void)ignored;
        ms_fs_path_free(&text);
    }
    ms_fs_fail_errno_at(fail, error, "ioctl", destination);
    return false;
}

typedef enum { CLONED, CLONE_SKIPPED, CLONE_ERROR } CloneResult;

/* The clone step of copying a file: done, skipped in favour of an ordinary copy, or failed. */
static CloneResult try_clone(Copier *copier, MsSysFd input, MsBytes destination, const MsSysStat *info) {
    MsFsFail attempt = {0};
    if (!clone_into(&attempt, input, destination, info)) {
        MsSysStat leftover;
        // A failed clone removed only the file it created; take the ordinary copy unless forced.
        const bool keep = copier->clone == CLONE_FORCE || ms_fs_stat_bytes(destination, false, &leftover) == 0;
        if (keep) {
            ms_fs_fail_free(&copier->fail);
            copier->fail = attempt;
            return CLONE_ERROR;
        }
        ms_fs_fail_free(&attempt);
        return CLONE_SKIPPED;
    }
    MsSysStat cloned;
    if (!stat_at(copier, destination, true, "stat", &cloned)) {
        return CLONE_ERROR;
    }
    if (cloned.size > copier->bytes) {
        fail_status(copier, STATUS_LIMIT_EXCEEDED);
        return CLONE_ERROR;
    }
    copier->bytes -= cloned.size;
    return CLONED;
}

static bool copy_file_from(Copier *copier, MsSysFd input, MsBytes source, MsBytes destination, const MsSysStat *info, bool exists) {
    MsSysStat acquired;
    const MsSysError stat_error = ms_sys_fs_fstat(input, &acquired);
    if (stat_error != 0) {
        return fail_at(copier, stat_error, "stat", source);
    }
    if (!ms_fs_same_file(info, &acquired)) {
        return fail_status(copier, STATUS_INVALID_INPUT);
    }
    if (exists && !remove_ignoring_missing(copier, destination)) {
        return false;
    }
    if (copier->clone != CLONE_NONE) {
        const CloneResult cloned = try_clone(copier, input, destination, info);
        if (cloned == CLONE_ERROR) {
            return false;
        }
        if (cloned == CLONED) {
            return chmod_path(copier, destination, info->mode) && (!has_flag(copier, FLAG_PRESERVE) || chtimes(copier, destination, info));
        }
    }
    return copy_contents(copier, input, destination, info) && (!has_flag(copier, FLAG_PRESERVE) || chtimes(copier, destination, info));
}

static bool copy_file(Copier *copier, MsBytes source, MsBytes destination, const MsSysStat *info, bool exists) {
    MsSysFd input = MS_SYS_FD_INVALID;
    const MsSysError error = open_path(source, MS_SYS_O_READ, 0, &input);
    if (error != 0) {
        return fail_at(copier, error, "open", source);
    }
    const bool ok = copy_file_from(copier, input, source, destination, info, exists);
    ms_sys_fs_close_quietly(input);
    return ok;
}

/* A symbolic link at `destination` pointing at `link`. */
static bool make_symlink(Copier *copier, MsBytes link, MsBytes destination) {
    MsFsPath link_text;
    if (!ms_fs_path_init(&link_text, link)) {
        return fail_status(copier, STATUS_INVALID_INPUT);
    }
    MsFsPath destination_text;
    if (!ms_fs_path_init(&destination_text, destination)) {
        ms_fs_path_free(&link_text);
        return fail_status(copier, STATUS_INVALID_INPUT);
    }
    const MsSysError error = ms_sys_fs_symlink(link_text.text, destination_text.text);
    ms_fs_path_free(&link_text);
    ms_fs_path_free(&destination_text);
    if (error != 0) {
        const MsBytes paths[2] = {link, destination};
        ms_fs_fail_errno(&copier->fail, error, "symlink", paths, 2);
        return false;
    }
    return true;
}

/* A symbolic link is copied as a link; a relative target is made absolute unless the copy is verbatim. */
static bool copy_link(Copier *copier, MsBytes source, MsBytes destination, bool exists) {
    MsFsPath text;
    if (!ms_fs_path_init(&text, source)) {
        return fail_status(copier, STATUS_INVALID_INPUT);
    }
    char *target = NULL;
    size_t length = 0;
    const MsSysError error = ms_sys_fs_readlink(text.text, &target, &length);
    ms_fs_path_free(&text);
    if (error != 0) {
        return fail_at(copier, error, "readlink", source);
    }
    MsFsBuffer resolved = {0};
    MsBytes link = ms_bytes_of((const uint8_t *)target, length);
    bool ok = true;
    if (!has_flag(copier, FLAG_VERBATIM) && !ms_fs_is_absolute(link)) {
        MsFsBuffer parent = {0};
        MsFsBuffer absolute_parent = {0};
        ok = (ms_fs_path_dir(source, &parent) && ms_fs_absolute(ms_fs_buffer_view(&parent), &absolute_parent) &&
              ms_fs_path_join(ms_fs_buffer_view(&absolute_parent), link, &resolved)) ||
             fail_memory(copier);
        link = ms_fs_buffer_view(&resolved);
        ms_fs_buffer_free(&parent);
        ms_fs_buffer_free(&absolute_parent);
    }
    if (ok && exists) {
        ok = remove_ignoring_missing(copier, destination);
    }
    if (ok) {
        ok = make_symlink(copier, link, destination);
    }
    ms_fs_buffer_free(&resolved);
    free(target);
    return ok;
}

/* ---- directories ---- */

static bool copy_entry(Copier *copier, MsBytes source, MsBytes destination, size_t depth);

/* The children of `source`, each copied to the same name under `destination`. */
static bool copy_children(Copier *copier, MsBytes source, MsBytes destination, size_t depth) {
    MsFsBuffer names = {0};
    bool ok = ms_fs_names_read(source, &names, &copier->fail);
    size_t cursor = 0;
    MsBytes name;
    while (ok && ms_fs_names_next(&names, &cursor, &name)) {
        MsFsBuffer from = {0};
        MsFsBuffer to = {0};
        ok = (ms_fs_path_join(source, name, &from) && ms_fs_path_join(destination, name, &to)) || fail_memory(copier);
        ok = ok && copy_entry(copier, ms_fs_buffer_view(&from), ms_fs_buffer_view(&to), depth + 1);
        ms_fs_buffer_free(&from);
        ms_fs_buffer_free(&to);
    }
    ms_fs_buffer_free(&names);
    return ok;
}

static bool copy_directory_inner(Copier *copier, MsBytes source, MsBytes destination, const MsSysStat *info, bool exists, size_t depth) {
    if (!exists) {
        const MsSysError error = call_with_mode(destination, ms_sys_fs_mkdir, COPY_DIRECTORY_MODE);
        if (error != 0) {
            return fail_at(copier, error, "mkdir", destination);
        }
    }
    if (!copy_children(copier, source, destination, depth)) {
        return false;
    }
    if (!exists && !chmod_path(copier, destination, info->mode)) {
        return false;
    }
    return !has_flag(copier, FLAG_PRESERVE) || chtimes(copier, destination, info);
}

static bool copy_directory(Copier *copier, MsBytes source, MsBytes destination, const MsSysStat *info, const MsSysStat *previous, size_t depth) {
    if (!has_flag(copier, FLAG_RECURSIVE) || (previous != NULL && !ms_fs_stat_is_directory(previous))) {
        return fail_status(copier, STATUS_INVALID_INPUT);
    }
    if (previous != NULL && !has_flag(copier, FLAG_REPLACE) && has_flag(copier, FLAG_ERROR_ON_EXISTS)) {
        return fail_status(copier, STATUS_ALREADY_EXISTS);
    }
    MsFsBuffer canonical = {0};
    bool ok = canonical_of(copier, source, &canonical);
    bool within = false;
    // A followed link can lead to a directory that holds the destination; copying it would read the tree being written and never end.
    if (ok && !ms_fs_within_path(ms_fs_buffer_view(&canonical), ms_fs_buffer_view(&copier->destination), &within)) {
        ok = fail_memory(copier);
    }
    if (ok && (within || ms_fs_names_contain(&copier->ancestors, ms_fs_buffer_view(&canonical)))) {
        ok = fail_status(copier, STATUS_INVALID_INPUT);
    }
    const size_t mark = copier->ancestors.length;
    if (ok && !ms_fs_names_push(&copier->ancestors, ms_fs_buffer_view(&canonical))) {
        ok = fail_memory(copier);
    }
    ms_fs_buffer_free(&canonical);
    if (!ok) {
        return false;
    }
    ok = copy_directory_inner(copier, source, destination, info, previous != NULL, depth);
    copier->ancestors.length = mark;
    return ok;
}

/* ---- entries ---- */

/* Asks the filter whether to copy (source, destination); no filter copies everything. */
static bool filter_accepts(Copier *copier, MsBytes source, MsBytes destination) {
    if (copier->filter == NULL) {
        return true;
    }
    MsFsArguments *arguments = &copier->arguments;
    ms_fs_arguments_set(arguments, source, destination);
    const uint8_t keep = copier->filter->code.pair(copier->filter, arguments->first.low_bits, arguments->first.tagged,
                                                    arguments->second.low_bits, arguments->second.tagged);
    ms_fs_arguments_free(arguments);
    return keep != 0;
}

/* What is at the destination: false in `*present` when nothing is. */
static bool destination_state(Copier *copier, MsBytes destination, MsSysStat *previous, bool *present) {
    const MsSysError error = ms_fs_stat_bytes(destination, false, previous);
    *present = error == 0;
    return error == 0 || is_kind(error, MS_SYS_ERR_NOT_FOUND) || fail_at(copier, error, "lstat", destination);
}

/* Copies a file or link that is not a directory, given the destination's state. */
static bool copy_leaf(Copier *copier, MsBytes source, MsBytes destination, const MsSysStat *info, bool exists) {
    if (exists && !has_flag(copier, FLAG_REPLACE)) {
        return has_flag(copier, FLAG_ERROR_ON_EXISTS) ? fail_status(copier, STATUS_ALREADY_EXISTS) : true;
    }
    if (ms_fs_stat_is_link(info)) {
        return copy_link(copier, source, destination, exists);
    }
    if (!ms_fs_stat_is_regular(info)) {
        return fail_status(copier, STATUS_INVALID_INPUT);
    }
    if (info->size > copier->bytes) {
        return fail_status(copier, STATUS_LIMIT_EXCEEDED);
    }
    return copy_file(copier, source, destination, info, exists);
}

static bool copy_entry(Copier *copier, MsBytes source, MsBytes destination, size_t depth) {
    if (ms_fs_poll_cancel(&copier->fail)) {
        return false;
    }
    if (depth > COPY_MAX_DEPTH || copier->entries <= 0) {
        return fail_status(copier, STATUS_LIMIT_EXCEEDED);
    }
    copier->entries -= 1;
    if (!filter_accepts(copier, source, destination)) {
        return true;
    }
    MsSysStat info;
    MsSysStat previous;
    bool present = false;
    const bool follow = has_flag(copier, FLAG_DEREFERENCE);
    bool ok = stat_at(copier, source, false, "lstat", &info) && (!follow || stat_at(copier, source, true, "stat", &info)) &&
              destination_state(copier, destination, &previous, &present);
    if (ok && present && ms_fs_same_file(&info, &previous)) {
        ok = fail_status(copier, STATUS_INVALID_INPUT);
    }
    if (!ok) {
        return false;
    }
    if (ms_fs_stat_is_directory(&info)) {
        return copy_directory(copier, source, destination, &info, present ? &previous : NULL, depth);
    }
    return copy_leaf(copier, source, destination, &info, present);
}

/* ---- the native ---- */

static bool parse_clone(const MsStr *text, CloneMode *mode) {
    const MsBytes bytes = msrt_str_bytes(text);
    if (bytes.len == 4 && memcmp(bytes.ptr, "none", 4) == 0) {
        *mode = CLONE_NONE;
    } else if (bytes.len == 3 && memcmp(bytes.ptr, "try", 3) == 0) {
        *mode = CLONE_TRY;
    } else if (bytes.len == 5 && memcmp(bytes.ptr, "force", 5) == 0) {
        *mode = CLONE_FORCE;
    } else {
        return false;
    }
    return true;
}

static uint8_t invalid_input(MsStr *err) {
    if (err != NULL) {
        msrt_string_empty(err);
    }
    return STATUS_INVALID_INPUT;
}

uint8_t msstd_fs_copy(const MsStr *source, const MsStr *destination, int64_t flags, const MsStr *clone, uint8_t has_entries, int64_t entries,
                      uint8_t has_bytes, int64_t bytes, void *filter, MsStr *err) {
    Copier copier = {.flags = flags, .filter = filter};
    if (!parse_clone(clone, &copier.clone)) {
        return invalid_input(err);
    }
    if (!ms_fs_limit(has_entries, entries, &copier.entries) || !ms_fs_limit(has_bytes, bytes, &copier.bytes)) {
        ms_fs_fail_status(&copier.fail, STATUS_INVALID_INPUT);
        return ms_fs_finish(&copier.fail, err);
    }
    const MsBytes from = msrt_str_bytes(source);
    const MsBytes to = msrt_str_bytes(destination);
    const size_t handle = msrt_cleanup_push(copier_cleanup, (uint8_t *)&copier);
    if (check_destination(&copier, from, to)) {
        copy_entry(&copier, from, to, 0);
    }
    msrt_cleanup_discard(handle);
    ms_fs_arguments_free(&copier.arguments);
    ms_fs_buffer_free(&copier.destination);
    ms_fs_buffer_free(&copier.ancestors);
    return ms_fs_finish_pair(&copier.fail, from, to, err);
}
