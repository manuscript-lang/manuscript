/* The path-based @std/fs natives (read, write, stat, list, remove, rename, links, attributes). Each one validates its
 * arguments, runs the system calls on the blocking pool when other tasks could use the time (ms_fs_run), and turns the
 * outcome into a status plus text. A job runs where the runtime is off limits, so it works on malloc'd data and the
 * native copies the result into runtime values afterwards. Borrowed arguments are safe in a job: the wait is shielded. */
#include "ms_rt/fs.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "fs_support.h"

#define ARRAY_LENGTH(a) (sizeof(a) / sizeof((a)[0]))

/* ---- one job record for every operation ---- */

typedef struct FsJob {
    MsBytes path;
    MsBytes other; /* a second path, a link target or the bytes to write */
    int64_t number;
    int64_t second_number;
    int64_t third_number;
    uint8_t flag;
    MsSysTime times[2];
    MsFsFail fail;
    /* results */
    MsFsBuffer text;
    MsSysStat stat;
    MsSysFsStat filesystem;
    bool found;
    bool not_regular; /* a whole-file job found something that is not a regular file */
} FsJob;

static FsJob job_for(const MsStr *path) {
    FsJob job = {0};
    job.path = msrt_str_bytes(path);
    return job;
}

static void job_free(FsJob *job) {
    ms_fs_fail_free(&job->fail);
    ms_fs_buffer_free(&job->text);
}

static void run_job(MsFsRunFn run, FsJob *job) { ms_fs_run(run, job, &job->fail); }

/* ---- error kinds ---- */

static bool is_kind(MsSysError error, MsSysErrorKind kind) { return ms_sys_fs_error_kind(error) == kind; }

static void fail_invalid(MsFsFail *fail) { ms_fs_fail_status(fail, STATUS_INVALID_INPUT); }

static bool open_path(MsFsFail *fail, MsFsPath *path, MsBytes bytes) {
    if (!ms_fs_path_init(path, bytes)) {
        fail_invalid(fail);
        return false;
    }
    return true;
}

static void fail_memory(MsFsFail *fail) { ms_fs_fail_text(fail, "out of memory"); }

/* ---- whole files ---- */

enum { READ_CHUNK = 32 * 1024, READ_LARGEST = 1 << 20, READ_KNOWN_LIMIT = 1 << 28, WRITE_STEP = 65536, WRITE_JOB_STEP = 1 << 20 };

/* Parks until `fd` can be read, so a pipe with no data yet neither stalls the other tasks nor ignores a stop request. */
static bool wait_readable(MsSysFd fd, MsFsFail *fail) {
#ifdef _WIN32
    (void)fd;
    (void)fail;
    return true;
#else
    if ((msrt_task_wait_fd((int32_t)fd, MS_WAIT_READ, -1) & MS_WAIT_CANCELLED) != 0) {
        ms_fs_fail_text(fail, "cancelled");
        return false;
    }
    return true;
#endif
}

/* Called before each park of a wait that loops: a stop request fails, and so does a bounded read whose time has
 * passed, because a park past that limit returns at once and a loop that only retried would spin. */
static bool check_wait(MsFsFail *fail) {
    if (ms_fs_poll_cancel(fail)) {
        return false;
    }
    if (ms_sched_read_limit_passed()) {
        ms_fs_fail_status(fail, STATUS_TIMED_OUT);
        return false;
    }
    return true;
}

static bool is_regular(const MsSysStat *stat) { return (stat->mode & MS_SYS_S_IFMT) == MS_SYS_S_IFREG; }
static bool is_directory(const MsSysStat *stat) { return (stat->mode & MS_SYS_S_IFMT) == MS_SYS_S_IFDIR; }
static bool is_link(const MsSysStat *stat) { return (stat->mode & MS_SYS_S_IFMT) == MS_SYS_S_IFLNK; }

/* Reads to the end of `fd` into `out`, failing with STATUS_LIMIT_EXCEEDED when more than `max` bytes arrive. A
 * cancellable read checks for a stop request between reads (a pool thread must not) and waits for a pipe or device to
 * be readable. `stat` is the descriptor's fstat, or null when it has none. */
void ms_fs_read_limited(MsSysFd fd, int64_t max, bool cancellable, const MsSysStat *stat, MsFsBuffer *out, MsFsFail *fail) {
    size_t first = 0;
    const size_t max_size = max > (int64_t)(SIZE_MAX / 2) ? SIZE_MAX / 2 : (size_t)max;
    if (stat != NULL && is_regular(stat)) {
        const size_t known = stat->size > 0 ? (size_t)stat->size : 0;
        first = (known < max_size ? known : max_size);
        first = first < READ_KNOWN_LIMIT ? first : READ_KNOWN_LIMIT;
    } else {
        first = max_size < READ_CHUNK - 1 ? max_size : READ_CHUNK - 1;
    }
    first += 1;
    uint8_t *buffer = malloc(first);
    if (buffer == NULL) {
        fail_memory(fail);
        return;
    }
    size_t capacity = first;
    size_t filled = 0;
    const bool waits = cancellable && stat != NULL && !is_regular(stat);
    for (;;) {
        if (cancellable && !check_wait(fail)) {
            break;
        }
        if (waits && !wait_readable(fd, fail)) {
            break;
        }
        const int64_t remaining = max - (int64_t)filled;
        if (filled == capacity) {
            /* Full and not at the end: double, within the one byte past `max` that detects excess. */
            size_t grown = capacity * 2 > READ_CHUNK ? capacity * 2 : READ_CHUNK;
            if (grown > max_size + 1) {
                grown = max_size + 1;
            }
            uint8_t *bigger = grown > capacity ? realloc(buffer, grown) : NULL;
            if (bigger == NULL) {
                fail_memory(fail);
                break;
            }
            buffer = bigger;
            capacity = grown;
        }
        size_t room = capacity - filled;
        room = room < READ_LARGEST ? room : READ_LARGEST;
        const size_t want = remaining < (int64_t)room ? (size_t)remaining + 1 : room;
        size_t count = 0;
        if (ms_sys_fs_read(fd, buffer + filled, want, &count) != 0) {
            ms_fs_fail_status(fail, STATUS_INVALID_DATA);
            break;
        }
        if ((int64_t)count > remaining) {
            ms_fs_fail_status(fail, STATUS_LIMIT_EXCEEDED);
            break;
        }
        if (count == 0) {
            out->data = buffer;
            out->length = filled;
            out->capacity = capacity;
            return;
        }
        filled += count;
    }
    free(buffer);
}

