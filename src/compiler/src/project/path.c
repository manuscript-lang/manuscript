/* Paths and project errors (project.h): Go's filepath semantics over `/`. On Windows a path also carries a volume
 * (`C:` or `//server/share`), and `\` reads as `/`, as in crates/ms-driver/src/project/pathops.rs. */
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/project.h"
#include "project/host.h"

/* ---- errors ---- */

void ms_project_error_message(MsProjectError *err, const char *message) {
    *err = (MsProjectError){.kind = MS_PERR_MESSAGE, .message = message};
}

void ms_project_error_path(MsProjectError *err, MsArena *a, const char *op, const char *path, int err_no) {
    *err = (MsProjectError){.kind = MS_PERR_PATH, .op = op, .path = ms_arena_strndup(a, path, strlen(path)), .err_no = err_no};
}

/* The Go (`syscall.Errno`) message for an errno: lower-case first letter, no `(os error N)`. */
static const char *errno_message(MsArena *a, int err_no) {
    char message[256];
    (void)ms_sys_fs_error_text(err_no, message, sizeof message);
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
    case MS_PERR_ERRNO: return host_missing(err->err_no);
    case MS_PERR_MANIFEST: return ms_project_error_not_exist(err->cause);
    case MS_PERR_MESSAGE:
    case MS_PERR_UNSUPPORTED:
    case MS_PERR_NONE: break;
    }
    return false;
}

/* ---- lexical paths ---- */

/* A separator: `/`, and `\` on Windows. */
static bool path_sep(char c) {
#ifdef _WIN32
    return c == '/' || c == '\\';
#else
    return c == '/';
#endif
}

/* A `\\?\` or `\\.\` path: its spelling is kept as written (Windows only). */
static bool path_verbatim(const char *path) {
#ifdef _WIN32
    return path[0] == '\\' && path[1] == '\\' && (path[2] == '?' || path[2] == '.') && path[3] == '\\';
#else
    (void)path;
    return false;
#endif
}

/* The bytes of the volume name that starts `path`: `C:` or `//server/share`; always 0 off Windows. */
static size_t path_volume_len(const char *path) {
#ifdef _WIN32
    if (isalpha((unsigned char)path[0]) && path[1] == ':') {
        return 2;
    }
    if (path_sep(path[0]) && path_sep(path[1]) && path[2] != 0 && !path_sep(path[2])) {
        size_t n = 2;
        for (int part = 0; part < 2; part++) {
            const size_t start = n;
            while (path[n] != 0 && !path_sep(path[n])) {
                n++;
            }
            if (n == start) {
                return 0;
            }
            if (part == 0) {
                if (path[n] == 0) {
                    return 0;
                }
                n++;
            }
        }
        return n;
    }
#else
    (void)path;
#endif
    return 0;
}

/* `path` with `\` as `/` (Windows), in the arena. */
static char *path_slashed(MsArena *a, const char *path) {
    char *copy = ms_arena_strndup(a, path, strlen(path));
#ifdef _WIN32
    for (char *c = copy; *c != 0; c++) {
        if (*c == '\\') {
            *c = '/';
        }
    }
#endif
    return copy;
}

const char *ms_path_clean(MsArena *a, const char *path) {
    if (path[0] == 0) {
        return ".";
    }
    if (path_verbatim(path)) {
        return ms_arena_strndup(a, path, strlen(path));
    }
    const char *slashed = path_slashed(a, path);
    const size_t vol = path_volume_len(slashed);
    const char *rest = slashed + vol;
    const bool rooted = rest[0] == '/';
    const size_t length = strlen(rest);
    if (length == 0 && vol > 2) {
        return slashed; /* a bare UNC share is its own root */
    }
    /* The output is the volume, then at most the rest plus a leading slash. */
    char *out = ms_alloc(a, vol + length + 3, 1);
    memcpy(out, slashed, vol);
    char *body = out + vol;
    size_t used = 0;
    size_t start = 0;
    while (start <= length) {
        size_t end = start;
        while (end < length && rest[end] != '/') {
            end++;
        }
        const size_t n = end - start;
        const char *part = rest + start;
        if (n == 0 || (n == 1 && part[0] == '.')) {
            /* nothing */
        } else if (n == 2 && part[0] == '.' && part[1] == '.') {
            /* pop the last element unless there is none or it is itself ".." */
            size_t last = used;
            while (last > 0 && body[last - 1] != '/') {
                last--;
            }
            const bool have = used > (rooted ? 1u : 0u);
            const bool last_is_dotdot = used - last == 2 && body[last] == '.' && body[last + 1] == '.';
            if (have && !last_is_dotdot) {
                used = last > 0 ? last - 1 : 0;
                if (rooted && used == 0) {
                    used = 1;
                }
            } else if (!rooted) {
                if (used > 0) {
                    body[used++] = '/';
                }
                body[used++] = '.';
                body[used++] = '.';
            }
        } else {
            if (used > 0 ? body[used - 1] != '/' : rooted) {
                body[used++] = '/';
            }
            memcpy(body + used, part, n);
            used += n;
        }
        start = end + 1;
    }
    if (used == 0) {
        body[used++] = rooted ? '/' : '.';
    }
    body[used] = 0;
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
    const size_t vol = path_volume_len(path);
    size_t split = strlen(path);
    while (split > 0 && !path_sep(path[split - 1])) {
        split--;
    }
    if (split < vol) {
        split = vol;
    }
    if (split == 0) {
        return ".";
    }
    return ms_path_clean(a, ms_arena_strndup(a, path, split));
}

