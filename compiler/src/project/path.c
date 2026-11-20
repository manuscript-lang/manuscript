/* Paths and project errors (project.h): filepath semantics over `/`, POSIX file system. */
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L /* lstat, readlink; libms.c defines it first for the whole unit */
#endif
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "ms/project.h"
#include "ms_rt/sys_fs.h"

/* ---- errors ---- */

void ms_project_error_message(MsProjectError *err, const char *message) {
    *err = (MsProjectError){.kind = MS_PERR_MESSAGE, .message = message};
}

void ms_project_error_path(MsProjectError *err, MsArena *a, const char *op, const char *path, int err_no) {
    *err = (MsProjectError){.kind = MS_PERR_PATH, .op = op, .path = ms_arena_strndup(a, path, strlen(path)), .err_no = err_no};
}

/* The Go (`syscall.Errno`) message for an errno: lower-case first letter, no `(os error N)`. */
static const char *errno_message(MsArena *a, int err_no) {
    char message[128] = "unknown error";
    if (strerror_r(err_no, message, sizeof message) != 0) {
        snprintf(message, sizeof message, "errno %d", err_no);
    }
    char *text = ms_arena_strndup(a, message, strlen(message));
    if (text[0] >= 'A' && text[0] <= 'Z') {
        text[0] = (char)(text[0] - 'A' + 'a');
    }
    return text;
}

void ms_project_error_unsupported(MsProjectError *err, const char *what) {
    *err = (MsProjectError){.kind = MS_PERR_UNSUPPORTED, .message = what};
}

bool ms_project_error_is_unsupported(const MsProjectError *err) { return err->kind == MS_PERR_UNSUPPORTED; }

const char *ms_project_error_text(MsArena *a, const MsProjectError *err) {
    switch (err->kind) {
    case MS_PERR_PATH: return ms_arena_fmt(a, "%s %s: %s", err->op, err->path, errno_message(a, err->err_no)).ptr;
    case MS_PERR_ERRNO: return errno_message(a, err->err_no);
    case MS_PERR_MESSAGE:
    case MS_PERR_UNSUPPORTED: return err->message;
    case MS_PERR_MANIFEST:
        return ms_arena_fmt(a, "%s:%u:%u: %s", err->file, err->line, err->column, ms_project_error_text(a, err->cause)).ptr;
    case MS_PERR_NONE: break;
    }
    return "";
}

bool ms_project_error_not_exist(const MsProjectError *err) {
    switch (err->kind) {
    case MS_PERR_PATH:
    case MS_PERR_ERRNO: return err->err_no == ENOENT;
    case MS_PERR_MANIFEST: return ms_project_error_not_exist(err->cause);
    case MS_PERR_MESSAGE:
    case MS_PERR_UNSUPPORTED:
    case MS_PERR_NONE: break;
    }
    return false;
}

/* ---- lexical paths ---- */

const char *ms_path_clean(MsArena *a, const char *path) {
    if (path[0] == 0) {
        return ".";
    }
    const bool rooted = path[0] == '/';
    const size_t length = strlen(path);
    /* The output is never longer than the input plus a leading slash. */
    char *out = ms_alloc(a, length + 2, 1);
    size_t used = 0;
    size_t start = 0;
    while (start <= length) {
        size_t end = start;
        while (end < length && path[end] != '/') {
            end++;
        }
        const size_t n = end - start;
        const char *part = path + start;
        if (n == 0 || (n == 1 && part[0] == '.')) {
            /* nothing */
        } else if (n == 2 && part[0] == '.' && part[1] == '.') {
            /* pop the last element unless there is none or it is itself ".." */
            size_t last = used;
            while (last > 0 && out[last - 1] != '/') {
                last--;
            }
            const bool have = used > (rooted ? 1u : 0u);
            const bool last_is_dotdot = used - last == 2 && out[last] == '.' && out[last + 1] == '.';
            if (have && !last_is_dotdot) {
                used = last > 0 ? last - 1 : 0;
                if (rooted && used == 0) {
                    used = 1;
                }
            } else if (!rooted) {
                if (used > 0) {
                    out[used++] = '/';
                }
                out[used++] = '.';
                out[used++] = '.';
            }
        } else {
            if (used > 0 ? out[used - 1] != '/' : rooted) {
                out[used++] = '/';
            }
            memcpy(out + used, part, n);
            used += n;
        }
        start = end + 1;
    }
    if (used == 0) {
        out[used++] = rooted ? '/' : '.';
    }
    out[used] = 0;
    return out;
}

const char *ms_path_join(MsArena *a, const char *const *elements, size_t count) {
    MsBuf joined = {0};
    for (size_t i = 0; i < count; i++) {
        if (elements[i][0] == 0) {
            continue;
        }
        if (joined.len > 0) {
            ms_buf_putc(&joined, '/');
        }
        ms_buf_puts(&joined, elements[i]);
    }
    if (joined.len == 0) {
        ms_buf_free(&joined);
        return "";
    }
    ms_buf_putc(&joined, 0);
    const char *cleaned = ms_path_clean(a, joined.data);
    ms_buf_free(&joined);
    return cleaned;
}

