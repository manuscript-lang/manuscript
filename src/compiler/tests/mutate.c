/* mutate OUT_DIR COUNT SEED FILE_LIST [mir|layout]: writes COUNT mutated copies of the listed
 * sources, for differential fuzzing of the C front end against the Rust one. The generator is a
 * fixed xorshift, so a seed names the same files on every platform. With `layout` a copy is the
 * whole file re-laid-out (lines joined inside brackets, tabs as spaces, spacing removed), which
 * stays valid syntax and gives the formatter work to do. */
#include <stdbool.h>
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
/* Pieces for MIR text (the optional sixth argument "mir"). */
static const char *const mir_pieces[] = {
    "%", "@", "!", "!1:2:3", "!1:2", "->", ":", ",", "(", ")", "{", "}", "[", "]", "<", ">", "=",
    "move ", "int", "str", "list<int>", "opt<", "fn(", "dyn ", "obj ", "b9", "b0()", "br ", "ret",
    "fn @f() {\n", "}\n", "\n", " ; c\n", "\"", "\\x", "\\x4", "\\q", "0x", "0xzz", "1e5", "1e", "-",
    "-9223372036854775809", "99999999999999999999", "1.5", "1.", ".5", "true", "false", "default",
    "fault ", "switch ", "icmp.", "icmp.xx", "export", "inline(", "closure(", "method", "sort_cmp",
    "\t", "\r", "\r\n", "\x01", "\xc3\xa9", "unknown", "x.y", "a.b.c", "0",
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

/* Joins the lines inside brackets (outside text and comments): every group when `all`, else each
 * group with probability one half. */
static void join_brackets(Bytes *b, bool all) {
    char *copy = malloc(b->n + 1);
    memcpy(copy, b->p, b->n);
    size_t len = b->n;
    b->n = 0;
    bool joins[256];
    size_t depth = 0;
    bool in_text = false;
    for (size_t i = 0; i < len; i++) {
        const char c = copy[i];
        if (in_text) {
            splice(b, b->n, 0, &c, 1);
            if (c == '\\' && i + 1 < len) {
                splice(b, b->n, 0, &copy[++i], 1);
            } else if (c == '"') {
                in_text = false;
            }
        } else if (c == '"') {
            in_text = true;
            splice(b, b->n, 0, &c, 1);
        } else if (c == '/' && i + 1 < len && copy[i + 1] == '/') {
            size_t end = i;
            while (end < len && copy[end] != '\n') {
                end++;
            }
            splice(b, b->n, 0, copy + i, end - i);
            i = end - 1;
        } else if (c == '\n' && depth > 0 && depth <= 256 && joins[depth - 1]) {
            size_t j = i + 1;
            while (j < len && (copy[j] == ' ' || copy[j] == '\t')) {
                j++;
            }
            splice(b, b->n, 0, j < len && copy[j] == '\n' ? "\n" : " ", 1);
            i = j - 1;
        } else {
            if (c == '(' || c == '[' || c == '{') {
                if (depth < 256) {
                    joins[depth] = all || below(2) == 0;
                }
                depth++;
            } else if ((c == ')' || c == ']' || c == '}') && depth > 0) {
                depth--;
            }
            splice(b, b->n, 0, &c, 1);
        }
    }
    free(copy);
}

/* Removes every occurrence of `from` by replacing it with `to`. */
static void replace_all(Bytes *b, const char *from, const char *to) {
    const size_t from_len = strlen(from);
    const size_t to_len = strlen(to);
    for (size_t at = 0; at + from_len <= b->n;) {
        if (memcmp(b->p + at, from, from_len) == 0) {
            splice(b, at, from_len, to, to_len);
            at += to_len;
        } else {
            at++;
        }
    }
}

static void reshape(Bytes *b) {
    switch (below(6)) {
    case 0: join_brackets(b, true); break;
    case 1: join_brackets(b, false); break;
    case 2: replace_all(b, "\t", "  "); break;
    case 3: replace_all(b, ", ", ","); break;
    case 4:
        join_brackets(b, true);
        replace_all(b, "\t", "    ");
        break;
    default: replace_all(b, "\n\n", "\n"); break;
    }
}

int main(int argc, char **argv) {
    if (argc != 5 && argc != 6) {
        fputs("usage: mutate OUT_DIR COUNT SEED FILE_LIST [mir|layout]\n", stderr);
        return 2;
    }
    bool mir = argc == 6 && strcmp(argv[5], "mir") == 0;
    bool layout = argc == 6 && strcmp(argv[5], "layout") == 0;
    const char *const *piece_set = mir ? mir_pieces : pieces;
    size_t npieces = mir ? sizeof mir_pieces / sizeof mir_pieces[0] : NPIECES;
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
            size_t size = strlen(line) + 1;
            files[nfiles] = malloc(size);
            memcpy(files[nfiles++], line, size);
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
        if (len > 20000 && !layout) {
            start = below(len - 20000);
            len = 20000;
        }
        if (layout && len > 60000) {
            continue;
        }
        fseek(f, (long)start, SEEK_SET);
        b.n = 0;
        splice(&b, 0, 0, "", 0);
        char *buf = malloc(len + 1);
        size_t got = fread(buf, 1, len, f);
        fclose(f);
        splice(&b, 0, 0, buf, got);
        free(buf);
        if (layout) {
            reshape(&b);
        }
        static const int rounds[] = {1, 1, 1, 2, 3, 5};
        int r = layout ? 0 : rounds[below(6)];
        for (int k = 0; k < r && b.n > 0; k++) {
            size_t at = below(b.n + 1);
            uint64_t op = rnd() % 100;
            if (op < 45) {
                const char *piece = piece_set[below(npieces)];
                splice(&b, at, 0, piece, strlen(piece));
            } else if (op < 70) {
                static const size_t dels[] = {1, 1, 2, 5, 20};
                splice(&b, at, dels[below(5)], "", 0);
            } else if (op < 85) {
                const char *piece = piece_set[below(npieces)];
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
        snprintf(path, sizeof path, "%s/m%06ld.%s", out, i, mir ? "mir" : "ms");
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
