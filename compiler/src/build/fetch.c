/* Downloads and unpacks the pinned toolchain archives (compiler/include/ms/build_fetch.h). Owns the downloaded body
 * until ms_fetch_tools returns, and the staging directory until it has renamed its files or removed them.
 * Standalone: libcurl for the GET, OpenSSL's digest for the checksum, zlib's inflate for the gzip layer. */
#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif
#include "ms/build_fetch.h"

#include <curl/curl.h>
#include <openssl/evp.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <zlib.h>

#ifdef _WIN32
#include <direct.h>
#include <io.h>
#include <process.h>
#include <windows.h>
#else
#include <time.h>
#include <unistd.h>
#endif

enum { MAX_REDIRECTS = 5, DEFAULT_ATTEMPTS = 4, TAR_BLOCK = 512, INFLATE_CHUNK = 1 << 16, MAX_FILES = 16, CONNECT_SECONDS = 30, STALL_SECONDS = 60 };

#ifdef _WIN32
static const char exe_suffix[] = ".exe";
#else
static const char exe_suffix[] = "";
#endif

/* ---- the file system, in UTF-8 on every host ---- */

#ifdef _WIN32
static bool widen(const char *text, wchar_t *out, size_t capacity) {
    return MultiByteToWideChar(CP_UTF8, 0, text, -1, out, (int)capacity) > 0;
}
#define WIDE_PATH(name, text)           \
    wchar_t name[MS_FETCH_PATH];        \
    if (!widen((text), name, MS_FETCH_PATH)) { \
        return false;                   \
    }
static FILE *os_open(const char *path) {
    wchar_t wide[MS_FETCH_PATH];
    return widen(path, wide, MS_FETCH_PATH) ? _wfopen(wide, L"wb") : NULL;
}
static bool os_mkdir(const char *path) {
    WIDE_PATH(wide, path)
    return _wmkdir(wide) == 0;
}
static bool os_rmdir(const char *path) {
    WIDE_PATH(wide, path)
    return _wrmdir(wide) == 0;
}
static bool os_remove(const char *path) {
    WIDE_PATH(wide, path)
    return _wremove(wide) == 0;
}
static bool os_rename(const char *from, const char *to) {
    wchar_t a[MS_FETCH_PATH], b[MS_FETCH_PATH];
    return widen(from, a, MS_FETCH_PATH) && widen(to, b, MS_FETCH_PATH) && _wrename(a, b) == 0;
}
/* Whether `path` names a directory (`dir`) or a regular file. */
static bool os_kind_is(const char *path, bool dir) {
    struct _stat64i32 info;
    WIDE_PATH(wide, path)
    return _wstat64i32(wide, &info) == 0 && (info.st_mode & (dir ? _S_IFDIR : _S_IFREG)) != 0;
}
static void os_make_executable(const char *path) { (void)path; }
static int os_pid(void) { return _getpid(); }
static void os_sleep(unsigned seconds) { Sleep(seconds * 1000u); }
#else
static FILE *os_open(const char *path) { return fopen(path, "wbe"); }
static bool os_mkdir(const char *path) { return mkdir(path, 0777) == 0; }
static bool os_rmdir(const char *path) { return rmdir(path) == 0; }
static bool os_remove(const char *path) { return remove(path) == 0; }
static bool os_rename(const char *from, const char *to) { return rename(from, to) == 0; }
/* Whether `path` names a directory (`dir`) or a regular file. */
static bool os_kind_is(const char *path, bool dir) {
    struct stat info;
    return stat(path, &info) == 0 && (dir ? S_ISDIR(info.st_mode) : S_ISREG(info.st_mode));
}
static void os_make_executable(const char *path) { (void)chmod(path, 0755); }
static int os_pid(void) { return (int)getpid(); }
static void os_sleep(unsigned seconds) {
    const struct timespec span = {(time_t)seconds, 0};
    (void)nanosleep(&span, NULL);
}
#endif