const char *ms_path_dir(MsArena *a, const char *path) {
    const char *slash = strrchr(path, '/');
    if (slash == NULL) {
        return ".";
    }
    return ms_path_clean(a, ms_arena_strndup(a, path, (size_t)(slash - path) + 1));
}

const char *ms_path_base(MsArena *a, const char *path) {
    if (path[0] == 0) {
        return ".";
    }
    size_t length = strlen(path);
    while (length > 0 && path[length - 1] == '/') {
        length--;
    }
    if (length == 0) {
        return "/";
    }
    size_t start = length;
    while (start > 0 && path[start - 1] != '/') {
        start--;
    }
    return ms_arena_strndup(a, path + start, length - start);
}

const char *ms_path_ext(const char *path) {
    size_t i = strlen(path);
    while (i > 0 && path[i - 1] != '/') {
        i--;
        if (path[i] == '.') {
            return path + i;
        }
    }
    return path + strlen(path);
}

bool ms_path_is_abs(const char *path) { return path[0] == '/'; }

bool ms_path_escapes(const char *rel) { return strcmp(rel, "..") == 0 || strncmp(rel, "../", 3) == 0; }

bool ms_path_abs(MsArena *a, const char *path, const char **out, MsProjectError *err) {
    if (ms_path_is_abs(path)) {
        *out = ms_path_clean(a, path);
        return true;
    }
    char cwd[4096];
    if (getcwd(cwd, sizeof cwd) == NULL) {
        ms_project_error_path(err, a, "getwd", "", errno);
        return false;
    }
    *out = MS_PATH_JOIN(a, cwd, path);
    return true;
}

bool ms_path_rel(MsArena *a, const char *basepath, const char *targpath, const char **out, MsProjectError *err) {
    const char *base = ms_path_clean(a, basepath);
    const char *targ = ms_path_clean(a, targpath);
    if (strcmp(targ, base) == 0) {
        *out = ".";
        return true;
    }
    if (strcmp(base, ".") == 0) {
        base = "";
    }
    if (strcmp(targ, ".") == 0) {
        targ = "";
    }
    const size_t bl = strlen(base), tl = strlen(targ);
    if ((base[0] == '/') != (targ[0] == '/')) {
        goto fail;
    }
    size_t b0 = 0, bi = 0, t0 = 0, ti = 0;
    for (;;) {
        while (bi < bl && base[bi] != '/') {
            bi++;
        }
        while (ti < tl && targ[ti] != '/') {
            ti++;
        }
        if (ti - t0 != bi - b0 || memcmp(targ + t0, base + b0, ti - t0) != 0) {
            break;
        }
        if (bi < bl) {
            bi++;
        }
        if (ti < tl) {
            ti++;
        }
        b0 = bi;
        t0 = ti;
    }
    if (bi - b0 == 2 && base[b0] == '.' && base[b0 + 1] == '.') {
        goto fail;
    }
    if (b0 != bl) {
        MsBuf up = {0};
        ms_buf_puts(&up, "..");
        for (size_t i = b0; i < bl; i++) {
            if (base[i] == '/') {
                ms_buf_puts(&up, "/..");
            }
        }
        if (t0 != tl) {
            ms_buf_putc(&up, '/');
            ms_buf_put(&up, targ + t0, tl - t0);
        }
        ms_buf_putc(&up, 0);
        *out = ms_arena_strndup(a, up.data, up.len - 1);
        ms_buf_free(&up);
        return true;
    }
    *out = ms_arena_strndup(a, targ + t0, tl - t0);
    return true;
fail:
    ms_project_error_message(err, ms_arena_fmt(a, "Rel: can't make %s relative to %s", targpath, basepath).ptr);
    return false;
}

/* ---- symbolic links ---- */

enum { MAX_LINKS = 255 };

/* The walk of ms_path_eval_symlinks: `dest` is the resolved prefix, `path` what is left to resolve. */
typedef struct SymlinkWalk {
    MsBuf path, dest;
    size_t vol;   /* 1 for a rooted path */
    size_t start; /* next unread byte of `path` */
    int links;
} SymlinkWalk;

/* The last separator of dest[vol..], or -1. */
static ptrdiff_t last_separator(const SymlinkWalk *w) {
    ptrdiff_t r = (ptrdiff_t)w->dest.len - 1;
    while (r >= (ptrdiff_t)w->vol && w->dest.data[r] != '/') {
        r--;
    }
    return r;
}

/* `..`: drops the last resolved component, or keeps the `..` when there is none to drop. */
static void walk_parent(SymlinkWalk *w) {
    const ptrdiff_t r = last_separator(w);
    const size_t last = r < (ptrdiff_t)w->vol ? w->vol : (size_t)r + 1;
    const bool at_dotdot = w->dest.len - last == 2 && w->dest.data[last] == '.' && w->dest.data[last + 1] == '.';
    if (r < (ptrdiff_t)w->vol || at_dotdot) {
        if (w->dest.len > w->vol) {
            ms_buf_putc(&w->dest, '/');
        }
        ms_buf_puts(&w->dest, "..");
    } else {
        w->dest.len = (size_t)r;
    }
}

