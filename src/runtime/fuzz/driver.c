/* Portable mutation driver for the fuzz harnesses (the harnesses in src/runtime/fuzz). Built when libFuzzer is not used, so
   the same harness runs under any compiler and platform with AddressSanitizer and UBSan.
   Usage: driver [-n iterations] [-s seed] seed-file... Every seed file runs unchanged first; then each iteration
   mutates a randomly chosen seed (bit flips, byte sets, inserts, deletes, copies, splices from another seed).
   Every input is a fresh exact-size heap block, so a read or write one byte past it is reported. A failure
   prints the seed and iteration, and writes the input to fuzz-crash.bin (needs ASAN_OPTIONS=abort_on_error=1). */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

static uint64_t rng_state;
static uint64_t rng(void) {
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 7;
    rng_state ^= rng_state << 17;
    return rng_state;
}

typedef struct { uint8_t *p; size_t n; } input;

static int read_file(const char *path, input *out) {
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    size_t cap = 4096, n = 0;
    uint8_t *p = malloc(cap);
    size_t got;
    while ((got = fread(p + n, 1, cap - n, f)) > 0) {
        n += got;
        if (n == cap) p = realloc(p, cap *= 2);
    }
    fclose(f);
    out->p = p;
    out->n = n;
    return 0;
}

static const uint8_t *current;
static size_t current_len;
static uint64_t current_seed, current_iter;

/* On a crash, keep the input that caused it. Set ASAN_OPTIONS=abort_on_error=1 so a sanitizer report ends in SIGABRT. */
static void on_crash(int sig) {
    FILE *f = fopen("fuzz-crash.bin", "wb");
    if (f) { fwrite(current, 1, current_len, f); fclose(f); }
    fprintf(stderr, "driver: signal %d at seed %llu iteration %llu; input saved to fuzz-crash.bin\n", sig,
            (unsigned long long)current_seed, (unsigned long long)current_iter);
    signal(sig, SIG_DFL);
    raise(sig);
}

static void run(const uint8_t *p, size_t n, uint64_t seed, uint64_t iter) {
    uint8_t *exact = malloc(n ? n : 1);
    if (n) memcpy(exact, p, n);
    current = exact; current_len = n; current_seed = seed; current_iter = iter;
    LLVMFuzzerTestOneInput(exact, n);
    free(exact);
}

#define MAX_INPUT (1u << 16)

static size_t mutate(uint8_t *buf, size_t n, const input *seeds, size_t nseeds) {
    int rounds = 1 + (int)(rng() % 4);
    while (rounds--) {
        size_t at = n ? (size_t)(rng() % n) : 0;
        switch (rng() % 7) {
        case 0: if (n) buf[at] ^= (uint8_t)(1u << (rng() % 8)); break;
        case 1: if (n) buf[at] = (uint8_t)rng(); break;
        case 2: if (n < MAX_INPUT) { memmove(buf + at + 1, buf + at, n - at); buf[at] = (uint8_t)rng(); n++; } break;
        case 3: if (n) { memmove(buf + at, buf + at + 1, n - at - 1); n--; } break;
        case 4: if (n > 1 && n * 2 < MAX_INPUT) { /* repeat a chunk */
                    size_t len = 1 + (size_t)(rng() % (n - at > 64 ? 64 : n - at));
                    memmove(buf + at + len, buf + at, n - at);
                    memcpy(buf + at, buf + at + len, len);
                    n += len;
                } break;
        case 5: { /* splice a piece of another seed */
                    const input *o = &seeds[rng() % nseeds];
                    if (!o->n) break;
                    size_t from = (size_t)(rng() % o->n), len = 1 + (size_t)(rng() % (o->n - from));
                    if (len > 256) len = 256;
                    if (n + len < MAX_INPUT) {
                        memmove(buf + at + len, buf + at, n - at);
                        memcpy(buf + at, o->p + from, len);
                        n += len;
                    }
                } break;
        default: { /* interesting byte */
                    static const uint8_t interesting[] = {0, 1, 0x0d, 0x0a, 0x20, 0x3a, 0x7f, 0x80, 0xff};
                    if (n) buf[at] = interesting[rng() % sizeof interesting];
                } break;
        }
    }
    return n;
}

int main(int argc, char **argv) {
    uint64_t iterations = 100000, seed = 1;
    input seeds[256];
    size_t nseeds = 0;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-n") && i + 1 < argc) iterations = strtoull(argv[++i], NULL, 10);
        else if (!strcmp(argv[i], "-s") && i + 1 < argc) seed = strtoull(argv[++i], NULL, 10);
        else if (nseeds < 256 && read_file(argv[i], &seeds[nseeds]) == 0) nseeds++;
        else { fprintf(stderr, "driver: cannot use %s\n", argv[i]); return 2; }
    }
    if (!nseeds) { fprintf(stderr, "driver: no seed files\n"); return 2; }
    signal(SIGABRT, on_crash); signal(SIGILL, on_crash); signal(SIGSEGV, on_crash); signal(SIGFPE, on_crash);
    rng_state = seed * 0x9E3779B97F4A7C15ull + 1;
    for (size_t i = 0; i < nseeds; i++) run(seeds[i].p, seeds[i].n, seed, 0);
    uint8_t *buf = malloc(MAX_INPUT);
    for (uint64_t it = 1; it <= iterations; it++) {
        const input *s = &seeds[rng() % nseeds];
        memcpy(buf, s->p, s->n);
        size_t n = mutate(buf, s->n, seeds, nseeds);
        run(buf, n, seed, it);
    }
    free(buf);
    for (size_t i = 0; i < nseeds; i++) free(seeds[i].p);
    printf("fuzz: %llu inputs, seed %llu, no failure\n", (unsigned long long)(iterations + nseeds), (unsigned long long)seed);
    return 0;
}