/* Creates `path` and the directories above it. */
static bool make_dirs(const char *path) {
    char copy[MS_FETCH_PATH];
    const size_t length = strlen(path);
    if (length == 0 || length >= sizeof copy) {
        return false;
    }
    memcpy(copy, path, length + 1);
    for (size_t i = 1; i < length; i++) {
        if (copy[i] != '/' && copy[i] != '\\') {
            continue;
        }
        const char kept = copy[i];
        copy[i] = 0;
        if (!os_kind_is(copy, true) && !os_mkdir(copy) && !os_kind_is(copy, true)) {
            return false;
        }
        copy[i] = kept;
    }
    return os_kind_is(copy, true) || os_mkdir(copy) || os_kind_is(copy, true);
}

/* Writes "<a>/<b>" into `out`; false when it does not fit. */
static bool join(char out[MS_FETCH_PATH], const char *a, const char *b) {
    const int n = snprintf(out, MS_FETCH_PATH, "%s/%s", a, b);
    return n > 0 && (size_t)n < MS_FETCH_PATH;
}

MS_PRINTF(2, 3) static void say(char why[MS_FETCH_WHY], const char *format, ...) {
    va_list args;
    va_start(args, format);
    (void)vsnprintf(why, MS_FETCH_WHY, format, args);
    va_end(args);
}

/* ---- the checksum ---- */

void ms_fetch_sha256_hex(const uint8_t *data, size_t length, char out[65]) {
    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned size = 0;
    out[0] = 0;
    if (EVP_Digest(data, length, digest, &size, EVP_sha256(), NULL) != 1 || size != 32) {
        return;
    }
    for (unsigned i = 0; i < size; i++) {
        (void)snprintf(out + 2 * (size_t)i, 3, "%02x", digest[i]);
    }
}

/* ---- the download ---- */

typedef struct Body {
    uint8_t *ptr; /* owned */
    size_t len;
    size_t cap;
} Body;

typedef enum { GET_OK, GET_RETRY, GET_FATAL } GetResult;

static size_t on_body(char *chunk, size_t size, size_t count, void *user) {
    Body *const body = user;
    size_t bytes = 0, needed = 0;
    if (!ms_size_mul(size, count, &bytes) || !ms_size_add(body->len, bytes, &needed)) {
        return 0;
    }
    if (needed > body->cap) {
        size_t grown = body->cap == 0 ? 1u << 20 : body->cap;
        while (grown < needed) {
            if (!ms_size_mul(grown, 2, &grown)) {
                return 0;
            }
        }
        uint8_t *const next = realloc(body->ptr, grown);
        if (next == NULL) {
            return 0;
        }
        body->ptr = next;
        body->cap = grown;
    }
    memcpy(body->ptr + body->len, chunk, bytes);
    body->len = needed;
    return bytes;
}

static const char *proxy_from_environment(void) {
    static const char *const names[] = {"HTTPS_PROXY", "https_proxy"};
    for (size_t i = 0; i < MS_COUNT_OF(names); i++) {
        const char *const value = getenv(names[i]); // NOLINT(concurrency-mt-unsafe): read once, before any thread of ms starts a download
        if (value != NULL && value[0] != 0) {
            return value;
        }
    }
    return NULL;
}

/* Gives the easy handle its limits, proxy and roots. `roots` is the PEM text to trust, or empty for libcurl's own. */
static bool configure(CURL *easy, const char *url, Body *body, const struct curl_blob *roots) {
    const char *const proxy = proxy_from_environment();
    bool ok = curl_easy_setopt(easy, CURLOPT_URL, url) == CURLE_OK && curl_easy_setopt(easy, CURLOPT_NOSIGNAL, 1L) == CURLE_OK &&
              curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, on_body) == CURLE_OK && curl_easy_setopt(easy, CURLOPT_WRITEDATA, body) == CURLE_OK &&
              curl_easy_setopt(easy, CURLOPT_FOLLOWLOCATION, 1L) == CURLE_OK && curl_easy_setopt(easy, CURLOPT_MAXREDIRS, (long)MAX_REDIRECTS) == CURLE_OK &&
              curl_easy_setopt(easy, CURLOPT_PROTOCOLS_STR, "http,https") == CURLE_OK &&
              curl_easy_setopt(easy, CURLOPT_REDIR_PROTOCOLS_STR, "http,https") == CURLE_OK &&
              curl_easy_setopt(easy, CURLOPT_CONNECTTIMEOUT, (long)CONNECT_SECONDS) == CURLE_OK &&
              curl_easy_setopt(easy, CURLOPT_LOW_SPEED_LIMIT, 1L) == CURLE_OK && curl_easy_setopt(easy, CURLOPT_LOW_SPEED_TIME, (long)STALL_SECONDS) == CURLE_OK &&
              curl_easy_setopt(easy, CURLOPT_USERAGENT, "ms") == CURLE_OK;
    ok = ok && (proxy == NULL || curl_easy_setopt(easy, CURLOPT_PROXY, proxy) == CURLE_OK);
    ok = ok && (roots->len == 0 || curl_easy_setopt(easy, CURLOPT_CAINFO_BLOB, roots) == CURLE_OK);
