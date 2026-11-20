/* mutate OUT_DIR COUNT SEED FILE_LIST: writes COUNT mutated copies of the listed sources, for
 * differential fuzzing of the C front end against the Rust one. The generator is a fixed xorshift,
 * so a seed names the same files on every platform. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint64_t rng_state;

static uint64_t rnd(void) {
    uint64_t x = rng_state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    return rng_state = x;
}
static size_t below(size_t n) {
    return n == 0 ? 0 : (size_t)(rnd() % n);
}

static const char *const pieces[] = {
    "\"", "'", "f\"", "r\"", "\"\"\"", "{", "}", "(", ")", "[", "]", ":", ":=", "=", "|", ".", "..",
    "...", "\t", "\r", "\r\n", "    ", "\n", "\n\n", " ", "?", "!", "&", "fn ", "if ", "else", "match ",
    "var ", "enum ", "type ", "import ", "from ", "move ", "try ", "not ", "//", "/*", "*/", "\\",
    "\\u{", "\\n", "0x", "1_", "1e", "1d", "_", ";", "#", "$", "`", "@", "~", "^", ",", "->", "=>",
    "<", ">", "+=", "-=", "\xc3\xa9", "\xe2\x80\xae", "\xe2\x80\x8b", "\xf0\x9f\x98\x80", "\xcc\x81",
    "\x01", "\x7f", "\xef\xbb\xbf",
};
#define NPIECES (sizeof pieces / sizeof pieces[0])

typedef struct {
    char *p;
    size_t n, cap;
} Bytes;

static void splice(Bytes *b, size_t at, size_t del, const char *ins, size_t ins_len) {
    if (at > b->n) {
        at = b->n;
    }
    if (at + del > b->n) {
        del = b->n - at;
    }
    size_t n = b->n - del + ins_len;
    if (n + 1 > b->cap) {
        b->cap = (n + 1) * 2;
        b->p = realloc(b->p, b->cap);
    }
    memmove(b->p + at + ins_len, b->p + at + del, b->n - at - del);
    memcpy(b->p + at, ins, ins_len);
    b->n = n;
}

int main(int argc, char **argv) {
    if (argc != 5) {
        fputs("usage: mutate OUT_DIR COUNT SEED FILE_LIST\n", stderr);
        return 2;
    }
    const char *out = argv[1];
    long count = atol(argv[2]);
    rng_state = (uint64_t)atol(argv[3]) * 0x9E3779B97F4A7C15ull + 88172645463325252ull;
    FILE *list = fopen(argv[4], "r");
    if (list == NULL) {
        perror(argv[4]);
        return 1;
    }
    char **files = NULL;
    size_t nfiles = 0;
    char line[4096];
    while (fgets(line, sizeof line, list) != NULL) {
        line[strcspn(line, "\r\n")] = 0;
        if (line[0] != 0) {
            files = realloc(files, (nfiles + 1) * sizeof *files);
            files[nfiles] = malloc(strlen(line) + 1);
            strcpy(files[nfiles++], line);
        }
    }
    fclose(list);
    Bytes b = {0};
    for (long i = 0; i < count; i++) {
        FILE *f = fopen(files[below(nfiles)], "rb");
        if (f == NULL) {
            continue;
        }
        fseek(f, 0, SEEK_END);
        long size = ftell(f);
        fseek(f, 0, SEEK_SET);
        size_t start = 0, len = (size_t)size;
        if (len > 20000) {
            start = below(len - 20000);
            len = 20000;
        }
        fseek(f, (long)start, SEEK_SET);
        b.n = 0;
        splice(&b, 0, 0, "", 0);
        char *buf = malloc(len + 1);
        size_t got = fread(buf, 1, len, f);
        fclose(f);
        splice(&b, 0, 0, buf, got);
        free(buf);
        static const int rounds[] = {1, 1, 1, 2, 3, 5};
        int r = rounds[below(6)];
        for (int k = 0; k < r && b.n > 0; k++) {
            size_t at = below(b.n + 1);
            uint64_t op = rnd() % 100;
            if (op < 45) {
                const char *piece = pieces[below(NPIECES)];
                splice(&b, at, 0, piece, strlen(piece));
            } else if (op < 70) {
                static const size_t dels[] = {1, 1, 2, 5, 20};
                splice(&b, at, dels[below(5)], "", 0);
            } else if (op < 85) {
                const char *piece = pieces[below(NPIECES)];
                splice(&b, at, 1, piece, strlen(piece));
            } else {
                size_t lo = at;
                while (lo > 0 && b.p[lo - 1] != '\n') {
                    lo--;
                }
                size_t hi = at;
                while (hi < b.n && b.p[hi] != '\n') {
                    hi++;
                }
                if (hi < b.n) {
                    hi++;
                }
                char *copy = malloc(hi - lo + 1);
                memcpy(copy, b.p + lo, hi - lo);
                splice(&b, lo, 0, copy, hi - lo);
                free(copy);
            }
        }
        char path[4096];
        snprintf(path, sizeof path, "%s/m%06ld.ms", out, i);
        FILE *o = fopen(path, "wb");
        if (o == NULL) {
            perror(path);
            return 1;
        }
        fwrite(b.p, 1, b.n, o);
        fclose(o);
    }
    return 0;
}
