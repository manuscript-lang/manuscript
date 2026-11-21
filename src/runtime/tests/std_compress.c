#define _POSIX_C_SOURCE 200809L
/* The @std/io/archive natives (src/runtime/std/compress.c): replays the corpora recorded from Go's compress packages
 * (src/runtime/tests/oracle/compress.tsv and stream.tsv, whole-buffer and chunked decoding), and round-trips the
 * encoders at every level, format and chunk size. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

#include "ms_rt/checksum.h"
#include "ms_rt/compress.h"
#include "ms_rt/strbuild.h"
#include "fake_rt.h"

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

enum { NO_LIMIT = 0, HAS_LIMIT = 1, MAX_INPUTS = 512 };

/* A Bytes value over `storage`, a mutable copy of `text` (a string literal is const; a Bytes buffer is not). */
static MsVec bytes_in(char *storage, const char *text) {
    const size_t length = strlen(text);
    memcpy(storage, text, length);
    return (MsVec){storage, length, length};
}

static MsStr name_of(const char *text) {
    return (MsStr){.bytes = (const uint8_t *)text, .tagged = MS_STR_STATIC | strlen(text)};
}

/* The bytes a `x<hex>` token spells, in a new buffer. */
static MsVec from_hex(const char *token) {
    const size_t count = strlen(token + 1) / 2;
    uint8_t *bytes = malloc(count + 1);
    for (size_t i = 0; i < count; i++) {
        unsigned value = 0;
        (void)sscanf(token + 1 + 2 * i, "%2x", &value);
        bytes[i] = (uint8_t)value;
    }
    return (MsVec){bytes, count, count};
}

static void free_bytes(MsVec *v) {
    free(v->ptr);
    *v = (MsVec){0};
}

static const char *status_name(uint8_t status) {
    switch (status) {
    case STATUS_OK: return "ok";
    case STATUS_INVALID_INPUT: return "err InvalidInput";
    case STATUS_LIMIT_EXCEEDED: return "err LimitExceeded";
    case STATUS_INVALID_DATA: return "err InvalidData";
    case STATUS_UNSUPPORTED: return "err Unsupported";
    default: return "err Other";
    }
}

static uint32_t crc_of(const MsVec *v) { return (uint32_t)msstd_checksum_crc32(v); }

/* ---- the whole-buffer corpus ---- */

/* Splits a line at tabs, in place. */
static size_t split_tabs(char *line, char **fields, size_t cap) {
    size_t n = 0;
    for (char *p = line; p != NULL && n < cap;) {
        fields[n++] = p;
        p = strchr(p, '\t');
        if (p != NULL) *p++ = 0;
    }
    return n;
}

/* getline(3) is POSIX; Windows has no equivalent, so the replay reads lines with this. */
static long read_line(char **line, size_t *capacity, FILE *file) {
    size_t length = 0;
    for (;;) {
        if (length + 2 > *capacity) {
            const size_t grown = *capacity == 0 ? 256 : *capacity * 2;
            char *bigger = realloc(*line, grown);
            if (bigger == NULL) return -1;
            *line = bigger;
            *capacity = grown;
        }
        if (fgets(*line + length, (int)(*capacity - length), file) == NULL) return length > 0 ? (long)length : -1;
        length += strlen(*line + length);
        if (length > 0 && (*line)[length - 1] == '\n') return (long)length;
    }
}

static void replay_whole_buffer(void) {
    FILE *file = fopen("src/runtime/tests/oracle/compress.tsv", "r");
    CHECK(file != NULL);
    char *line = NULL;
    size_t line_cap = 0;
    int cases = 0;
    while (file != NULL && read_line(&line, &line_cap, file) > 0) {
        line[strcspn(line, "\n")] = 0;
        if (line[0] == '#' || line[0] == 0) continue;
        char *f[8];
        const size_t n = split_tabs(line, f, 8);
        const char *want = f[n - 1];
        const bool has_max = strcmp(f[3], "-") != 0;
        const int64_t max = has_max ? atoll(f[3]) : 0;
        const MsStr format = name_of(f[1]);
        MsVec out = {0};
        static char got[1 << 19]; /* a result is at most two hex digits per output byte */
        if (strcmp(f[0], "compress") == 0) {
            char storage[16];
            MsVec sample = bytes_in(storage, "sample");
            const uint8_t status = msstd_compress_compress(&sample, &format, atoll(f[2]), has_max, max, &out);
            snprintf(got, sizeof got, "%s", status_name(status));
        } else {
            MsVec data = from_hex(f[2]);
            const uint8_t status = msstd_compress_decompress(&data, &format, has_max, max, &out);
            int used = snprintf(got, sizeof got, "%s", status_name(status));
            if (status == STATUS_OK) {
                used += snprintf(got + used, sizeof got - (size_t)used, " x");
                for (size_t i = 0; i < out.len; i++) used += snprintf(got + used, sizeof got - (size_t)used, "%02x", ((uint8_t *)out.ptr)[i]);
            }
            free_bytes(&data);
        }
        if (strcmp(got, want) != 0) {
            printf("FAIL %s: got %.200s\n", line, got);
            failures++;
        }
        free_bytes(&out);
        cases++;
    }
    CHECK(cases > 500);
    free(line);
    if (file != NULL) fclose(file);
}