#ifdef _WIN32
    ok = ok && (roots->len != 0 || curl_easy_setopt(easy, CURLOPT_SSL_OPTIONS, (long)CURLSSLOPT_NATIVE_CA) == CURLE_OK);
#endif
    return ok;
}

/* One attempt. A refusal that cannot pass (4xx but 429) is fatal; a connection failure, 5xx and 429 may pass. */
static GetResult get_once(const char *url, const struct curl_blob *roots, Body *body, char why[MS_FETCH_WHY]) {
    CURL *const easy = curl_easy_init();
    if (easy == NULL || !configure(easy, url, body, roots)) {
        curl_easy_cleanup(easy);
        say(why, "cannot set up the download of %s", url);
        return GET_FATAL;
    }
    const CURLcode code = curl_easy_perform(easy);
    long status = 0;
    (void)curl_easy_getinfo(easy, CURLINFO_RESPONSE_CODE, &status);
    curl_easy_cleanup(easy);
    if (code != CURLE_OK) {
        say(why, "%s: %s", url, curl_easy_strerror(code));
        return code == CURLE_PEER_FAILED_VERIFICATION || code == CURLE_SSL_CACERT_BADFILE ? GET_FATAL : GET_RETRY;
    }
    if (status >= 200 && status < 300) {
        return GET_OK;
    }
    say(why, "%s answered %ld", url, status);
    return status == 429 || status >= 500 ? GET_RETRY : GET_FATAL;
}

bool ms_fetch_get(const MsFetchOptions *options, const char *url, uint8_t **out, size_t *length, char why[MS_FETCH_WHY]) {
    if (curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK) {
        say(why, "cannot start libcurl");
        return false;
    }
    size_t system_length = 0;
    char *const system_roots = options->roots_pem != NULL ? NULL : ms_fetch_system_roots(&system_length);
    const char *const pem = options->roots_pem != NULL ? options->roots_pem : system_roots;
    const size_t pem_length = options->roots_pem != NULL ? strlen(options->roots_pem) : system_length;
    const struct curl_blob roots = {(void *)(uintptr_t)(pem == NULL ? "" : pem), pem == NULL ? 0 : pem_length, CURL_BLOB_COPY}; // NOLINT(performance-no-int-to-ptr): the blob's data is not const-qualified; libcurl copies it
    const unsigned attempts = options->attempts == 0 ? DEFAULT_ATTEMPTS : options->attempts;
    bool done = false;
    for (unsigned attempt = 1; attempt <= attempts && !done; attempt++) {
        Body body = {0};
        const GetResult result = get_once(url, &roots, &body, why);
        if (result == GET_OK) {
            *out = body.ptr;
            *length = body.len;
            done = true;
            continue;
        }
        free(body.ptr);
        if (result == GET_FATAL || attempt == attempts) {
            break;
        }
        if (options->pause != NULL) {
            options->pause(attempt);
        } else {
            os_sleep(attempt);
        }
    }
    free(system_roots);
    return done;
}

/* ---- the unpack ---- */

typedef struct Tar {
    uint8_t header[TAR_BLOCK];
    size_t header_used;
    uint64_t remaining; /* bytes of the entry's contents still to come */
    uint64_t padding;   /* bytes of padding after them */
    bool ended;         /* the zero block that ends the archive was read */
    FILE *out;          /* owned: the open wanted entry, or NULL */
    char out_path[MS_FETCH_PATH];
    const char *const *wanted; /* borrowed */
    size_t nwanted;
    const char *dir; /* borrowed */
    bool found[MAX_FILES];
} Tar;