/* Writes all of `data`, in small steps when cancellable so a stop request is seen between them. */
static void write_all(MsSysFd fd, MsBytes data, MsBytes path, bool cancellable, MsFsFail *fail) {
    const size_t step = cancellable ? WRITE_STEP : WRITE_JOB_STEP;
    size_t done = 0;
    while (done < data.len) {
        if (cancellable && ms_fs_poll_cancel(fail)) {
            return;
        }
        const size_t end = data.len - done < step ? data.len - done : step;
        size_t count = 0;
        const MsSysError error = ms_sys_fs_write(fd, data.ptr + done, end, &count);
        if (error != 0) {
            ms_fs_fail_errno_at(fail, error, "write", path);
            return;
        }
        if (count == 0) {
            ms_fs_fail_text(fail, "short write");
            return;
        }
        done += count;
    }
}

/* Closes after a write: the write's own failure wins over a failed close. */
static void close_after_write(MsSysFd fd, MsBytes path, MsFsFail *fail) {
    const MsSysError error = ms_sys_fs_close(fd);
    if (error != 0 && !ms_fs_failed(fail)) {
        ms_fs_fail_errno_at(fail, error, "close", path);
    }
}

/* Opens `path` for a pool job and says when it is not a regular file (a FIFO, a device, a directory), which the
 * caller then runs on the runtime thread, where a wait can be cancelled. */
static bool open_regular(FsJob *job, int32_t flags, MsSysFd *fd) {
    MsFsPath path;
    if (!open_path(&job->fail, &path, job->path)) {
        return false;
    }
    const MsSysError error = ms_sys_fs_open(path.text, flags | MS_SYS_O_NONBLOCK, 0600, fd);
    ms_fs_path_free(&path);
    if (error != 0) {
        if (is_kind(error, MS_SYS_ERR_NO_ENTRY_DEVICE)) { /* a FIFO without a reader */
            job->not_regular = true;
        } else {
            ms_fs_fail_errno_at(&job->fail, error, "open", job->path);
        }
        return false;
    }
    MsSysStat stat;
    if (ms_sys_fs_fstat(*fd, &stat) == 0 && is_regular(&stat)) {
        return true;
    }
    const MsSysError closed = ms_sys_fs_close(*fd);
    (void)closed;
    job->not_regular = true;
    return false;
}

static void read_whole_job(void *data) {
    FsJob *job = data;
    MsSysFd fd = MS_SYS_FD_INVALID;
    if (!open_regular(job, MS_SYS_O_READ, &fd)) {
        return;
    }
    ms_fs_read_limited(fd, job->number, false, NULL, &job->text, &job->fail);
    const MsSysError closed = ms_sys_fs_close(fd);
    (void)closed;
}

/* The same read on the runtime thread, for anything but a regular file. */
static void read_whole_here(FsJob *job) {
    MsFsPath path;
    if (!open_path(&job->fail, &path, job->path)) {
        return;
    }
    MsSysFd fd = MS_SYS_FD_INVALID;
    /* A named pipe opened for reading would block in open until a writer arrives, so it is opened without waiting
     * and switched back to blocking mode; reads wait for data through wait_readable. */
    MsSysError error = ms_sys_fs_open(path.text, MS_SYS_O_READ | MS_SYS_O_NONBLOCK, 0, &fd);
    ms_fs_path_free(&path);
    if (error != 0) {
        ms_fs_fail_errno_at(&job->fail, error, "open", job->path);
        return;
    }
    MsSysStat stat;
    const bool have_stat = ms_sys_fs_fstat(fd, &stat) == 0;
    if (!have_stat || !is_regular(&stat)) {
        ms_sys_fs_set_blocking(fd);
    }
    if (have_stat && is_directory(&stat)) {
        fail_invalid(&job->fail);
    } else {
        ms_fs_read_limited(fd, job->number, true, have_stat ? &stat : NULL, &job->text, &job->fail);
    }
    error = ms_sys_fs_close(fd);
    (void)error;
}

uint8_t msstd_fs_read_file(const MsStr *path, uint8_t has_max, int64_t max, MsVec *out, MsStr *err) {
    FsJob job = job_for(path);
    if (!ms_fs_limit(has_max, max, &job.number)) {
        fail_invalid(&job.fail);
    } else if (!ms_sched_pool_alone() && !ms_sched_on_pool_thread()) {
        run_job(read_whole_job, &job);
        if (job.not_regular && !ms_fs_failed(&job.fail)) {
            read_whole_here(&job);
        }
    } else {
        read_whole_here(&job);
    }
    if (!ms_fs_failed(&job.fail)) {
        msrt_write_bytes(out, job.text.data, job.text.length);
    }
    const uint8_t status = ms_fs_finish_at(&job.fail, job.path, err);
    job_free(&job);
    return status;
}

static void write_whole_job(void *data) {
    FsJob *job = data;
    MsSysFd fd = MS_SYS_FD_INVALID;
    if (!open_regular(job, MS_SYS_O_WRITE | MS_SYS_O_CREATE | (int32_t)job->number, &fd)) {
        return;
    }
    write_all(fd, job->other, job->path, false, &job->fail);
    close_after_write(fd, job->path, &job->fail);
}

static void write_whole_here(FsJob *job) {
    MsFsPath path;
    if (!open_path(&job->fail, &path, job->path)) {
        return;
    }
    MsSysFd fd = MS_SYS_FD_INVALID;
    const MsSysError error = ms_sys_fs_open(path.text, MS_SYS_O_WRITE | MS_SYS_O_CREATE | (int32_t)job->number, 0600, &fd);
    ms_fs_path_free(&path);
    if (error != 0) {
        ms_fs_fail_errno_at(&job->fail, error, "open", job->path);
        return;
    }
    write_all(fd, job->other, job->path, true, &job->fail);
    close_after_write(fd, job->path, &job->fail);
}

static uint8_t write_with(const MsStr *path, const MsVec *data, int32_t flags, MsStr *err) {
    FsJob job = job_for(path);
    job.other = ms_bytes_of(data->ptr, data->len);
    job.number = flags;
    if (!ms_sched_pool_alone() && !ms_sched_on_pool_thread()) {
        run_job(write_whole_job, &job);
        if (job.not_regular && !ms_fs_failed(&job.fail)) {
            write_whole_here(&job);
        }
    } else {
        write_whole_here(&job);
    }
    const uint8_t status = ms_fs_finish_at(&job.fail, job.path, err);
    job_free(&job);
    return status;
}

uint8_t msstd_fs_write_file(const MsStr *path, const MsVec *data, uint8_t replace, MsStr *err) {
    return write_with(path, data, replace != 0 ? MS_SYS_O_TRUNCATE : MS_SYS_O_EXCLUSIVE, err);
}

uint8_t msstd_fs_append_file(const MsStr *path, const MsVec *data, MsStr *err) {
    return write_with(path, data, MS_SYS_O_APPEND, err);
}

/* ---- metadata ---- */