const char *ms_path_base(MsArena *a, const char *path) {
    if (path[0] == 0) {
        return ".";
    }
    size_t length = strlen(path);
    while (length > 0 && path_sep(path[length - 1])) {
        length--;
    }
    const size_t vol = path_volume_len(ms_arena_strndup(a, path, length));
    if (length <= vol) {
        return "/";
    }
    size_t start = length;
    while (start > vol && !path_sep(path[start - 1])) {
        start--;
    }
    return ms_arena_strndup(a, path + start, length - start);
}

const char *ms_path_ext(const char *path) {
    size_t i = strlen(path);
    while (i > 0 && !path_sep(path[i - 1])) {
        i--;
        if (path[i] == '.') {
            return path + i;
        }
    }
    return path + strlen(path);
}

bool ms_path_is_abs(const char *path) {
#ifdef _WIN32
    const size_t vol = path_volume_len(path);
    if (vol == 0) {
        return false;
    }
    return vol > 2 || path_sep(path[vol]);
#else
    return path[0] == '/';
#endif
}

bool ms_path_escapes(const char *rel) { return strcmp(rel, "..") == 0 || strncmp(rel, "../", 3) == 0; }

bool ms_path_working_dir(MsArena *a, const char **dir, MsProjectError *err) {
    char *cwd = NULL;
    size_t length = 0;
    const MsSysError failure = ms_sys_fs_current_directory(&cwd, &length);
    if (failure != 0) {
        ms_project_error_path(err, a, "getwd", "", failure);
        return false;
    }
    *dir = ms_path_clean(a, cwd);
    ms_sys_fs_free(cwd);
    return true;
}

bool ms_path_abs(MsArena *a, const char *path, const char **out, MsProjectError *err) {
    if (path[0] == 0) {
        path = ".";
    }
    if (ms_path_is_abs(path)) {
        *out = ms_path_clean(a, path);
        return true;
    }
    const char *cwd;
    if (!ms_path_working_dir(a, &cwd, err)) {
        return false;
    }
#ifdef _WIN32
    /* `\x` is rooted on the current drive and `D:x` is relative to that drive's directory. */
    const size_t vol = path_volume_len(path);
    if (vol == 0 && path_sep(path[0])) {
        *out = ms_path_clean(a, ms_arena_fmt(a, "%.*s%s", (int)path_volume_len(cwd), cwd, path).ptr);
        return true;
    }
    if (vol == 2) {
        const size_t cwd_vol = path_volume_len(cwd);
        if (cwd_vol == 2 && tolower((unsigned char)cwd[0]) == tolower((unsigned char)path[0])) {
            *out = MS_PATH_JOIN(a, cwd, path + 2);
        } else {
            *out = ms_path_clean(a, ms_arena_fmt(a, "%.2s/%s", path, path + 2).ptr);
        }
        return true;
    }
#endif
    *out = MS_PATH_JOIN(a, cwd, path);
    return true;
}