static uint64_t octal(const uint8_t *field, size_t length, bool *ok) {
    uint64_t value = 0;
    size_t i = 0;
    while (i < length && (field[i] == ' ' || field[i] == 0)) {
        i++;
    }
    for (; i < length && field[i] >= '0' && field[i] <= '7'; i++) {
        value = value * 8 + (uint64_t)(field[i] - '0');
    }
    for (; i < length; i++) {
        if (field[i] != ' ' && field[i] != 0) {
            *ok = false;
        }
    }
    return value;
}

/* The wanted index of a regular entry named "bin/<base>" (a leading "./" is allowed), or -1. */
static int wanted_index(const Tar *tar, const uint8_t *header) {
    char name[101];
    memcpy(name, header, 100);
    name[100] = 0;
    const char *base = name;
    if (strncmp(base, "./", 2) == 0) {
        base += 2;
    }
    const bool regular = header[156] == 0 || header[156] == '0';
    if (!regular || strncmp(base, "bin/", 4) != 0) {
        return -1;
    }
    base += 4;
    for (size_t i = 0; i < tar->nwanted; i++) {
        if (strcmp(tar->wanted[i], base) == 0) {
            return (int)i;
        }
    }
    return -1;
}

static bool tar_close_entry(Tar *tar, char why[MS_FETCH_WHY]) {
    if (tar->out == NULL) {
        return true;
    }
    const int closed = fclose(tar->out);
    tar->out = NULL;
    if (closed != 0) {
        say(why, "%s: cannot write", tar->out_path);
        return false;
    }
    os_make_executable(tar->out_path);
    return true;
}

static bool tar_start_entry(Tar *tar, char why[MS_FETCH_WHY]) {
    bool ok = true;
    const uint64_t size = octal(tar->header + 124, 12, &ok);
    if (!ok) {
        say(why, "malformed tar header");
        return false;
    }
    tar->remaining = size;
    tar->padding = (TAR_BLOCK - size % TAR_BLOCK) % TAR_BLOCK;
    const int index = wanted_index(tar, tar->header);
    if (index < 0) {
        return true;
    }
    if (!join(tar->out_path, tar->dir, tar->wanted[index])) {
        say(why, "the path of %s is too long", tar->wanted[index]);
        return false;
    }
    tar->out = os_open(tar->out_path);
    if (tar->out == NULL) {
        say(why, "%s: cannot create", tar->out_path);
        return false;
    }
    tar->found[index] = true;
    return true;
}

/* Feeds one decompressed chunk to the entry state machine. */
static bool tar_feed(Tar *tar, const uint8_t *data, size_t length, char why[MS_FETCH_WHY]) {
    size_t at = 0;
    while (at < length && !tar->ended) {
        if (tar->remaining > 0) {
            const size_t content = (length - at) < tar->remaining ? (length - at) : (size_t)tar->remaining;
            if (tar->out != NULL && fwrite(data + at, 1, content, tar->out) != content) {
                say(why, "%s: cannot write", tar->out_path);
                return false;
            }
            at += content;
            tar->remaining -= content;
            if (tar->remaining == 0 && !tar_close_entry(tar, why)) {
                return false;
            }
            continue;
        }
        if (tar->padding > 0) {
            const size_t skipped = (length - at) < tar->padding ? (length - at) : (size_t)tar->padding;
            at += skipped;
            tar->padding -= skipped;
            continue;
        }
        const size_t take = TAR_BLOCK - tar->header_used < length - at ? TAR_BLOCK - tar->header_used : length - at;
        memcpy(tar->header + tar->header_used, data + at, take);
        tar->header_used += take;
        at += take;
        if (tar->header_used < TAR_BLOCK) {
            continue;
        }
        tar->header_used = 0;
        bool blank = true;
        for (size_t i = 0; i < TAR_BLOCK && blank; i++) {
            blank = tar->header[i] == 0;
        }
        if (blank) {
            tar->ended = true;
        } else if (!tar_start_entry(tar, why) || (tar->remaining == 0 && !tar_close_entry(tar, why))) {
            return false;
        }
    }
    return true;
}