/* ---- the chunked corpus ---- */

/* Decodes `input` in `chunk`-byte pushes. Returns the status name; `produced` collects the output. */
static const char *decode_chunked(const char *format_name, bool has_max, int64_t max, const MsVec *input, size_t chunk,
                                  size_t *produced, uint32_t *crc) {
    const MsStr format = name_of(format_name);
    void *decoder = NULL;
    CHECK(msstd_compress_decoder_new(&format, has_max, max, &decoder) == STATUS_OK);
    uint8_t *all = malloc(1);
    size_t total = 0;
    uint8_t status = STATUS_OK;
    for (size_t at = 0; at <= input->len && status == STATUS_OK; at += chunk) {
        const size_t take = input->len - at < chunk ? input->len - at : chunk;
        if (take == 0 && input->len != 0) break;
        const MsVec piece = {(uint8_t *)input->ptr + at, take, take};
        MsVec out = {0};
        status = msstd_compress_decoder_push(decoder, &piece, &out);
        all = realloc(all, total + out.len + 1);
        if (out.len != 0) memcpy(all + total, out.ptr, out.len);
        total += out.len;
        free_bytes(&out);
        if (input->len == 0) break;
    }
    if (status == STATUS_OK) {
        MsVec out = {0};
        status = msstd_compress_decoder_end(decoder, &out);
        all = realloc(all, total + out.len + 1);
        if (out.len != 0) memcpy(all + total, out.ptr, out.len);
        total += out.len;
        free_bytes(&out);
    }
    const MsVec whole = {all, total, total};
    *produced = total;
    *crc = crc_of(&whole);
    free(all);
    ((MsObj *)decoder)->drop(decoder);
    return status == STATUS_LIMIT_EXCEEDED ? "err LimitExceeded" : status == STATUS_OK ? "ok" : "err InvalidData";
}

static void replay_chunked(void) {
    FILE *file = fopen("src/runtime/tests/oracle/stream.tsv", "r");
    CHECK(file != NULL);
    static MsVec inputs[MAX_INPUTS];
    char *line = NULL;
    size_t line_cap = 0;
    int cases = 0;
    while (file != NULL && read_line(&line, &line_cap, file) > 0) {
        line[strcspn(line, "\n")] = 0;
        if (line[0] == '#' || line[0] == 0) continue;
        char *f[12];
        split_tabs(line, f, 12);
        if (strcmp(f[0], "in") == 0) {
            const int id = atoi(f[1]);
            CHECK(id >= 0 && id < MAX_INPUTS);
            inputs[id] = from_hex(f[2]);
            continue;
        }
        const bool has_max = strcmp(f[3], "-") != 0;
        const int64_t max = has_max ? atoll(f[3]) : 0;
        size_t produced = 0;
        uint32_t crc = 0;
        const char *status = decode_chunked(f[1], has_max, max, &inputs[atoi(f[2])], (size_t)atoll(f[4]), &produced, &crc);
        char got[64];
        if (strcmp(status, "ok") == 0) {
            // A complete output matches exactly; the output before an error depends on the chunking.
            snprintf(got, sizeof got, "%zu\t%x\tok", produced, crc);
            if (strcmp(got, f[7] == NULL ? "" : f[7]) != 0) {
                char want[128];
                snprintf(want, sizeof want, "%s\t%s\t%s", f[7], f[8], f[9]);
                if (strcmp(got, want) != 0) { printf("FAIL dec %s in %s max %s chunk %s: got %s, want %s\n", f[1], f[2], f[3], f[4], got, want); failures++; }
            }
        } else if (strcmp(status, f[9]) != 0 || (has_max && produced > (size_t)(max < 0 ? 0 : max))) {
            printf("FAIL dec %s in %s max %s chunk %s: got %s after %zu bytes, want %s\n", f[1], f[2], f[3], f[4], status, produced, f[9]);
            failures++;
        }
        cases++;
    }
    CHECK(cases > 1000);
    free(line);
    if (file != NULL) fclose(file);
}

