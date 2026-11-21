/* Unit test of the toolchain downloader (compiler/src/build/fetch.c): the checksum, the gzipped tar unpack, the GET with
 * redirects, retries and a refusal that is not retried, and the cached fetch end to end, against a small HTTP server on
 * the loopback in a thread of this process. */
#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

#include "ms/build_fetch.h"

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
typedef SOCKET Sock;
typedef int SendLength; /* winsock counts in int */
#define CLOSE_SOCK closesocket
#define SOCK_BAD INVALID_SOCKET
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
typedef int Sock;
typedef size_t SendLength;
#define CLOSE_SOCK close
#define SOCK_BAD (-1)
#endif

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)

static uint8_t *archive; /* the gzipped tar the server hands out */
static size_t archive_length;
static atomic_int hits_ok, hits_flaky, hits_missing, hits_archive;

/* ---- the server ---- */

static void send_all(Sock sock, const void *data, size_t length) {
    const char *at = data;
    while (length > 0) {
        const int sent = (int)send(sock, at, (SendLength)(length > 65536u ? 65536u : length), 0);
        if (sent <= 0) {
            return;
        }
        at += sent;
        length -= (size_t)sent;
    }
}

static void respond(Sock sock, int status, const char *extra, const void *body, size_t length) {
    char head[256];
    const int n = snprintf(head, sizeof head, "HTTP/1.1 %d X\r\n%sContent-Length: %zu\r\nConnection: close\r\n\r\n", status, extra, length);
    send_all(sock, head, (size_t)n);
    send_all(sock, body, length);
}

/* Reads the request head and answers by path. Returns false for /quit. */
static bool serve_one(Sock sock) {
    char head[2048];
    size_t used = 0;
    while (used < sizeof head - 1 && (used < 4 || memcmp(head + used - 4, "\r\n\r\n", 4) != 0)) {
        const int got = (int)recv(sock, head + used, 1, 0);
        if (got <= 0) {
            return true;
        }
        used += (size_t)got;
    }
    head[used] = 0;
    const char *const path = strchr(head, ' ') == NULL ? "" : strchr(head, ' ') + 1;
    if (strncmp(path, "/quit", 5) == 0) {
        respond(sock, 200, "", "", 0);
        return false;
    }
    if (strncmp(path, "/ok", 3) == 0) {
        atomic_fetch_add(&hits_ok, 1);
        respond(sock, 200, "", "hello", 5);
    } else if (strncmp(path, "/redirect", 9) == 0) {
        respond(sock, 302, "Location: /ok\r\n", "", 0);
    } else if (strncmp(path, "/flaky", 6) == 0) {
        respond(sock, atomic_fetch_add(&hits_flaky, 1) < 2 ? 503 : 200, "", "fine", 4);
    } else if (strncmp(path, "/missing", 8) == 0) {
        atomic_fetch_add(&hits_missing, 1);
        respond(sock, 404, "", "no", 2);
    } else if (strncmp(path, "/archive", 8) == 0) {
        atomic_fetch_add(&hits_archive, 1);
        respond(sock, 200, "", archive, archive_length);
    } else {
        respond(sock, 400, "", "", 0);
    }
    return true;
}

static void *server_main(void *arg) {
    const Sock listener = *(const Sock *)arg;
    bool running = true;
    while (running) {
        const Sock client = accept(listener, NULL, NULL);
        if (client == SOCK_BAD) {
            break;
        }
        running = serve_one(client);
        CLOSE_SOCK(client);
    }
    return NULL;
}