static void split_time(MsSysTime time, int64_t *seconds, int64_t *nanos) {
    int64_t whole = time.seconds + time.nanos / 1000000000;
    int64_t rest = time.nanos % 1000000000;
    if (rest < 0) {
        rest += 1000000000;
        whole -= 1;
    }
    *seconds = whole;
    *nanos = rest;
}

enum {
    KIND_DIRECTORY = 1,
    KIND_SYMLINK = 2,
    KIND_REGULAR = 4,
    KIND_FIFO = 8,
    KIND_SOCKET = 16,
    KIND_BLOCK_DEVICE = 32,
    KIND_CHAR_DEVICE = 64
};

static int64_t kinds_of(uint32_t mode) {
    switch (mode & MS_SYS_S_IFMT) {
    case MS_SYS_S_IFDIR:
        return KIND_DIRECTORY;
    case MS_SYS_S_IFLNK:
        return KIND_SYMLINK;
    case MS_SYS_S_IFREG:
        return KIND_REGULAR;
    case MS_SYS_S_IFIFO:
        return KIND_FIFO;
    case MS_SYS_S_IFSOCK:
        return KIND_SOCKET;
    case MS_SYS_S_IFBLK:
        return KIND_BLOCK_DEVICE;
    case MS_SYS_S_IFCHR:
        return KIND_CHAR_DEVICE;
    default:
        return 0;
    }
}

/* Fills `out` (the name is written separately) from a stat; unsigned host counters carry their bits. */
void ms_fs_info_fill(MsFsInfo *out, const MsSysStat *stat) {
    out->size = stat->size;
    out->mode = (int64_t)(stat->mode & 0177777);
    out->permissions = (int64_t)(stat->mode & 07777);
    split_time(stat->modified, &out->modified_seconds, &out->modified_nanos);
    split_time(stat->accessed, &out->accessed_seconds, &out->accessed_nanos);
    split_time(stat->changed, &out->changed_seconds, &out->changed_nanos);
    out->created_seconds = 0;
    out->created_nanos = 0;
    out->created_present = stat->has_created ? 1 : 0;
    if (stat->has_created) {
        split_time(stat->created, &out->created_seconds, &out->created_nanos);
    }
    out->kinds = kinds_of(stat->mode);
    out->block_size = (int64_t)stat->block_size;
    out->blocks = (int64_t)stat->blocks;
    out->rdev = (int64_t)stat->rdev;
    out->device = (int64_t)stat->device;
    out->inode = (int64_t)stat->inode;
    out->links = (int64_t)stat->links;
    out->uid = (int64_t)stat->uid;
    out->gid = (int64_t)stat->gid;
}

static const char *stat_operation(bool follow) { return follow ? "stat" : "lstat"; }

static void stat_job(void *data) {
    FsJob *job = data;
    MsFsPath path;
    if (!open_path(&job->fail, &path, job->path)) {
        return;
    }
    const MsSysError error = ms_sys_fs_stat(path.text, job->flag != 0, &job->stat);
    ms_fs_path_free(&path);
    if (error != 0) {
        ms_fs_fail_errno_at(&job->fail, error, stat_operation(job->flag != 0), job->path);
        return;
    }
    /* The name is the last element of the path, as text. */
    const MsBytes base = ms_fs_path_base(job->path);
    if (!ms_fs_buffer_append_lossy(&job->text, base.ptr, base.len)) {
        fail_memory(&job->fail);
    }
}

uint8_t msstd_fs_stat(const MsStr *path, uint8_t follow, MsFsInfo *out, MsStr *err) {
    FsJob job = job_for(path);
    job.flag = follow;
    run_job(stat_job, &job);
    if (!ms_fs_failed(&job.fail)) {
        ms_fs_info_fill(out, &job.stat);
        ms_fs_write_buffer_string(&out->name, &job.text);
    }
    const uint8_t status = ms_fs_finish_at(&job.fail, job.path, err);
    job_free(&job);
    return status;
}

static void exists_job(void *data) {
    FsJob *job = data;
    MsFsPath path;
    if (!open_path(&job->fail, &path, job->path)) {
        return;
    }
    const MsSysError error = ms_sys_fs_stat(path.text, job->flag != 0, &job->stat);
    ms_fs_path_free(&path);
    if (error == 0) {
        job->found = true;
    } else if (!is_kind(error, MS_SYS_ERR_NOT_FOUND) && !is_kind(error, MS_SYS_ERR_NOT_DIRECTORY)) {
        ms_fs_fail_errno_at(&job->fail, error, stat_operation(job->flag != 0), job->path);
    }
}

/* 1 when `path` names anything, 0 when it or a directory part is missing; any other failure is an error, so a
 * permission error is not mistaken for absence. */
uint8_t msstd_fs_exists(const MsStr *path, uint8_t follow, int64_t *out, MsStr *err) {
    FsJob job = job_for(path);
    job.flag = follow;
    run_job(exists_job, &job);
    if (!ms_fs_failed(&job.fail)) {
        *out = job.found ? 1 : 0;
    }
    const uint8_t status = ms_fs_finish_at(&job.fail, job.path, err);
    job_free(&job);
    return status;
}

static void filesystem_job(void *data) {
    FsJob *job = data;
    MsFsPath path;
    if (!open_path(&job->fail, &path, job->path)) {
        return;
    }
    const MsSysError error = ms_sys_fs_stat_filesystem(path.text, &job->filesystem);
    ms_fs_path_free(&path);
    if (error != 0) {
        ms_fs_fail_errno_at(&job->fail, error, "statfs", job->path);
    }
}

uint8_t msstd_fs_stat_filesystem(const MsStr *path, MsFsFilesystem *out, MsStr *err) {
    FsJob job = job_for(path);
    run_job(filesystem_job, &job);
    if (!ms_fs_failed(&job.fail)) {
        out->kind = job.filesystem.kind;
        out->block_size = job.filesystem.block_size;
        out->blocks = job.filesystem.blocks;
        out->blocks_free = job.filesystem.blocks_free;
        out->blocks_available = job.filesystem.blocks_available;
        out->files = job.filesystem.files;
        out->files_free = job.filesystem.files_free;
    }
    const uint8_t status = ms_fs_finish_at(&job.fail, job.path, err);
    job_free(&job);
    return status;
}

/* ---- listing ---- */

typedef struct ListEntry {
    uint8_t *name; /* malloc'd, lossy UTF-8 */
    size_t length;
    bool directory;
    bool symlink;
} ListEntry;

typedef struct ListEntries {
    ListEntry *items;
    size_t count;
    size_t capacity;
} ListEntries;

static void entries_free(ListEntries *entries) {
    for (size_t i = 0; i < entries->count; i++) {
        free(entries->items[i].name);
    }
    free(entries->items);
    *entries = (ListEntries){0};
}