/* Inflates `archive` (one gzip member) chunk by chunk into the tar reader. */
static bool gunzip_into_tar(const uint8_t *archive, size_t length, Tar *tar, char why[MS_FETCH_WHY]) {
    z_stream stream;
    memset(&stream, 0, sizeof stream);
    if (inflateInit2(&stream, 16 + MAX_WBITS) != Z_OK) {
        say(why, "cannot start the decompressor");
        return false;
    }
    uint8_t *const chunk = malloc(INFLATE_CHUNK);
    if (chunk == NULL) {
        (void)inflateEnd(&stream);
        say(why, "out of memory");
        return false;
    }
    if (length > UINT32_MAX) {
        free(chunk);
        (void)inflateEnd(&stream);
        say(why, "the archive is too large");
        return false;
    }
    stream.next_in = (Bytef *)(uintptr_t)archive; // NOLINT(performance-no-int-to-ptr): zlib's input is not const-qualified; inflate only reads it
    stream.avail_in = (uInt)length;
    bool ok = true;
    int status = Z_OK;
    while (ok && status == Z_OK && !tar->ended) {
        stream.next_out = chunk;
        stream.avail_out = INFLATE_CHUNK;
        status = inflate(&stream, Z_NO_FLUSH);
        if (status != Z_OK && status != Z_STREAM_END) {
            say(why, "the archive is not valid gzip (%s)", stream.msg != NULL ? stream.msg : "inflate failed");
            ok = false;
        } else {
            ok = tar_feed(tar, chunk, (size_t)(INFLATE_CHUNK - stream.avail_out), why);
        }
    }
    free(chunk);
    (void)inflateEnd(&stream);
    return ok;
}

bool ms_fetch_unpack(const uint8_t *archive, size_t length, const char *const *wanted, size_t nwanted, const char *dir,
                     char why[MS_FETCH_WHY]) {
    if (nwanted > MAX_FILES) {
        say(why, "too many tools to unpack");
        return false;
    }
    Tar tar;
    memset(&tar, 0, sizeof tar);
    tar.wanted = wanted;
    tar.nwanted = nwanted;
    tar.dir = dir;
    bool ok = gunzip_into_tar(archive, length, &tar, why);
    if (tar.out != NULL) {
        (void)fclose(tar.out);
    }
    for (size_t i = 0; ok && i < nwanted; i++) {
        if (!tar.found[i]) {
            say(why, "the archive does not hold every tool");
            ok = false;
        }
    }
    return ok;
}

/* ---- the cache ---- */

typedef struct Names {
    char files[MAX_FILES][128]; /* the tools with the host's executable suffix */
    const char *list[MAX_FILES];
} Names;

static bool names_of(const MsFetchOptions *options, Names *names) {
    if (options->nfiles > MAX_FILES) {
        return false;
    }
    for (size_t i = 0; i < options->nfiles; i++) {
        const int n = snprintf(names->files[i], sizeof names->files[i], "%s%s", options->files[i], exe_suffix);
        if (n <= 0 || (size_t)n >= sizeof names->files[i]) {
            return false;
        }
        names->list[i] = names->files[i];
    }
    return true;
}

static bool cache_complete(const char *dir, const Names *names, size_t count) {
    char path[MS_FETCH_PATH];
    if (!join(path, dir, ".ok") || !os_kind_is(path, false)) {
        return false;
    }
    for (size_t i = 0; i < count; i++) {
        if (!join(path, dir, names->list[i]) || !os_kind_is(path, false)) {
            return false;
        }
    }
    return true;
}

/* A fresh staging directory beside `root`'s <name>: ".fetch-<pid>-<n>". */
static bool make_stage(const char *parent, char stage[MS_FETCH_PATH]) {
    static atomic_uint next;
    if (!make_dirs(parent)) {
        return false;
    }
    for (int tries = 0; tries < 1000; tries++) {
        char leaf[64];
        (void)snprintf(leaf, sizeof leaf, ".fetch-%d-%u", os_pid(), atomic_fetch_add(&next, 1u));
        if (!join(stage, parent, leaf)) {
            return false;
        }
        if (os_mkdir(stage)) {
            return true;
        }
        if (!os_kind_is(stage, true)) {
            return false;
        }
    }
    return false;
}