bool ms_path_rel(MsArena *a, const char *basepath, const char *targpath, const char **out, MsProjectError *err) {
    const char *base_full = ms_path_clean(a, basepath);
    const char *targ_full = ms_path_clean(a, targpath);
    const size_t base_vol = path_volume_len(base_full), targ_vol = path_volume_len(targ_full);
    const char *base = base_full + base_vol;
    const char *targ = targ_full + targ_vol;
    if (base_vol != targ_vol) {
        goto fail;
    }
    for (size_t i = 0; i < base_vol; i++) {
        if (tolower((unsigned char)base_full[i]) != tolower((unsigned char)targ_full[i])) {
            goto fail;
        }
    }
    if (base_vol > 2) { /* a bare UNC share is a root even without a trailing separator */
        base = base[0] == 0 ? "/" : base;
        targ = targ[0] == 0 ? "/" : targ;
    }
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

#ifndef _WIN32

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
    char *target;
    size_t length;
    const MsSysError failure = ms_sys_fs_readlink(w->dest.data, &target, &length);
    if (failure != 0) {
        ms_project_error_path(err, a, "readlink", w->dest.data, failure);
        return false;
    }
    MsBuf next = {0};
    ms_buf_put(&next, target, length);
    ms_buf_put(&next, w->path.data + end, w->path.len - end);
    ms_buf_free(&w->path);
    w->path = next;
    const bool absolute = target[0] == '/';
    ms_sys_fs_free(target);
    if (absolute) {
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
    MsSysStat info;
    const MsSysError failure = ms_sys_fs_stat(w->dest.data, false, &info);
    if (failure != 0) {
        ms_project_error_path(err, a, "lstat", w->dest.data, failure);
        return false;
    }
    if (host_is_link(&info)) {
        return walk_follow(w, a, end, err);
    }
    if (!host_is_dir(&info) && end < w->path.len) {
        *err = (MsProjectError){.kind = MS_PERR_ERRNO, .err_no = HOST_NOT_DIRECTORY};
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

#else

/* The ordinary spelling of a canonical path: `C:/dir` or `//server/share/dir`, or NULL when it has none. libuv hands
 * back the ordinary form with backslashes; a `\\?\` form is read as well. */
static const char *path_ordinary(MsArena *a, const char *canonical) {
    const char *rest;
    if (strncmp(canonical, "\\\\?\\UNC\\", 8) == 0) {
        rest = canonical + 8;
        return ms_path_clean(a, ms_arena_fmt(a, "//%s", rest).ptr);
    }
    if (strncmp(canonical, "\\\\?\\", 4) == 0 && isalpha((unsigned char)canonical[4]) && canonical[5] == ':') {
        return ms_path_clean(a, canonical + 4);
    }
    if (isalpha((unsigned char)canonical[0]) && canonical[1] == ':' && (canonical[2] == '\\' || canonical[2] == '/')) {
        return ms_path_clean(a, canonical);
    }
    if (canonical[0] == '\\' && canonical[1] == '\\' && canonical[2] != '?') {
        return ms_path_clean(a, ms_arena_fmt(a, "//%s", canonical + 2).ptr);
    }
    return NULL;
}

/* A component of the canonical path that Windows would strip back (`name.` or `name `) has no ordinary spelling. */
static bool path_has_trailing_dot_or_space(const char *path) {
    for (const char *c = path; *c != 0; c++) {
        if ((*c == '.' || *c == ' ') && (c[1] == '\\' || c[1] == '/' || c[1] == 0) && c[-1] != '\\' && c[-1] != '/') {
            return true;
        }
    }
    return false;
}

/* Why `path` is missing, as the component walk of Unix reports it: the first prefix that cannot be resolved with its
 * failure, or ERROR_DIRECTORY (HOST_NOT_DIRECTORY) when a file stands where a directory should. */
static MsSysError path_missing_prefix(MsArena *a, const char *path, MsSysError original, const char **failing, bool *not_directory) {
    *failing = path;
    *not_directory = false;
    for (const char *c = path + path_volume_len(path); *c != 0; c++) {
        if (!path_sep(*c) || c == path + path_volume_len(path)) {
            continue;
        }
        const char *head = ms_arena_strndup(a, path, (size_t)(c - path));
        char *resolved;
        size_t length;
        const MsSysError failure = ms_sys_fs_canonicalize(head, &resolved, &length);
        if (failure != 0) {
            *failing = ms_path_clean(a, head);
            return failure;
        }
        ms_sys_fs_free(resolved);
        MsSysStat info;
        if (ms_sys_fs_stat(head, true, &info) == 0 && !host_is_dir(&info)) {
            *not_directory = true;
            return HOST_NOT_DIRECTORY;
        }
    }
    return original;
}

bool ms_path_eval_symlinks(MsArena *a, const char *input, const char **out, MsProjectError *err) {
    char *canonical = NULL;
    size_t length = 0;
    MsSysError failure = ms_sys_fs_canonicalize(input, &canonical, &length);
    if (failure != 0) {
        const char *failing = input;
        bool not_directory = false;
        if (ms_sys_fs_error_kind(failure) == MS_SYS_ERR_LINK_LOOP) {
            ms_project_error_message(err, "EvalSymlinks: too many links");
            return false;
        }
        if (host_missing(failure)) {
            failure = path_missing_prefix(a, input, failure, &failing, &not_directory);
        }
        if (not_directory) {
            *err = (MsProjectError){.kind = MS_PERR_ERRNO, .err_no = HOST_NOT_DIRECTORY};
            return false;
        }
        ms_project_error_path(err, a, "lstat", failing, failure);
        return false;
    }
    const char *text = ms_arena_strndup(a, canonical, length);
    ms_sys_fs_free(canonical);
    const char *ordinary = path_has_trailing_dot_or_space(text) ? NULL : path_ordinary(a, text);
    if (ordinary == NULL) {
        ms_project_error_message(err, ms_arena_fmt(a, "unsupported Windows project path %s; use names that do not require a verbatim namespace", text).ptr);
        return false;
    }
    /* The ordinary spelling must name exactly the entry the verbatim one does. */
    char *again = NULL;
    failure = ms_sys_fs_canonicalize(ordinary, &again, &length);
    const bool same = failure == 0 && strcmp(ms_arena_strndup(a, again, length), text) == 0;
    if (failure != 0) {
        ms_project_error_path(err, a, "lstat", ordinary, failure);
        return false;
    }
    ms_sys_fs_free(again);
    if (!same) {
        ms_project_error_message(err, ms_arena_fmt(a, "unsupported Windows project path %s; use names that do not require a verbatim namespace", text).ptr);
        return false;
    }
    *out = ordinary;
    return true;
}

#endif

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