static bool entries_push(ListEntries *entries, ListEntry entry) {
    if (entries->count == entries->capacity) {
        size_t capacity = 0;
        if (!ms_size_mul(entries->capacity == 0 ? 16 : entries->capacity, 2, &capacity) || capacity > SIZE_MAX / sizeof(ListEntry)) {
            return false;
        }
        ListEntry *grown = realloc(entries->items, capacity * sizeof(ListEntry));
        if (grown == NULL) {
            return false;
        }
        entries->items = grown;
        entries->capacity = capacity;
    }
    entries->items[entries->count++] = entry;
    return true;
}

static int compare_entries(const void *left, const void *right) {
    const ListEntry *a = left;
    const ListEntry *b = right;
    const size_t common = a->length < b->length ? a->length : b->length;
    const int order = common == 0 ? 0 : memcmp(a->name, b->name, common);
    if (order != 0) {
        return order;
    }
    if (a->length == b->length) {
        return 0;
    }
    return a->length < b->length ? -1 : 1;
}

/* Whether an entry is a directory or a symbolic link: from the listing's own kind, or an lstat when the filesystem
 * reports none. */
void ms_fs_entry_kind(MsBytes directory, const MsSysDirEntry *entry, bool *is_dir, bool *is_symlink) {
    *is_dir = false;
    *is_symlink = false;
    if (entry->kind != MS_SYS_DT_UNKNOWN) {
        *is_dir = entry->kind == MS_SYS_DT_DIR;
        *is_symlink = entry->kind == MS_SYS_DT_LNK;
        return;
    }
    MsFsBuffer full = {0};
    MsFsPath path;
    if (ms_fs_path_join(directory, ms_bytes_of((const uint8_t *)entry->name, entry->name_length), &full) &&
        ms_fs_path_init(&path, ms_fs_buffer_view(&full))) {
        MsSysStat stat;
        if (ms_sys_fs_stat(path.text, false, &stat) == 0) {
            *is_dir = is_directory(&stat);
            *is_symlink = is_link(&stat);
        }
        ms_fs_path_free(&path);
    }
    ms_fs_buffer_free(&full);
}

typedef struct ListJob {
    FsJob base;
    ListEntries entries;
} ListJob;

/* Adds one directory entry to the job's list, or fails the job. */
static void list_add(ListJob *job, const MsSysDirEntry *entry) {
    MsFsFail *fail = &job->base.fail;
    if ((int64_t)job->entries.count >= job->base.number) {
        ms_fs_fail_status(fail, STATUS_LIMIT_EXCEEDED);
        return;
    }
    ListEntry item = {0};
    ms_fs_entry_kind(job->base.path, entry, &item.directory, &item.symlink);
    MsFsBuffer name = {0};
    if (!ms_fs_buffer_append_lossy(&name, (const uint8_t *)entry->name, entry->name_length)) {
        ms_fs_buffer_free(&name);
        fail_memory(fail);
        return;
    }
    item.name = name.data;
    item.length = name.length;
    if (!entries_push(&job->entries, item)) {
        free(item.name);
        fail_memory(fail);
    }
}

/* Reads every entry of the open directory into the job. */
static void list_read_all(ListJob *job, MsSysDir *dir) {
    MsFsFail *fail = &job->base.fail;
    while (!ms_fs_failed(fail)) {
        MsSysDirEntry entry;
        bool found = false;
        const MsSysError error = ms_sys_fs_dir_read(dir, &entry, &found);
        if (error != 0) {
            ms_fs_fail_errno_at(fail, error, "readdirent", job->base.path);
            return;
        }
        if (!found || ms_fs_poll_cancel(fail)) {
            return;
        }
        list_add(job, &entry);
    }
}

static void list_job(void *data) {
    ListJob *job = data;
    MsFsFail *fail = &job->base.fail;
    MsFsPath path;
    if (!open_path(fail, &path, job->base.path)) {
        return;
    }
    MsSysStat stat;
    MsSysDir *dir = NULL;
    MsSysError error = ms_sys_fs_stat(path.text, true, &stat);
    if (error != 0) {
        ms_fs_fail_errno_at(fail, error, "open", job->base.path);
    } else if (!is_directory(&stat)) {
        fail_invalid(fail);
    } else {
        error = ms_sys_fs_dir_open(path.text, &dir);
        if (error != 0) {
            ms_fs_fail_errno_at(fail, error, "readdirent", job->base.path);
        }
    }
    ms_fs_path_free(&path);
    if (dir != NULL) {
        list_read_all(job, dir);
        ms_sys_fs_dir_close(dir);
    }
    if (!ms_fs_failed(fail) && job->entries.count > 1) {
        qsort(job->entries.items, job->entries.count, sizeof(ListEntry), compare_entries);
    }
}

static void entry_drop(const uint8_t *slot) {
    MsFsEntry entry;
    memcpy(&entry, slot, sizeof entry);
    msrt_string_free(&entry.name);
}

static void entry_copy(const uint8_t *source, uint8_t *destination) {
    MsFsEntry entry;
    memcpy(&entry, source, sizeof entry);
    MsFsEntry copy = entry;
    msrt_string_clone(&entry.name, &copy.name);
    memcpy(destination, &copy, sizeof copy);
}

static const MsTypeDesc entry_desc = {
    .size = sizeof(MsFsEntry),
    .align = _Alignof(MsFsEntry),
    .kind = MS_TYPE_KIND_CUSTOM,
    .drop = entry_drop,
    .copy = entry_copy,
};

uint8_t msstd_fs_list(const MsStr *path, uint8_t has_limit, int64_t limit, MsVec *out, MsStr *err) {
    ListJob job = {.base = job_for(path)};
    if (!ms_fs_limit(has_limit, limit, &job.base.number)) {
        fail_invalid(&job.base.fail);
    } else {
        ms_fs_run(list_job, &job, &job.base.fail);
    }
    if (!ms_fs_failed(&job.base.fail)) {
        msrt_list_with_capacity(&entry_desc, (int64_t)job.entries.count, out);
        for (size_t i = 0; i < job.entries.count; i++) {
            MsFsEntry entry = {.directory = job.entries.items[i].directory ? 1 : 0, .symlink = job.entries.items[i].symlink ? 1 : 0};
            msrt_string_from_bytes(job.entries.items[i].name, job.entries.items[i].length, &entry.name);
            msrt_list_push(out, &entry_desc, &entry);
        }
    }
    const uint8_t status = ms_fs_finish_at(&job.base.fail, job.base.path, err);
    entries_free(&job.entries);
    job_free(&job.base);
    return status;
}

/* ---- directories, removal and links ---- */

