/* The package cache: where packages live, the index that names their files, and the hash of that index. Port of the
 * cache half of crates/ms-driver/src/project/packages.rs. See ms/packages.h. */
#include <openssl/evp.h>
#include <stdlib.h>
#include <string.h>

#include "ms/packages.h"
#include "project/host.h"

/* The most bytes one package may hold. */
#define PACKAGE_MAX_BYTES ((uint64_t)64 << 20)
#define PACKAGE_HASH_DIGITS 64

static const char *package_env(const char *name) {
    // NOLINTNEXTLINE(concurrency-mt-unsafe): the compiler reads its environment before it starts any thread.
    const char *value = getenv(name);
    return value != NULL && value[0] != 0 ? value : NULL;
}

const char *ms_package_cache_dir(MsArena *a) {
    const char *override = package_env("MS_PACKAGE_CACHE");
    if (override != NULL) {
        return override;
    }
    const char *base = package_env("LOCALAPPDATA"); /* set on Windows only */
    if (base == NULL) {
        base = package_env("XDG_CACHE_HOME");
    }
    if (base == NULL && package_env("HOME") != NULL) {
        base = MS_PATH_JOIN(a, package_env("HOME"), ".cache");
    }
    if (base == NULL) {
        char *temporary = NULL;
        size_t length = 0;
        base = ms_sys_fs_temp_directory(&temporary, &length) == 0 ? ms_arena_strndup(a, temporary, length) : "/tmp";
        ms_sys_fs_free(temporary);
    }
    return MS_PATH_JOIN(a, base, "ms", "packages");
}

void ms_sha256_hex(const void *data, size_t length, char out[65]) {
    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int size = 0;
    if (EVP_Digest(data, length, digest, &size, EVP_sha256(), NULL) != 1 || size != PACKAGE_HASH_DIGITS / 2) {
        ms_oom(); /* OpenSSL cannot hash only when it cannot allocate */
    }
    static const char digits[] = "0123456789abcdef";
    for (size_t i = 0; i < size; i++) {
        out[2 * i] = digits[digest[i] >> 4];
        out[2 * i + 1] = digits[digest[i] & 15];
    }
    out[PACKAGE_HASH_DIGITS] = 0;
}

const char *ms_package_hash(MsArena *a, MsStr index) {
    char hex[PACKAGE_HASH_DIGITS + 1];
    ms_sha256_hex(index.ptr, index.len, hex);
    return ms_arena_strndup(a, hex, PACKAGE_HASH_DIGITS);
}

/* ---- the index ---- */

typedef struct IndexWalk {
    MsArena *arena;
    MsProjectError *err;
    MsBuf paths; /* const char *, relative with `/` */
} IndexWalk;

static bool index_collect(IndexWalk *w, const char *dir, const char *prefix) {
    const char *const *names;
    uint32_t count;
    if (!ms_path_list_dir(w->arena, dir, "read directory", &names, &count, w->err)) {
        return false;
    }
    for (uint32_t i = 0; i < count; i++) {
        const char *name = names[i];
        if (prefix[0] == 0 && strcmp(name, ".git") == 0) {
            continue;
        }
        if (!ms_utf8_valid(name, strlen(name))) {
            ms_project_error_message(w->err, ms_arena_fmt(w->arena, "package file name in %s is not valid UTF-8; rename it", dir).ptr);
            return false;
        }
        const char *relative = ms_arena_fmt(w->arena, "%s%s", prefix, name).ptr;
        const char *path = MS_PATH_JOIN(w->arena, dir, name);
        MsSysStat info;
        const MsSysError failure = ms_sys_fs_stat(path, false, &info);
        if (failure != 0) {
            ms_project_error_path(w->err, w->arena, "stat", relative, failure);
            return false;
        }
        if (host_is_link(&info)) {
            ms_project_error_message(w->err, ms_arena_fmt(w->arena, "package contains the symbolic link %s; a package holds regular files only", relative).ptr);
            return false;
        }
        if (host_is_dir(&info)) {
            if (!index_collect(w, path, ms_arena_fmt(w->arena, "%s/", relative).ptr)) {
                return false;
            }
        } else {
            MS_VEC_PUSH(w->paths, const char *, relative);
        }
    }
    return true;
}

bool ms_package_index(MsArena *a, const char *dir, MsStr *index, MsProjectError *err) {
    IndexWalk walk = {.arena = a, .err = err};
    if (!index_collect(&walk, dir, "")) {
        ms_buf_free(&walk.paths);
        return false;
    }
    const size_t count = MS_VEC_LEN(walk.paths, const char *);
    const char **paths = ms_buf_items(&walk.paths);
    if (count > 1) {
        qsort(paths, count, sizeof(const char *), ms_cmp_cstr);
    }
    MsBuf text = {0};
    uint64_t total = 0;
    bool ok = true;
    for (size_t i = 0; ok && i < count; i++) {
        const char *path = MS_PATH_JOIN(a, dir, paths[i]);
        size_t length = 0;
        const char *bytes = ms_project_read_file(a, path, &length, err);
        total += length;
        if (bytes == NULL) {
            ok = false;
        } else if (total > PACKAGE_MAX_BYTES) {
            ms_project_error_message(err, ms_arena_fmt(a, "package is larger than %u MiB; a package holds source only", (unsigned)(PACKAGE_MAX_BYTES >> 20)).ptr);
            ok = false;
        } else {
            char hex[PACKAGE_HASH_DIGITS + 1];
            ms_sha256_hex(bytes, length, hex);
            ms_buf_puts(&text, paths[i]);
            ms_buf_putc(&text, 0);
            ms_buf_put(&text, hex, PACKAGE_HASH_DIGITS);
            ms_buf_putc(&text, '\n');
        }
    }
    ms_buf_free(&walk.paths);
    if (ok) {
        *index = (MsStr){ms_arena_strndup(a, text.data == NULL ? "" : text.data, text.len), (uint32_t)text.len};
    }
    ms_buf_free(&text);
    return ok;
}

bool ms_package_cached_intact(MsArena *a, const char *cache, const char *hash) {
    MsProjectError err = {0};
    size_t length = 0;
    const char *stored = ms_project_read_file(a, MS_PATH_JOIN(a, cache, ms_arena_fmt(a, "%s.index", hash).ptr), &length, &err);
    if (stored == NULL) {
        return false;
    }
    const MsStr stored_index = {stored, (uint32_t)length};
    if (strcmp(ms_package_hash(a, stored_index), hash) != 0) {
        return false;
    }
    MsStr found;
    return ms_package_index(a, MS_PATH_JOIN(a, cache, hash), &found, &err) && found.len == stored_index.len &&
           memcmp(found.ptr, stored, found.len) == 0;
}