/* Replaces the link just resolved (the last component of dest, ending at path[end]) by its target. */
static bool walk_follow(SymlinkWalk *w, MsArena *a, size_t end, MsProjectError *err) {
    if (++w->links > MAX_LINKS) {
        ms_project_error_message(err, "EvalSymlinks: too many links");
        return false;
    }
    char target[4096];
    const ssize_t length = readlink(w->dest.data, target, sizeof target - 1);
    if (length < 0) {
        ms_project_error_path(err, a, "readlink", w->dest.data, errno);
        return false;
    }
    MsBuf next = {0};
    ms_buf_put(&next, target, (size_t)length);
    ms_buf_put(&next, w->path.data + end, w->path.len - end);
    ms_buf_free(&w->path);
    w->path = next;
    if (target[0] == '/') {
        w->dest.len = 0;
        ms_buf_putc(&w->dest, '/');
    } else {
        const ptrdiff_t r = last_separator(w);
        w->dest.len = r < (ptrdiff_t)w->vol ? w->vol : (size_t)r;
    }
    w->start = 0;
    return true;
}

/* Resolves the component path[start..end): appends it to dest, then follows it if it is a link. */
static bool walk_component(SymlinkWalk *w, MsArena *a, size_t end, MsProjectError *err) {
    const size_t n = end - w->start;
    const char *component = w->path.data + w->start;
    if (n == 1 && component[0] == '.') {
        w->start = end;
        return true;
    }
    if (n == 2 && component[0] == '.' && component[1] == '.') {
        walk_parent(w);
        w->start = end;
        return true;
    }
    if (w->dest.len > w->vol && w->dest.data[w->dest.len - 1] != '/') {
        ms_buf_putc(&w->dest, '/');
    }
    ms_buf_put(&w->dest, component, n);
    ms_buf_putc(&w->dest, 0);
    w->dest.len--;
    struct stat info;
    if (lstat(w->dest.data, &info) != 0) {
        ms_project_error_path(err, a, "lstat", w->dest.data, errno);
        return false;
    }
    if (S_ISLNK(info.st_mode)) {
        return walk_follow(w, a, end, err);
    }
    if (!S_ISDIR(info.st_mode) && end < w->path.len) {
        *err = (MsProjectError){.kind = MS_PERR_ERRNO, .err_no = ENOTDIR};
        return false;
    }
    w->start = end;
    return true;
}

/* filepath.EvalSymlinks: every component is resolved with lstat, and errors carry the failing prefix. */
bool ms_path_eval_symlinks(MsArena *a, const char *input, const char **out, MsProjectError *err) {
    SymlinkWalk w = {.vol = input[0] == '/' ? 1 : 0};
    ms_buf_puts(&w.path, input);
    ms_buf_put(&w.dest, input, w.vol);
    w.start = w.vol;
    bool ok = true;
    while (ok && w.start < w.path.len) {
        while (w.start < w.path.len && w.path.data[w.start] == '/') {
            w.start++;
        }
        size_t end = w.start;
        while (end < w.path.len && w.path.data[end] != '/') {
            end++;
        }
        if (end == w.start) {
            break;
        }
        ok = walk_component(&w, a, end, err);
    }
    if (ok) {
        ms_buf_putc(&w.dest, 0);
        *out = ms_path_clean(a, w.dest.data);
    }
    ms_buf_free(&w.path);
    ms_buf_free(&w.dest);
    return ok;
}

/* ---- directories ---- */

bool ms_path_list_dir(MsArena *a, const char *dir, const char *open_op, const char *const **names, uint32_t *count, MsProjectError *err) {
    MsSysDir *handle;
    MsSysError failure = ms_sys_fs_dir_open(dir, &handle);
    if (failure != 0) {
        ms_project_error_path(err, a, open_op, dir, failure);
        return false;
    }
    MsBuf found = {0};
    MsSysDirEntry entry;
    bool more = true;
    while (more && (failure = ms_sys_fs_dir_read(handle, &entry, &more)) == 0 && more) {
        MS_VEC_PUSH(found, const char *, ms_arena_strndup(a, entry.name, entry.name_length));
    }
    ms_sys_fs_dir_close(handle);
    if (failure != 0) {
        ms_buf_free(&found);
        ms_project_error_path(err, a, "readdirent", dir, failure);
        return false;
    }
    *count = (uint32_t)MS_VEC_LEN(found, const char *);
    const char **sorted = MS_NEW_N(a, const char *, *count + 1);
    for (uint32_t i = 0; i < *count; i++) {
        sorted[i] = MS_VEC_AT(found, const char *, i);
    }
    ms_buf_free(&found);
    if (*count > 1) {
        qsort(sorted, *count, sizeof(const char *), ms_cmp_cstr);
    }
    *names = sorted;
    return true;
}