/* ---- the encoders ---- */

static void roundtrip_streaming(const char *format_name, int64_t level, const MsVec *data, size_t chunk) {
    const MsStr format = name_of(format_name);
    void *encoder = NULL;
    CHECK(msstd_compress_encoder_new(&format, level, &encoder) == STATUS_OK);
    uint8_t *packed = malloc(1);
    size_t packed_len = 0;
    for (size_t at = 0; at < data->len; at += chunk) {
        const size_t take = data->len - at < chunk ? data->len - at : chunk;
        const MsVec piece = {(uint8_t *)data->ptr + at, take, take};
        MsVec out = {0};
        msstd_compress_encoder_push(encoder, &piece, &out);
        packed = realloc(packed, packed_len + out.len + 1);
        if (out.len != 0) memcpy(packed + packed_len, out.ptr, out.len);
        packed_len += out.len;
        free_bytes(&out);
    }
    MsVec tail = {0};
    msstd_compress_encoder_end(encoder, &tail);
    packed = realloc(packed, packed_len + tail.len + 1);
    if (tail.len != 0) memcpy(packed + packed_len, tail.ptr, tail.len);
    packed_len += tail.len;
    free_bytes(&tail);
    ((MsObj *)encoder)->drop(encoder);

    MsVec back = {0};
    const MsVec packed_vec = {packed, packed_len, packed_len};
    CHECK(msstd_compress_decompress(&packed_vec, &format, NO_LIMIT, 0, &back) == STATUS_OK);
    CHECK(back.len == data->len && (data->len == 0 || memcmp(back.ptr, data->ptr, data->len) == 0));
    free_bytes(&back);
    free(packed);
}

static void test_encoders(void) {
    uint8_t *big = malloc(300000);
    for (uint32_t i = 0; i < 300000; i++) big[i] = (uint8_t)(i * 7 % 253);
    char hello[32];
    const MsVec inputs[] = {{NULL, 0, 0}, bytes_in(hello, "hello hello hello"), {big, 300000, 300000}};
    for (const char *const *name = (const char *const[]){"gzip", "zlib", "deflate", NULL}; *name != NULL; name++) {
        for (int64_t level = 0; level <= 9; level += 3) {
            for (size_t i = 0; i < 3; i++) {
                for (size_t chunk = 1; chunk <= 40000; chunk *= 197) {
                    if (chunk == 1 && inputs[i].len > 1000) continue; /* a byte at a time: the small inputs only */
                    roundtrip_streaming(*name, level, &inputs[i], chunk);
                }
            }
        }
    }
    free(big);
}

static void test_headers_and_errors(void) {
    const MsStr gzip = name_of("gzip"), zlib = name_of("zlib"), bz2 = name_of("bz2");
    char abc[8], def_storage[8];
    MsVec sample = bytes_in(abc, "abc"), out = {0};
    CHECK(msstd_compress_compress(&sample, &gzip, 6, NO_LIMIT, 0, &out) == STATUS_OK);
    const uint8_t *header = out.ptr;
    CHECK(header[0] == 0x1f && header[1] == 0x8b && header[2] == 8 && header[3] == 0 && header[9] == 255);
    free_bytes(&out);
    CHECK(msstd_compress_compress(&sample, &zlib, 6, NO_LIMIT, 0, &out) == STATUS_OK);
    CHECK(((uint8_t *)out.ptr)[0] == 0x78 && ((uint8_t *)out.ptr)[1] == 0x9c);
    free_bytes(&out);
    CHECK(msstd_compress_compress(&sample, &bz2, 6, NO_LIMIT, 0, &out) == STATUS_UNSUPPORTED && out.len == 0);
    CHECK(msstd_compress_compress(&sample, &gzip, 10, NO_LIMIT, 0, &out) == STATUS_INVALID_INPUT);
    CHECK(msstd_compress_compress(&sample, &gzip, -1, NO_LIMIT, 0, &out) == STATUS_INVALID_INPUT);
    void *handle = NULL;
    CHECK(msstd_compress_encoder_new(&gzip, 10, &handle) == STATUS_INVALID_INPUT);
    CHECK(msstd_compress_decoder_new(&bz2, NO_LIMIT, 0, &handle) == STATUS_UNSUPPORTED);
    // Two gzip members decode as one stream, and the limit counts both.
    MsVec first = {0}, second = {0};
    const MsVec def = bytes_in(def_storage, "def");
    CHECK(msstd_compress_compress(&sample, &gzip, 6, NO_LIMIT, 0, &first) == STATUS_OK);
    CHECK(msstd_compress_compress(&def, &gzip, 6, NO_LIMIT, 0, &second) == STATUS_OK);
    uint8_t *both = malloc(first.len + second.len);
    memcpy(both, first.ptr, first.len);
    memcpy(both + first.len, second.ptr, second.len);
    const MsVec joined = {both, first.len + second.len, first.len + second.len};
    CHECK(msstd_compress_decompress(&joined, &gzip, NO_LIMIT, 0, &out) == STATUS_OK && out.len == 6);
    free_bytes(&out);
    CHECK(msstd_compress_decompress(&joined, &gzip, HAS_LIMIT, 5, &out) == STATUS_LIMIT_EXCEEDED && out.len == 0);
    free(both);
    free_bytes(&first);
    free_bytes(&second);
}

