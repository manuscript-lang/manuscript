/* Directory cursors and scoped temporary directories of @std/fs: handles the program closes, or drops. */
#include <stdlib.h>
#include <string.h>

#include "fs_support.h"
#include "ms_rt/fs.h"

#define DIR_OPERATION_OPEN "open"

/* A text kept by a handle, copied with malloc (handles are freed on the runtime thread, but the text is plain data). */
typedef struct HandleText {
    char *data;
    size_t length;
} HandleText;

static bool text_keep(HandleText *text, MsBytes bytes) {
    text->data = malloc(bytes.len + 1);
    if (text->data == NULL) {
        return false;
    }
    if (bytes.len > 0) {
        memcpy(text->data, bytes.ptr, bytes.len);
    }
    text->data[bytes.len] = '\0';
    text->length = bytes.len;
    return true;
}

static void text_write(const HandleText *text, MsStr *out) {
    msrt_string_from_bytes((const uint8_t *)text->data, text->length, out);
}

/* ---- directory cursors ---- */

typedef struct MsFsDirectory {
    MsObj header;
    MsSysDir *dir; /* null once closed */
    HandleText path;
} MsFsDirectory;

static void directory_close_now(MsFsDirectory *handle) {
    if (handle->dir != NULL) {
        ms_sys_fs_dir_close(handle->dir);
        handle->dir = NULL;
    }
}

static void directory_drop(MsObj *object) {
    MsFsDirectory *handle = (MsFsDirectory *)object;
    directory_close_now(handle);
    free(handle->path.data);
    msrt_free(handle);
}

/* Opens `path`; anything but a directory is invalid input. */
static void directory_open_now(MsBytes path, MsSysDir **dir, MsFsFail *fail) {
    MsFsPath text;
    if (!ms_fs_path_init(&text, path)) {
        ms_fs_fail_status(fail, STATUS_INVALID_INPUT);
        return;
    }
    MsSysStat stat;
    MsSysError error = ms_sys_fs_stat(text.text, true, &stat);
    if (error != 0) {
        ms_fs_fail_errno_at(fail, error, DIR_OPERATION_OPEN, path);
    } else if ((stat.mode & MS_SYS_S_IFMT) != MS_SYS_S_IFDIR) {
        ms_fs_fail_status(fail, STATUS_INVALID_INPUT);
    } else {
        error = ms_sys_fs_dir_open(text.text, dir);
        if (error != 0) {
            ms_fs_fail_errno_at(fail, error, "fdopendir", path);
        }
    }
    ms_fs_path_free(&text);
}

uint8_t msstd_fs_directory_open(const MsStr *path, void **out, MsStr *err) {
    MsFsFail fail = {0};
    const MsBytes bytes = msrt_str_bytes(path);
    MsSysDir *dir = NULL;
    directory_open_now(bytes, &dir, &fail);
    if (!ms_fs_failed(&fail)) {
        MsFsDirectory *handle = msrt_alloc(sizeof *handle);
        if (!text_keep(&handle->path, bytes)) {
            msrt_free(handle);
            ms_sys_fs_dir_close(dir);
            ms_fs_fail_text(&fail, "out of memory");
        } else {
            handle->header.clone = NULL;
            handle->header.drop = directory_drop;
            handle->dir = dir;
            *out = handle;
        }
    }
    return ms_fs_finish_at(&fail, bytes, err);
}

/* The next entry in native order; STATUS_NONE at the end. */
uint8_t msstd_fs_directory_read(void *handle, MsFsEntry *out, MsStr *err) {
    MsFsDirectory *cursor = handle;
    MsFsFail fail = {0};
    uint8_t status = STATUS_OK;
    MsSysDirEntry entry = {0};
    bool found = false;
    if (cursor->dir == NULL) {
        status = STATUS_CLOSED;
    } else if (!ms_fs_poll_cancel(&fail)) {
        const MsSysError error = ms_sys_fs_dir_read(cursor->dir, &entry, &found);
        if (error != 0) {
            ms_fs_fail_errno_at(&fail, error, "readdirent", ms_bytes_of((const uint8_t *)cursor->path.data, cursor->path.length));
        } else if (!found) {
            status = STATUS_NONE;
        }
    }
    MsFsBuffer name = {0};
    if (status == STATUS_OK && !ms_fs_failed(&fail)) {
        bool is_dir = false;
        bool is_symlink = false;
        ms_fs_entry_kind(ms_bytes_of((const uint8_t *)cursor->path.data, cursor->path.length), &entry, &is_dir, &is_symlink);
        if (ms_fs_buffer_append_lossy(&name, (const uint8_t *)entry.name, entry.name_length)) {
            ms_fs_write_buffer_string(&out->name, &name);
            out->directory = is_dir ? 1 : 0;
            out->symlink = is_symlink ? 1 : 0;
        } else {
            ms_fs_fail_text(&fail, "out of memory");
        }
    }
    ms_fs_buffer_free(&name);
    if (status != STATUS_OK && !ms_fs_failed(&fail)) {
        fail.status = status;
    }
    return ms_fs_finish(&fail, err);
}

void msstd_fs_directory_close(void *handle) { directory_close_now(handle); }

void msstd_fs_directory_path(const void *handle, MsStr *out) {
    text_write(&((const MsFsDirectory *)handle)->path, out);
}

/* ---- temporary directories ---- */

typedef struct MsFsTemporary {
    MsObj header;
    HandleText path;
    bool closed;
} MsFsTemporary;

static void temporary_drop(MsObj *object) {
    MsFsTemporary *handle = (MsFsTemporary *)object;
    free(handle->path.data);
    msrt_free(handle);
}

uint8_t msstd_fs_temporary_open(const MsStr *prefix, void **out, MsStr *err) {
    MsFsFail fail = {0};
    MsFsBuffer path = {0};
    if (ms_fs_make_temporary_directory(msrt_str_bytes(prefix), &path, &fail)) {
        MsFsTemporary *handle = msrt_alloc(sizeof *handle);
        if (!text_keep(&handle->path, ms_fs_buffer_view(&path))) {
            msrt_free(handle);
            ms_fs_fail_text(&fail, "out of memory");
        } else {
            handle->header.clone = NULL;
            handle->header.drop = temporary_drop;
            handle->closed = false;
            *out = handle;
        }
    }
    ms_fs_buffer_free(&path);
    return ms_fs_finish(&fail, err);
}

void msstd_fs_temporary_path(const void *handle, MsStr *out) { text_write(&((const MsFsTemporary *)handle)->path, out); }

typedef struct RemoveJob {
    MsBytes path;
    MsFsFail fail;
} RemoveJob;

static void remove_tree_job(void *data) {
    RemoveJob *job = data;
    ms_fs_remove_tree(job->path, &job->fail);
}

/* Removes the tree; a failure carries its text in `err`. */
uint8_t msstd_fs_temporary_close(void *handle, MsStr *err) {
    MsFsTemporary *temporary = handle;
    RemoveJob job = {.path = ms_bytes_of((const uint8_t *)temporary->path.data, temporary->path.length)};
    if (!temporary->closed) {
        ms_fs_run(remove_tree_job, &job, &job.fail);
        if (!ms_fs_failed(&job.fail)) {
            temporary->closed = true;
        }
    }
    const uint8_t status = ms_fs_finish(&job.fail, err);
    return status;
}