/* Creates `path` and its missing ancestors; an existing directory is not an error. */
static MsSysError make_directories(MsBytes path, uint32_t mode, size_t depth) {
    MsFsPath text;
    if (!ms_fs_path_init(&text, path)) {
        return ms_sys_fs_error_of(MS_SYS_ERR_INVALID);
    }
    MsSysError error = ms_sys_fs_mkdir(text.text, mode);
    if (error == 0) {
        ms_fs_path_free(&text);
        return 0;
    }
    if (is_kind(error, MS_SYS_ERR_NOT_FOUND) && depth < 4096) {
        MsFsBuffer parent = {0};
        const bool parted = ms_fs_path_dir(path, &parent);
        const bool progress = parted && parent.length > 0 && !(parent.length == path.len && memcmp(parent.data, path.ptr, path.len) == 0);
        if (progress) {
            error = make_directories(ms_fs_buffer_view(&parent), mode, depth + 1);
            if (error == 0) {
                error = ms_sys_fs_mkdir(text.text, mode);
            }
        }
        ms_fs_buffer_free(&parent);
        if (error == 0) {
            ms_fs_path_free(&text);
            return 0;
        }
    }
    if (!is_kind(error, MS_SYS_ERR_NOT_FOUND)) {
        MsSysStat stat;
        if (ms_sys_fs_stat(text.text, true, &stat) == 0 && is_directory(&stat)) {
            error = 0;
        }
    }
    ms_fs_path_free(&text);
    return error;
}

static void create_directory_job(void *data) {
    FsJob *job = data;
    MsFsPath path;
    if (!open_path(&job->fail, &path, job->path)) {
        return;
    }
    const MsSysError error = job->flag != 0 ? make_directories(job->path, 0700, 0) : ms_sys_fs_mkdir(path.text, 0700);
    ms_fs_path_free(&path);
    if (error != 0) {
        ms_fs_fail_errno_at(&job->fail, error, "mkdir", job->path);
    }
}

uint8_t msstd_fs_create_directory(const MsStr *path, uint8_t recursive, MsStr *err) {
    FsJob job = job_for(path);
    job.flag = recursive;
    run_job(create_directory_job, &job);
    const uint8_t status = ms_fs_finish_at(&job.fail, job.path, err);
    job_free(&job);
    return status;
}

/* os.Remove: as a file, then as a directory. */
MsSysError ms_fs_remove_one(const char *path) {
    const MsSysError first = ms_sys_fs_unlink(path);
    if (first == 0) {
        return 0;
    }
    const MsSysError second = ms_sys_fs_rmdir(path);
    if (second == 0) {
        return 0;
    }
    return is_kind(second, MS_SYS_ERR_NOT_DIRECTORY) ? first : second;
}

/* Removes the directory tree at `path` without following links. */
static MsSysError remove_directory_tree(MsBytes path, size_t depth, MsFsFail *fail) {
    MsFsPath text;
    if (!ms_fs_path_init(&text, path)) {
        return ms_sys_fs_error_of(MS_SYS_ERR_INVALID);
    }
    MsSysDir *dir = NULL;
    MsSysError error = ms_sys_fs_dir_open(text.text, &dir);
    while (error == 0) {
        MsSysDirEntry entry;
        bool found = false;
        if (ms_fs_poll_cancel(fail)) {
            error = ms_sys_fs_error_of(MS_SYS_ERR_IO);
            break;
        }
        error = ms_sys_fs_dir_read(dir, &entry, &found);
        if (error != 0 || !found) {
            break;
        }
        MsFsBuffer child = {0};
        const bool built = ms_fs_buffer_append(&child, path.ptr, path.len) &&
                           (path.len > 0 && ms_fs_is_separator(path.ptr[path.len - 1]) ? true : ms_fs_buffer_push(&child, ms_fs_separator())) &&
                           ms_fs_buffer_append(&child, (const uint8_t *)entry.name, entry.name_length);
        if (!built) {
            ms_fs_buffer_free(&child);
            error = ms_sys_fs_error_of(MS_SYS_ERR_IO);
            fail_memory(fail);
            break;
        }
        MsFsPath child_text;
        if (!ms_fs_path_init(&child_text, ms_fs_buffer_view(&child))) {
            error = ms_sys_fs_error_of(MS_SYS_ERR_INVALID);
        } else {
            MsSysStat stat;
            error = ms_sys_fs_stat(child_text.text, false, &stat);
            if (error == 0 && is_directory(&stat)) {
                error = depth < 4096 ? remove_directory_tree(ms_fs_buffer_view(&child), depth + 1, fail) : ms_sys_fs_error_of(MS_SYS_ERR_IO);
            } else if (error == 0 || !is_kind(error, MS_SYS_ERR_NOT_FOUND)) {
                error = ms_sys_fs_unlink(child_text.text);
            } else {
                error = 0;
            }
            ms_fs_path_free(&child_text);
        }
        ms_fs_buffer_free(&child);
    }
    if (dir != NULL) {
        ms_sys_fs_dir_close(dir);
    }
    if (error == 0) {
        error = ms_sys_fs_rmdir(text.text);
    }
    ms_fs_path_free(&text);
    return error;
}

/* The tree at `path`; a missing path is already removed. */
void ms_fs_remove_tree(MsBytes path, MsFsFail *fail) {
    if (ms_fs_poll_cancel(fail)) {
        return;
    }
    MsFsPath text;
    if (!open_path(fail, &text, path)) {
        return;
    }
    MsSysStat stat;
    MsSysError error = ms_sys_fs_stat(text.text, false, &stat);
    if (error != 0) {
        ms_fs_path_free(&text);
        if (!is_kind(error, MS_SYS_ERR_NOT_FOUND)) {
            ms_fs_fail_errno_at(fail, error, "lstat", path);
        }
        return;
    }
    error = is_directory(&stat) ? remove_directory_tree(path, 0, fail) : ms_sys_fs_unlink(text.text);
    ms_fs_path_free(&text);
    if (error != 0 && !ms_fs_failed(fail)) {
        ms_fs_fail_errno_at(fail, error, "remove", path);
    }
}

/* The absolute, canonical form of an existing path, or false with the host error. */
MsSysError ms_fs_eval_symlinks(MsBytes path, MsFsBuffer *out) {
    MsFsPath text;
    if (!ms_fs_path_init(&text, path)) {
        return ms_sys_fs_error_of(MS_SYS_ERR_INVALID);
    }
    char *resolved = NULL;
    size_t length = 0;
    const MsSysError error = ms_sys_fs_canonicalize(text.text, &resolved, &length);
    ms_fs_path_free(&text);
    if (error != 0) {
        return error;
    }
    const bool kept = ms_fs_buffer_append(out, (const uint8_t *)resolved, length);
    free(resolved);
    return kept ? 0 : ms_sys_fs_error_of(MS_SYS_ERR_IO);
}