/* Runs `ms_gunzip_step` over `z` in `chunk`-byte pieces into a `room`-byte output window, offering unused input again.
 * Returns the final status; `out` collects the output. */
static uint8_t gunzip_chunked(const uint8_t *z, size_t z_len, size_t chunk, size_t room, uint8_t *out, size_t *out_len) {
    MsGunzip *g = ms_gunzip_new();
    uint8_t status = MS_GUNZIP_OK;
    size_t fed = 0, made = 0;
    uint8_t *pending = malloc(z_len + 1);
    size_t pending_len = 0;
    for (bool more = true; more || status == MS_GUNZIP_OK;) {
        if (more) {
            const size_t take = z_len - fed < chunk ? z_len - fed : chunk;
            memcpy(pending + pending_len, z + fed, take);
            pending_len += take;
            fed += take;
            more = fed < z_len;
        }
        for (;;) {
            size_t used = 0, wrote = 0;
            status = ms_gunzip_step(g, pending, pending_len, more, out + made, room, &used, &wrote);
            memmove(pending, pending + used, pending_len - used);
            pending_len -= used;
            made += wrote;
            if (status != MS_GUNZIP_OK || (used == 0 && wrote == 0)) {
                break;
            }
        }
        if (status != MS_GUNZIP_OK) {
            break;
        }
    }
    free(pending);
    ms_gunzip_free(g);
    *out_len = made;
    return status;
}

static void test_gunzip_steps(void) {
    char storage[64];
    const MsVec sample = bytes_in(storage, "abcabcabcabcabcabcabcabc");
    MsStr gzip = name_of("gzip");
    MsVec z = {0};
    CHECK(msstd_compress_compress(&sample, &gzip, 6, NO_LIMIT, 0, &z) == STATUS_OK);
    uint8_t out[64];
    size_t made = 0;
    static const size_t chunks[] = {1, 3, 7, 4096};
    for (size_t i = 0; i < MS_COUNT_OF(chunks); i++) {
        CHECK(gunzip_chunked(z.ptr, z.len, chunks[i], 5, out, &made) == MS_GUNZIP_DONE);
        CHECK(made == sample.len && memcmp(out, sample.ptr, made) == 0);
    }
    // Truncated input, a flipped trailer checksum and trailing junk.
    CHECK(gunzip_chunked(z.ptr, z.len - 3, 4096, 64, out, &made) == MS_GUNZIP_TRUNCATED);
    CHECK(gunzip_chunked(z.ptr, 0, 4096, 64, out, &made) == MS_GUNZIP_TRUNCATED);
    uint8_t *bad = malloc(z.len + 4);
    memcpy(bad, z.ptr, z.len);
    bad[z.len - 8] ^= 1;
    CHECK(gunzip_chunked(bad, z.len, 4096, 64, out, &made) == MS_GUNZIP_INVALID);
    memcpy(bad, z.ptr, z.len);
    memcpy(bad + z.len, "junk", 4);
    CHECK(gunzip_chunked(bad, z.len + 4, 4096, 64, out, &made) == MS_GUNZIP_INVALID);
    CHECK(gunzip_chunked((const uint8_t *)"not gzip at all", 15, 4096, 64, out, &made) == MS_GUNZIP_INVALID);
    // Two members decode as one stream.
    uint8_t *both = malloc(2 * z.len);
    memcpy(both, z.ptr, z.len);
    memcpy(both + z.len, z.ptr, z.len);
    CHECK(gunzip_chunked(both, 2 * z.len, 5, 64, out, &made) == MS_GUNZIP_DONE && made == 2 * sample.len);
    free(both);
    free(bad);
    free_bytes(&z);
}

int main(void) {
    replay_whole_buffer();
    replay_chunked();
    test_encoders();
    test_headers_and_errors();
    test_gunzip_steps();
    puts(failures == 0 ? "std_compress: ok" : "std_compress: FAILED");
    return failures == 0 ? 0 : 1;
}