static Sock listen_on_loopback(int *port) {
    const Sock sock = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address;
    memset(&address, 0, sizeof address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    socklen_t length = sizeof address;
    if (sock == SOCK_BAD || bind(sock, (struct sockaddr *)&address, sizeof address) != 0 || listen(sock, 8) != 0 ||
        getsockname(sock, (struct sockaddr *)&address, &length) != 0) {
        return SOCK_BAD;
    }
    *port = ntohs(address.sin_port);
    return sock;
}

/* ---- the archive ---- */

typedef struct Buffer {
    uint8_t *ptr;
    size_t len;
} Buffer;

static void append(Buffer *buffer, const void *data, size_t length) {
    if (length == 0) {
        return;
    }
    buffer->ptr = realloc(buffer->ptr, buffer->len + length);
    memcpy(buffer->ptr + buffer->len, data, length);
    buffer->len += length;
}

/* One tar entry: a header block, the contents, and the padding to a block. */
static void add_entry(Buffer *tar, const char *name, char type, const uint8_t *data, size_t length) {
    uint8_t header[512] = {0};
    snprintf((char *)header, 100, "%s", name);
    snprintf((char *)header + 124, 12, "%011zo", length);
    header[156] = (uint8_t)type;
    append(tar, header, sizeof header);
    append(tar, data, length);
    const uint8_t zeros[512] = {0};
    append(tar, zeros, (512 - length % 512) % 512);
}

static void gzip(const Buffer *tar, Buffer *out) {
    z_stream stream;
    memset(&stream, 0, sizeof stream);
    deflateInit2(&stream, 6, Z_DEFLATED, 16 + MAX_WBITS, 8, Z_DEFAULT_STRATEGY);
    out->ptr = malloc(deflateBound(&stream, (uLong)tar->len));
    stream.next_in = tar->ptr;
    stream.avail_in = (uInt)tar->len;
    stream.next_out = out->ptr;
    stream.avail_out = (uInt)deflateBound(&stream, (uLong)tar->len);
    deflate(&stream, Z_FINISH);
    out->len = stream.total_out;
    deflateEnd(&stream);
}

#define BIG 70001 /* past one inflate chunk and not a multiple of a block */

static uint8_t big[BIG];

static void build_archive(void) {
    for (size_t i = 0; i < BIG; i++) {
        big[i] = (uint8_t)(i * 7 + 3);
    }
    Buffer tar = {0}, gz = {0};
    add_entry(&tar, "bin/", '5', NULL, 0);
    add_entry(&tar, "bin/tool-a", '0', big, BIG);
    add_entry(&tar, "share/other", '0', (const uint8_t *)"skipped", 7);
    add_entry(&tar, "./bin/tool-b", '0', (const uint8_t *)"bee", 3);
    add_entry(&tar, "bin/empty", '0', NULL, 0);
    const uint8_t end[1024] = {0};
    append(&tar, end, sizeof end);
    gzip(&tar, &gz);
    free(tar.ptr);
    archive = gz.ptr;
    archive_length = gz.len;
}

/* ---- the tests ---- */

static unsigned paused[8];
static size_t pauses;
static void note_pause(unsigned n) { paused[pauses++ % 8] = n; }

static char url_base[64];

static char *url_of(const char *path) {
    static char url[128];
    snprintf(url, sizeof url, "%s%s", url_base, path);
    return url;
}

static void test_checksum(void) {
    char hex[65];
    ms_fetch_sha256_hex((const uint8_t *)"abc", 3, hex);
    CHECK(strcmp(hex, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") == 0);
}

static void test_system_roots(void) {
    size_t length = 0;
    char *const roots = ms_fetch_system_roots(&length);
    CHECK(roots != NULL && length > 1000 && strstr(roots, "-----BEGIN CERTIFICATE-----") != NULL && strlen(roots) == length);
    free(roots);
}

static void test_get(void) {
    MsFetchOptions options = {.pause = note_pause};
    uint8_t *body = NULL;
    size_t length = 0;
    char why[MS_FETCH_WHY];
    CHECK(ms_fetch_get(&options, url_of("/redirect"), &body, &length, why) && length == 5 && memcmp(body, "hello", 5) == 0);
    free(body);
    pauses = 0;
    CHECK(ms_fetch_get(&options, url_of("/flaky"), &body, &length, why) && length == 4 && pauses == 2 && paused[0] == 1 && paused[1] == 2);
    free(body);
    CHECK(!ms_fetch_get(&options, url_of("/missing"), &body, &length, why) && strstr(why, "404") != NULL && atomic_load(&hits_missing) == 1);
}

static void test_unpack(const char *dir) {
    const char *const wanted[] = {"tool-a", "tool-b", "empty"};
    char why[MS_FETCH_WHY];
    CHECK(ms_fetch_unpack(archive, archive_length, wanted, 3, dir, why));
    char path[2 * MS_FETCH_PATH];
    snprintf(path, sizeof path, "%s/tool-a", dir);
    FILE *const file = fopen(path, "rb");
    uint8_t *back = malloc(BIG + 1);
    CHECK(file != NULL && fread(back, 1, BIG + 1, file) == BIG && memcmp(back, big, BIG) == 0);
    if (file != NULL) {
        fclose(file);
    }
    free(back);
    const char *const absent[] = {"tool-a", "missing"};
    CHECK(!ms_fetch_unpack(archive, archive_length, absent, 2, dir, why) && strstr(why, "every tool") != NULL);
    CHECK(!ms_fetch_unpack(archive, 10, wanted, 3, dir, why));
}

static void test_fetch_tools(const char *root) {
    const char *const files[] = {"tool-a", "tool-b"};
    char digest[65], dir[MS_FETCH_PATH], why[MS_FETCH_WHY];
    ms_fetch_sha256_hex(archive, archive_length, digest);
    MsFetchOptions options = {.name = "pin", .url = url_of("/archive"), .sha256 = digest, .files = files, .nfiles = 2,
                              .cache_root = root, .pause = note_pause};
    CHECK(ms_fetch_tools(&options, dir, why) && atomic_load(&hits_archive) == 1);
    char tool[2 * MS_FETCH_PATH];
    snprintf(tool, sizeof tool, "%s/tool-b", dir);
    FILE *const file = fopen(tool, "rb");
    CHECK(file != NULL);
    if (file != NULL) {
        fclose(file);
    }
    CHECK(strstr(dir, "pin") != NULL && ms_fetch_tools(&options, dir, why) && atomic_load(&hits_archive) == 1); /* cached */

    char other[65];
    memcpy(other, digest, sizeof other);
    other[0] = other[0] == '0' ? '1' : '0';
    options.sha256 = other;
    CHECK(!ms_fetch_tools(&options, dir, why) && strstr(why, "cannot verify pin") != NULL && strstr(why, "does not match") != NULL);
}

static void cleanup(const char *root, const char *unpacked) {
    char path[2 * MS_FETCH_PATH + 64];
    const char *const names[] = {"tool-a", "tool-b", "empty", ".ok"};
    for (size_t i = 0; i < 3; i++) {
        snprintf(path, sizeof path, "%s/%s", unpacked, names[i]);
        remove(path);
    }
    char digest[65];
    ms_fetch_sha256_hex(archive, archive_length, digest);
    for (size_t i = 0; i < 4; i++) {
        snprintf(path, sizeof path, "%s/pin/%.16s/%s", root, digest, names[i]);
        remove(path);
    }
    snprintf(path, sizeof path, "%s/pin/%.16s", root, digest);
    remove(path);
    snprintf(path, sizeof path, "%s/pin", root);
    remove(path);
    remove(unpacked);
    remove(root);
}

int main(void) {
#ifdef _WIN32
    WSADATA wsa;
    WSAStartup(MAKEWORD(2, 2), &wsa);
    _putenv_s("NO_PROXY", "127.0.0.1");
    const char *const temp = getenv("TEMP") != NULL ? getenv("TEMP") : ".";
#else
    setenv("NO_PROXY", "127.0.0.1", 1);
    unsetenv("HTTPS_PROXY");
    unsetenv("https_proxy");
    const char *const temp = getenv("TMPDIR") != NULL ? getenv("TMPDIR") : "/tmp";
#endif
    build_archive();
    int port = 0;
    Sock listener = listen_on_loopback(&port);
    CHECK(listener != SOCK_BAD);
    if (listener == SOCK_BAD) {
        return 1;
    }
    snprintf(url_base, sizeof url_base, "http://127.0.0.1:%d", port);
    pthread_t thread;
    pthread_create(&thread, NULL, server_main, &listener);

    char root[256], unpacked[300];
    snprintf(root, sizeof root, "%s/ms-fetch-test-%d", temp, port);
    snprintf(unpacked, sizeof unpacked, "%s-unpacked", root);
    CHECK(system(NULL) != 0);
    char command[MS_FETCH_PATH + 16];
    snprintf(command, sizeof command, "mkdir \"%s\"", unpacked);
    CHECK(system(command) == 0);

    test_checksum();
    test_system_roots();
    test_get();
    test_unpack(unpacked);
    test_fetch_tools(root);

    uint8_t *body = NULL;
    size_t length = 0;
    char why[MS_FETCH_WHY];
    MsFetchOptions quit = {0};
    CHECK(ms_fetch_get(&quit, url_of("/quit"), &body, &length, why));
    free(body);
    pthread_join(thread, NULL);
    CLOSE_SOCK(listener);
    cleanup(root, unpacked);
    free(archive);
    puts(failed ? "fetch_test: FAILED" : "fetch_test: ok");
    return failed;
}