bool ms_fs_same_file(const MsSysStat *a, const MsSysStat *b) { return a->device == b->device && a->inode == b->inode; }

/* `given` as an absolute path without trailing separators; false (the root itself is refused as invalid) with `fail`
 * set. */
static bool removal_candidate(MsBytes given, MsBytes cwd, MsFsBuffer *joined, MsFsFail *fail) {
    MsFsBuffer clean = {0};
    MsFsBuffer parent = {0};
    const bool built = ms_fs_is_absolute(given) ? ms_fs_buffer_append(joined, given.ptr, given.len) : ms_fs_path_join(cwd, given, joined);
    bool ok = false;
    if (!built || !ms_fs_path_clean(ms_fs_buffer_view(joined), &clean) || !ms_fs_path_dir(ms_fs_buffer_view(&clean), &parent)) {
        fail_memory(fail);
    } else if (ms_bytes_equal(ms_fs_buffer_view(&parent), ms_fs_buffer_view(&clean))) {
        fail_invalid(fail);
    } else {
        while (joined->length > 1 && ms_fs_is_separator(joined->data[joined->length - 1])) {
            joined->length--;
        }
        ok = true;
    }
    ms_fs_buffer_free(&clean);
    ms_fs_buffer_free(&parent);
    return ok;
}

/* Fails `fail` as invalid when `info` is the directory at `start` or one of its ancestors. `start` is consumed. */
static bool refuse_ancestors(const MsSysStat *info, MsFsBuffer *start, MsFsFail *fail) {
    MsFsBuffer ancestor = *start;
    *start = (MsFsBuffer){0};
    bool ok = true;
    for (;;) {
        MsFsPath at;
        if (!open_path(fail, &at, ms_fs_buffer_view(&ancestor))) {
            ok = false;
            break;
        }
        MsSysStat up;
        const MsSysError up_error = ms_sys_fs_stat(at.text, true, &up);
        ms_fs_path_free(&at);
        if (up_error != 0) {
            ms_fs_fail_errno_at(fail, up_error, "stat", ms_fs_buffer_view(&ancestor));
            ok = false;
            break;
        }
        if (ms_fs_same_file(info, &up)) {
            fail_invalid(fail);
            ok = false;
            break;
        }
        MsFsBuffer next = {0};
        if (!ms_fs_path_dir(ms_fs_buffer_view(&ancestor), &next)) {
            fail_memory(fail);
            ok = false;
        } else if (ms_bytes_equal(ms_fs_buffer_view(&next), ms_fs_buffer_view(&ancestor))) {
            ms_fs_buffer_free(&next);
            break;
        }
        ms_fs_buffer_free(&ancestor);
        ancestor = next;
        if (!ok) {
            break;
        }
    }
    ms_fs_buffer_free(&ancestor);
    return ok;
}

/* The path to remove: refuses the working directory, its ancestors and the root before anything is touched. */
static bool removal_path(MsBytes given, MsFsBuffer *out, MsFsFail *fail) {
    const MsBytes base_name = ms_fs_path_base(given);
    const uint8_t dot[] = {'.'};
    const uint8_t dots[] = {'.', '.'};
    if (given.len == 0 || ms_bytes_equal(base_name, ms_bytes_of(dot, 1)) || ms_bytes_equal(base_name, ms_bytes_of(dots, 2))) {
        fail_invalid(fail);
        return false;
    }
    char *cwd_text = NULL;
    size_t cwd_length = 0;
    if (ms_sys_fs_current_directory(&cwd_text, &cwd_length) != 0) {
        fail_invalid(fail);
        return false;
    }
    const MsBytes cwd = ms_bytes_of((const uint8_t *)cwd_text, cwd_length);
    MsFsBuffer joined = {0};
    MsFsBuffer canonical_cwd = {0};
    bool ok = removal_candidate(given, cwd, &joined, fail);
    const MsSysError cwd_error = ok ? ms_fs_eval_symlinks(cwd, &canonical_cwd) : 0;
    if (cwd_error != 0) {
        ms_fs_fail_errno_at(fail, cwd_error, "lstat", cwd);
        ok = false;
    }
    MsSysStat info;
    MsSysError info_error = ms_sys_fs_error_of(MS_SYS_ERR_NOT_FOUND);
    MsFsPath target;
    if (ok && open_path(fail, &target, ms_fs_buffer_view(&joined))) {
        info_error = ms_sys_fs_stat(target.text, false, &info);
        ms_fs_path_free(&target);
        if (info_error != 0 && !is_kind(info_error, MS_SYS_ERR_NOT_FOUND)) {
            ms_fs_fail_errno_at(fail, info_error, "lstat", ms_fs_buffer_view(&joined));
            ok = false;
        }
    } else {
        ok = false;
    }
    if (ok && info_error == 0 && is_directory(&info)) {
        ok = refuse_ancestors(&info, &canonical_cwd, fail);
    }
    if (ok) {
        *out = joined;
        joined = (MsFsBuffer){0};
    }
    free(cwd_text);
    ms_fs_buffer_free(&joined);
    ms_fs_buffer_free(&canonical_cwd);
    return ok;
}

static void remove_job(void *data) {
    FsJob *job = data;
    MsFsPath check;
    if (!open_path(&job->fail, &check, job->path)) {
        return;
    }
    ms_fs_path_free(&check);
    MsFsBuffer target = {0};
    if (!removal_path(job->path, &target, &job->fail)) {
        return;
    }
    if (job->flag != 0) {
        ms_fs_remove_tree(ms_fs_buffer_view(&target), &job->fail);
    } else {
        MsFsPath text;
        if (open_path(&job->fail, &text, ms_fs_buffer_view(&target))) {
            const MsSysError error = ms_fs_remove_one(text.text);
            ms_fs_path_free(&text);
            if (error != 0) {
                ms_fs_fail_errno_at(&job->fail, error, "remove", ms_fs_buffer_view(&target));
            }
        }
    }
    ms_fs_buffer_free(&target);
}

uint8_t msstd_fs_remove(const MsStr *path, uint8_t recursive, MsStr *err) {
    FsJob job = job_for(path);
    job.flag = recursive;
    run_job(remove_job, &job);
    const uint8_t status = ms_fs_finish_at(&job.fail, job.path, err);
    job_free(&job);
    return status;
}

/* A two-path operation: `first` and `second` as validated paths, run through `call`. */
typedef MsSysError (*PairCall)(const char *first, const char *second);

static void pair_job(FsJob *job, PairCall call, const char *operation, bool swapped_text) {
    MsFsPath first;
    MsFsPath second;
    if (!open_path(&job->fail, &first, job->path)) {
        return;
    }
    if (!open_path(&job->fail, &second, job->other)) {
        ms_fs_path_free(&first);
        return;
    }
    const MsSysError error = call(first.text, second.text);
    ms_fs_path_free(&first);
    ms_fs_path_free(&second);
    if (error != 0) {
        const MsBytes both[2] = {swapped_text ? job->other : job->path, swapped_text ? job->path : job->other};
        ms_fs_fail_errno(&job->fail, error, operation, both, 2);
    }
}