static void remove_stage(const char *stage, const Names *names, size_t count) {
    char path[MS_FETCH_PATH];
    for (size_t i = 0; i < count; i++) {
        if (join(path, stage, names->list[i])) {
            (void)os_remove(path);
        }
    }
    (void)os_rmdir(stage);
}

/* Moves the unpacked tools into `dir` and marks it done. A concurrent build may have installed a file already. */
static bool install(const char *stage, const char *dir, const Names *names, size_t count, char cause[MS_FETCH_WHY]) {
    if (!make_dirs(dir)) {
        say(cause, "cannot create the cache directory");
        return false;
    }
    for (size_t i = 0; i < count; i++) {
        char from[MS_FETCH_PATH], to[MS_FETCH_PATH];
        if (!join(from, stage, names->list[i]) || !join(to, dir, names->list[i])) {
            say(cause, "the path of %s is too long", names->list[i]);
            return false;
        }
        (void)os_rename(from, to);
        if (!os_kind_is(to, false)) {
            say(cause, "%s is missing", names->list[i]);
            return false;
        }
    }
    char marker[MS_FETCH_PATH];
    FILE *const file = join(marker, dir, ".ok") ? os_open(marker) : NULL;
    if (file == NULL || fclose(file) != 0) {
        say(cause, "cannot finish");
        return false;
    }
    return true;
}

/* Wraps `cause` as "cannot <what> <name> into <dir>: <cause>". */
static void failed(char why[MS_FETCH_WHY], const char *what, const MsFetchOptions *options, const char *dir, const char *cause) {
    char text[MS_FETCH_WHY];
    (void)snprintf(text, sizeof text, "%s", cause);
    say(why, "cannot %s %s into %s: %s", what, options->name, dir, text);
}

/* The work between staging and installing: download, verify, unpack. `what` names the step that failed. */
static bool stage_tools(const MsFetchOptions *options, const Names *names, const char *stage, const char **what, char cause[MS_FETCH_WHY]) {
    uint8_t *archive = NULL;
    size_t length = 0;
    *what = "download";
    if (!ms_fetch_get(options, options->url, &archive, &length, cause)) {
        return false;
    }
    char digest[65];
    ms_fetch_sha256_hex(archive, length, digest);
    if (strcmp(digest, options->sha256) != 0) {
        *what = "verify";
        say(cause, "checksum %s does not match the pinned %s", digest, options->sha256);
        free(archive);
        return false;
    }
    *what = "unpack";
    const bool unpacked = ms_fetch_unpack(archive, length, names->list, options->nfiles, stage, cause);
    free(archive);
    return unpacked;
}

bool ms_fetch_tools(const MsFetchOptions *options, char dir[MS_FETCH_PATH], char why[MS_FETCH_WHY]) {
    char parent[MS_FETCH_PATH], stage[MS_FETCH_PATH], leaf[32], cause[MS_FETCH_WHY];
    Names names = {0};
    const char *what = "create the cache for";
    if (strlen(options->sha256) != 64 || !names_of(options, &names) || !join(parent, options->cache_root, options->name)) {
        say(why, "cannot fetch %s: the pin is malformed", options->name);
        return false;
    }
    (void)snprintf(leaf, sizeof leaf, "%.16s", options->sha256);
    if (!join(dir, parent, leaf)) {
        say(why, "cannot fetch %s: the cache path is too long", options->name);
        return false;
    }
    if (cache_complete(dir, &names, options->nfiles)) {
        return true;
    }
    if (!make_stage(parent, stage)) {
        failed(why, what, options, dir, "cannot create the staging directory");
        return false;
    }
    if (options->announce) {
        (void)fprintf(stderr, "ms: fetching %s (once)\n", options->name);
    }
    bool ok = stage_tools(options, &names, stage, &what, cause);
    if (ok) {
        what = "install";
        ok = install(stage, dir, &names, options->nfiles, cause);
    }
    remove_stage(stage, &names, options->nfiles);
    if (!ok) {
        failed(why, what, options, dir, cause);
    }
    return ok;
}