static void rename_job(void *data) { pair_job(data, ms_sys_fs_rename, "rename", false); }
static void hard_link_job(void *data) { pair_job(data, ms_sys_fs_link, "link", false); }

static MsSysError symlink_call(const char *path, const char *target) { return ms_sys_fs_symlink(target, path); }

/* The link at `path` names `target`; the text reads `symlink <target> <path>`. */
static void create_link_job(void *data) { pair_job(data, symlink_call, "symlink", true); }

uint8_t msstd_fs_rename(const MsStr *source, const MsStr *destination, MsStr *err) {
    FsJob job = job_for(source);
    job.other = msrt_str_bytes(destination);
    run_job(rename_job, &job);
    const uint8_t status = ms_fs_finish_pair(&job.fail, job.path, job.other, err);
    job_free(&job);
    return status;
}

uint8_t msstd_fs_hard_link(const MsStr *source, const MsStr *destination, MsStr *err) {
    FsJob job = job_for(source);
    job.other = msrt_str_bytes(destination);
    run_job(hard_link_job, &job);
    const uint8_t status = ms_fs_finish(&job.fail, err);
    job_free(&job);
    return status;
}

uint8_t msstd_fs_create_link(const MsStr *path, const MsStr *target, MsStr *err) {
    FsJob job = job_for(path);
    job.other = msrt_str_bytes(target);
    run_job(create_link_job, &job);
    const uint8_t status = ms_fs_finish_at(&job.fail, job.path, err);
    job_free(&job);
    return status;
}

static void read_link_job(void *data) {
    FsJob *job = data;
    MsFsPath path;
    if (!open_path(&job->fail, &path, job->path)) {
        return;
    }
    char *target = NULL;
    size_t length = 0;
    const MsSysError error = ms_sys_fs_readlink(path.text, &target, &length);
    ms_fs_path_free(&path);
    if (error != 0) {
        ms_fs_fail_errno_at(&job->fail, error, "readlink", job->path);
        return;
    }
    if (!ms_fs_valid_utf8(ms_bytes_of((const uint8_t *)target, length))) {
        ms_fs_fail_status(&job->fail, STATUS_UNSUPPORTED);
    } else if (!ms_fs_buffer_append(&job->text, (const uint8_t *)target, length)) {
        fail_memory(&job->fail);
    }
    free(target);
}

uint8_t msstd_fs_read_link(const MsStr *path, MsStr *out, MsStr *err) {
    FsJob job = job_for(path);
    run_job(read_link_job, &job);
    if (!ms_fs_failed(&job.fail)) {
        ms_fs_write_buffer_string(out, &job.text);
    }
    const uint8_t status = ms_fs_finish_at(&job.fail, job.path, err);
    job_free(&job);
    return status;
}

static void canonicalize_job(void *data) {
    FsJob *job = data;
    MsFsPath path;
    if (!open_path(&job->fail, &path, job->path)) {
        return;
    }
    ms_fs_path_free(&path);
    const MsSysError error = ms_fs_eval_symlinks(job->path, &job->text);
    if (error != 0) {
        ms_fs_fail_errno_at(&job->fail, error, "lstat", job->path);
    } else if (!ms_fs_valid_utf8(ms_fs_buffer_view(&job->text))) {
        ms_fs_fail_status(&job->fail, STATUS_UNSUPPORTED);
    }
}

uint8_t msstd_fs_canonicalize(const MsStr *path, MsStr *out, MsStr *err) {
    FsJob job = job_for(path);
    run_job(canonicalize_job, &job);
    if (!ms_fs_failed(&job.fail)) {
        ms_fs_write_buffer_string(out, &job.text);
    }
    const uint8_t status = ms_fs_finish_at(&job.fail, job.path, err);
    job_free(&job);
    return status;
}

/* ---- temporary directories ---- */

/* The temporary directory as an absolute path, even when $TMPDIR is relative. */
static bool temporary_root(MsFsBuffer *out) {
    char *temp = NULL;
    size_t length = 0;
    if (ms_sys_fs_temp_directory(&temp, &length) != 0) {
        return false;
    }
    const MsBytes root = ms_bytes_of((const uint8_t *)temp, length);
    bool done = false;
    if (ms_fs_is_absolute(root)) {
        done = ms_fs_buffer_append(out, root.ptr, root.len);
    } else {
        char *cwd = NULL;
        size_t cwd_length = 0;
        if (ms_sys_fs_current_directory(&cwd, &cwd_length) == 0) {
            done = ms_fs_path_join(ms_bytes_of((const uint8_t *)cwd, cwd_length), root, out);
            free(cwd);
        } else {
            done = ms_fs_buffer_append(out, root.ptr, root.len);
        }
    }
    free(temp);
    return done;
}

void msstd_fs_temporary_root(MsStr *out) {
    MsFsBuffer root = {0};
    if (!temporary_root(&root)) {
        ms_fs_buffer_free(&root);
    }
    ms_fs_write_buffer_string(out, &root);
    ms_fs_buffer_free(&root);
}

static bool valid_prefix(MsBytes prefix) {
    if (prefix.len == 0) {
        return false;
    }
    for (size_t i = 0; i < prefix.len; i++) {
        if (prefix.ptr[i] == '/' || prefix.ptr[i] == '\\' || prefix.ptr[i] == 0) {
            return false;
        }
    }
    return true;
}

/* A new directory in the temporary directory named from `pattern`, where a `*` marks the random digits. The path is
 * left in `out`. */
bool ms_fs_make_temporary_directory(MsBytes pattern, MsFsBuffer *out, MsFsFail *fail) {
    if (!valid_prefix(pattern)) {
        fail_invalid(fail);
        return false;
    }
    size_t star = pattern.len;
    for (size_t i = pattern.len; i > 0; i--) {
        if (pattern.ptr[i - 1] == '*') {
            star = i - 1;
            break;
        }
    }
    const MsBytes prefix = ms_bytes_of(pattern.ptr, star);
    const MsBytes suffix = star < pattern.len ? ms_bytes_of(pattern.ptr + star + 1, pattern.len - star - 1) : ms_bytes_of(pattern.ptr, 0);
    MsFsBuffer root = {0};
    if (!temporary_root(&root) ||
        (root.length > 0 && !ms_fs_is_separator(root.data[root.length - 1]) && !ms_fs_buffer_push(&root, ms_fs_separator()))) {
        ms_fs_buffer_free(&root);
        fail_memory(fail);
        return false;
    }
    for (int tries = 0; tries < 10000; tries++) {
        MsFsBuffer name = {0};
        char digits[16];
        const int written = snprintf(digits, sizeof digits, "%u", (unsigned)ms_sys_fs_random());
        const bool built = ms_fs_buffer_append(&name, root.data, root.length) && ms_fs_buffer_append(&name, prefix.ptr, prefix.len) &&
                           written > 0 && ms_fs_buffer_append(&name, (const uint8_t *)digits, (size_t)written) &&
                           ms_fs_buffer_append(&name, suffix.ptr, suffix.len);
        MsFsPath text;
        if (!built || !ms_fs_path_init(&text, ms_fs_buffer_view(&name))) {
            ms_fs_buffer_free(&name);
            ms_fs_buffer_free(&root);
            fail_invalid(fail);
            return false;
        }
        const MsSysError error = ms_sys_fs_mkdir(text.text, 0700);
        ms_fs_path_free(&text);
        if (error == 0) {
            *out = name;
            ms_fs_buffer_free(&root);
            return true;
        }
        const bool taken = is_kind(error, MS_SYS_ERR_EXISTS);
        if (!taken) {
            ms_fs_fail_errno_at(fail, error, "mkdir", ms_fs_buffer_view(&name));
        }
        ms_fs_buffer_free(&name);
        if (!taken) {
            ms_fs_buffer_free(&root);
            return false;
        }
    }
    ms_fs_buffer_free(&root);
    ms_fs_fail_errno_at(fail, ms_sys_fs_error_of(MS_SYS_ERR_EXISTS), "mkdirtemp", pattern);
    return false;
}

uint8_t msstd_fs_temporary_directory(const MsStr *pattern, MsStr *out, MsStr *err) {
    MsFsFail fail = {0};
    MsFsBuffer path = {0};
    if (ms_fs_make_temporary_directory(msrt_str_bytes(pattern), &path, &fail)) {
        ms_fs_write_buffer_string(out, &path);
    }
    ms_fs_buffer_free(&path);
    return ms_fs_finish(&fail, err);
}

/* ---- attributes ---- */

static void chmod_job(void *data) {
    FsJob *job = data;
    MsFsPath path;
    if (!open_path(&job->fail, &path, job->path)) {
        return;
    }
    if (job->number < 0 || job->number > 07777) {
        fail_invalid(&job->fail);
    } else {
        const MsSysError error = job->flag != 0 ? ms_sys_fs_chmod(path.text, (uint32_t)job->number) : ms_sys_fs_chmod_link(path.text, (uint32_t)job->number);
        if (error != 0) {
            ms_fs_fail_errno_at(&job->fail, error, "chmod", job->path);
        }
    }
    ms_fs_path_free(&path);
}

uint8_t msstd_fs_chmod(const MsStr *path, int64_t mode, uint8_t follow, MsStr *err) {
    FsJob job = job_for(path);
    job.number = mode;
    job.flag = follow;
    run_job(chmod_job, &job);
    const uint8_t status = ms_fs_finish_at(&job.fail, job.path, err);
    job_free(&job);
    return status;
}

static void access_job(void *data) {
    FsJob *job = data;
    MsFsPath path;
    if (!open_path(&job->fail, &path, job->path)) {
        return;
    }
    if (job->number < 0 || job->number > 7) {
        fail_invalid(&job->fail);
    } else {
        const MsSysError error = ms_sys_fs_access(path.text, (int32_t)job->number);
        if (error != 0) {
            ms_fs_fail_errno_at(&job->fail, error, "access", job->path);
        }
    }
    ms_fs_path_free(&path);
}

uint8_t msstd_fs_access(const MsStr *path, int64_t mode, MsStr *err) {
    FsJob job = job_for(path);
    job.number = mode;
    run_job(access_job, &job);
    const uint8_t status = ms_fs_finish_at(&job.fail, job.path, err);
    job_free(&job);
    return status;
}

static void chown_job(void *data) {
    FsJob *job = data;
    MsFsPath path;
    if (!open_path(&job->fail, &path, job->path)) {
        return;
    }
    const int64_t largest = 2147483647;
    if (job->number < -1 || job->second_number < -1 || job->number > largest || job->second_number > largest) {
        fail_invalid(&job->fail);
    } else {
        const MsSysError error = ms_sys_fs_chown(path.text, job->number, job->second_number, job->flag != 0);
        if (error != 0) {
            ms_fs_fail_errno_at(&job->fail, error, job->flag != 0 ? "chown" : "lchown", job->path);
        }
    }
    ms_fs_path_free(&path);
}

uint8_t msstd_fs_chown(const MsStr *path, int64_t uid, int64_t gid, uint8_t follow, MsStr *err) {
    FsJob job = job_for(path);
    job.number = uid;
    job.second_number = gid;
    job.flag = follow;
    run_job(chown_job, &job);
    const uint8_t status = ms_fs_finish_at(&job.fail, job.path, err);
    job_free(&job);
    return status;
}

static void truncate_job(void *data) {
    FsJob *job = data;
    MsFsPath path;
    if (!open_path(&job->fail, &path, job->path)) {
        return;
    }
    if (job->number < 0) {
        fail_invalid(&job->fail);
    } else {
        const MsSysError error = ms_sys_fs_truncate(path.text, job->number);
        if (error != 0) {
            ms_fs_fail_errno_at(&job->fail, error, "truncate", job->path);
        }
    }
    ms_fs_path_free(&path);
}

uint8_t msstd_fs_truncate(const MsStr *path, int64_t size, MsStr *err) {
    FsJob job = job_for(path);
    job.number = size;
    run_job(truncate_job, &job);
    const uint8_t status = ms_fs_finish_at(&job.fail, job.path, err);
    job_free(&job);
    return status;
}

static void set_times_job(void *data) {
    FsJob *job = data;
    MsFsPath path;
    if (!open_path(&job->fail, &path, job->path)) {
        return;
    }
    const MsSysError error = ms_sys_fs_set_times(path.text, job->times[0], job->times[1], job->flag != 0);
    ms_fs_path_free(&path);
    if (error != 0) {
        ms_fs_fail_errno_at(&job->fail, error, "chtimes", job->path);
    }
}

uint8_t msstd_fs_set_times(const MsStr *path, const MsFsTimestamp *accessed, const MsFsTimestamp *modified, uint8_t follow,
                           MsStr *err) {
    FsJob job = job_for(path);
    job.times[0] = (MsSysTime){accessed->seconds, accessed->nanos};
    job.times[1] = (MsSysTime){modified->seconds, modified->nanos};
    job.flag = follow;
    run_job(set_times_job, &job);
    const uint8_t status = ms_fs_finish_at(&job.fail, job.path, err);
    job_free(&job);
    return status;
}
