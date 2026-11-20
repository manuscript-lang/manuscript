/* Semantic versions and requirements (semver.h). */
#include <string.h>

#include "ms/project.h"
#include "ms/semver.h"

/* The text as Rust's `{:?}` writes a string: quoted, with escapes for quotes, backslashes and control characters. */
const char *ms_debug_quote(MsArena *a, const char *text) {
    MsBuf out = {0};
    ms_buf_putc(&out, '"');
    for (const char *c = text; *c != 0; c++) {
        const unsigned char byte = (unsigned char)*c;
        switch (byte) {
        case '"': ms_buf_puts(&out, "\\\""); break;
        case '\\': ms_buf_puts(&out, "\\\\"); break;
        case '\n': ms_buf_puts(&out, "\\n"); break;
        case '\r': ms_buf_puts(&out, "\\r"); break;
        case '\t': ms_buf_puts(&out, "\\t"); break;
        default:
            if (byte < 0x20 || byte == 0x7f) {
                ms_buf_printf(&out, "\\u{%x}", byte);
            } else {
                ms_buf_putc(&out, *c);
            }
        }
    }
    ms_buf_putc(&out, '"');
    char *quoted = ms_arena_strndup(a, out.data, out.len);
    ms_buf_free(&out);
    return quoted;
}

/* ---- numbers and identifiers ---- */

/* -1, 0 or 1 as `x` is below, equal to or above `y`. */
static int semver_order(uint64_t x, uint64_t y) { return (x > y) - (x < y); }

static bool semver_digits(const char *s, size_t n) {
    for (size_t i = 0; i < n; i++) {
        if (s[i] < '0' || s[i] > '9') {
            return false;
        }
    }
    return n > 0;
}

/* A decimal number without a leading zero that fits in 64 bits. */
static bool semver_number(const char *s, size_t n, uint64_t *out) {
    if (!semver_digits(s, n) || (n > 1 && s[0] == '0')) {
        return false;
    }
    uint64_t value = 0;
    for (size_t i = 0; i < n; i++) {
        const uint64_t digit = (uint64_t)(s[i] - '0');
        if (value > (UINT64_MAX - digit) / 10) {
            return false;
        }
        value = value * 10 + digit;
    }
    *out = value;
    return true;
}

/* A pre-release identifier: ASCII letters, digits and `-`, and no leading zero when numeric. */
static bool semver_identifier(const char *s, size_t n) {
    if (n == 0) {
        return false;
    }
    for (size_t i = 0; i < n; i++) {
        const char c = s[i];
        const bool ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '-';
        if (!ok) {
            return false;
        }
    }
    return !(semver_digits(s, n) && n > 1 && s[0] == '0');
}

/* Whether every dot-separated identifier of `pre` is valid. */
static bool semver_identifiers(const char *pre) {
    const char *start = pre;
    for (;;) {
        const char *dot = strchr(start, '.');
        const size_t n = dot != NULL ? (size_t)(dot - start) : strlen(start);
        if (!semver_identifier(start, n)) {
            return false;
        }
        if (dot == NULL) {
            return true;
        }
        start = dot + 1;
    }
}

/* ---- versions ---- */

/* Splits `a.b.c` into numbers; false unless there are exactly `count` valid ones (`min..3` when count is 0). */
static size_t semver_split_numbers(const char *text, size_t length, uint64_t out[3], bool valid[3]) {
    size_t parts = 0;
    size_t start = 0;
    for (size_t i = 0; i <= length; i++) {
        if (i == length || text[i] == '.') {
            if (parts < 3) {
                valid[parts] = semver_number(text + start, i - start, &out[parts]);
            }
            parts++;
            start = i + 1;
        }
    }
    return parts;
}

bool ms_version_parse(MsArena *a, const char *text, MsVersion *out, const char **error) {
    const char *dash = strchr(text, '-');
    const size_t length = dash != NULL ? (size_t)(dash - text) : strlen(text);
    const char *pre = dash != NULL ? dash + 1 : "";
    uint64_t n[3] = {0};
    bool valid[3] = {false, false, false};
    const size_t parts = semver_split_numbers(text, length, n, valid);
    const bool ok = parts == 3 && valid[0] && valid[1] && valid[2] && (dash == NULL || semver_identifiers(pre));
    if (!ok) {
        *error = ms_arena_fmt(a, "%s is not a version; write three numbers such as 1.2.3 (a suffix such as -rc.1 is allowed)", ms_debug_quote(a, text)).ptr;
        return false;
    }
    *out = (MsVersion){.major = n[0], .minor = n[1], .patch = n[2], .pre = ms_arena_strndup(a, pre, strlen(pre))};
    return true;
}

bool ms_version_of_tag(MsArena *a, const char *tag, MsVersion *out) {
    const char *error;
    return ms_version_parse(a, tag[0] == 'v' ? tag + 1 : tag, out, &error);
}

/* Compares two dot-separated pre-release lists as semver does: numbers below names, shorter below longer. */
static int semver_compare_pre(const char *x, const char *y) {
    for (;;) {
        const char *xd = strchr(x, '.');
        const char *yd = strchr(y, '.');
        const size_t xn = xd != NULL ? (size_t)(xd - x) : strlen(x);
        const size_t yn = yd != NULL ? (size_t)(yd - y) : strlen(y);
        uint64_t xv = 0, yv = 0;
        const bool xnum = semver_number(x, xn, &xv);
        const bool ynum = semver_number(y, yn, &yv);
        int order;
        if (xnum && ynum) {
            order = semver_order(xv, yv);
        } else if (xnum) {
            order = -1;
        } else if (ynum) {
            order = 1;
        } else {
            const size_t common = xn < yn ? xn : yn;
            order = memcmp(x, y, common);
            if (order == 0) {
                order = semver_order(xn, yn);
            }
        }
        if (order != 0) {
            return order < 0 ? -1 : 1;
        }
        if (xd == NULL || yd == NULL) {
            return (xd != NULL) - (yd != NULL);
        }
        x = xd + 1;
        y = yd + 1;
    }
}

int ms_version_compare(const MsVersion *x, const MsVersion *y) {
    const uint64_t xs[3] = {x->major, x->minor, x->patch};
    const uint64_t ys[3] = {y->major, y->minor, y->patch};
    for (size_t i = 0; i < 3; i++) {
        if (xs[i] != ys[i]) {
            return xs[i] < ys[i] ? -1 : 1;
        }
    }
    const bool xr = x->pre[0] == 0, yr = y->pre[0] == 0;
    if (xr && yr) {
        return 0;
    }
    if (xr || yr) {
        return xr ? 1 : -1;
    }
    return semver_compare_pre(x->pre, y->pre);
}

const char *ms_version_text(MsArena *a, const MsVersion *v) {
    if (v->pre[0] == 0) {
        return ms_arena_fmt(a, "%llu.%llu.%llu", (unsigned long long)v->major, (unsigned long long)v->minor, (unsigned long long)v->patch).ptr;
    }
    return ms_arena_fmt(a, "%llu.%llu.%llu-%s", (unsigned long long)v->major, (unsigned long long)v->minor, (unsigned long long)v->patch, v->pre).ptr;
}

/* ---- buckets ---- */

MsBucket ms_version_bucket(const MsVersion *v) {
    if (v->major > 0) {
        return (MsBucket){MS_BUCKET_MAJOR, v->major};
    }
    if (v->minor > 0) {
        return (MsBucket){MS_BUCKET_MINOR, v->minor};
    }
    return (MsBucket){MS_BUCKET_PATCH, v->patch};
}

bool ms_bucket_equal(MsBucket x, MsBucket y) { return x.kind == y.kind && x.number == y.number; }

int ms_bucket_compare(MsBucket x, MsBucket y) {
    if (x.kind != y.kind) {
        return x.kind < y.kind ? -1 : 1;
    }
    return semver_order(x.number, y.number);
}

const char *ms_bucket_text(MsArena *a, MsBucket b) {
    const unsigned long long n = b.number;
    switch (b.kind) {
    case MS_BUCKET_MAJOR: return ms_arena_fmt(a, "%llu.x", n).ptr;
    case MS_BUCKET_MINOR: return ms_arena_fmt(a, "0.%llu.x", n).ptr;
    case MS_BUCKET_PATCH: break;
    }
    return ms_arena_fmt(a, "0.0.%llu", n).ptr;
}

/* ---- requirements ---- */

static bool semver_requirement_error(MsArena *a, const char *text, const char *why, const char **error) {
    *error = ms_arena_fmt(a, "%s is not a version requirement: %s", ms_debug_quote(a, text), why).ptr;
    return false;
}

bool ms_requirement_parse(MsArena *a, const char *text, MsRequirement *out, const char **error) {
    MsRequirementOp op = MS_REQ_CARET;
    const char *rest = text;
    if (text[0] == '^') {
        rest++;
    } else if (text[0] == '~') {
        op = MS_REQ_TILDE;
        rest++;
    } else if (text[0] == '=') {
        op = MS_REQ_EXACT;
        rest++;
    }
    const char *dash = strchr(rest, '-');
    const size_t length = dash != NULL ? (size_t)(dash - rest) : strlen(rest);
    const char *pre = dash != NULL ? dash + 1 : "";
    if (dash != NULL && !semver_identifiers(pre)) {
        return semver_requirement_error(a, text, "the suffix after - is not a pre-release name", error);
    }
    uint64_t n[3] = {0};
    bool valid[3] = {false, false, false};
    const size_t parts = semver_split_numbers(rest, length, n, valid);
    if (parts > 3 || !valid[0] || (parts > 1 && !valid[1]) || (parts > 2 && !valid[2])) {
        return semver_requirement_error(a, text, "write one to three numbers such as 1, 1.2 or 1.2.3, with an optional ^, ~ or =", error);
    }
    MsRequirement r = {.op = op, .major = n[0], .has_minor = parts > 1, .has_patch = parts > 2, .minor = n[1], .patch = n[2],
                       .pre = ms_arena_strndup(a, pre, strlen(pre))};
    if (pre[0] != 0 && !r.has_patch) {
        return semver_requirement_error(a, text, "a pre-release needs all three numbers", error);
    }
    /* A zero major makes the next number the compatibility boundary, so it must be there. */
    if (r.major == 0 && !r.has_minor) {
        return semver_requirement_error(a, text, "0 alone covers incompatible releases; write 0.4 or 0.4.1", error);
    }
    if (r.major == 0 && r.has_minor && r.minor == 0 && !r.has_patch) {
        return semver_requirement_error(a, text, "0.0 alone covers incompatible releases; write 0.0.3", error);
    }
    *out = r;
    return true;
}

MsBucket ms_requirement_bucket(const MsRequirement *r) {
    if (r->major > 0) {
        return (MsBucket){MS_BUCKET_MAJOR, r->major};
    }
    if (r->has_minor && r->minor > 0) {
        return (MsBucket){MS_BUCKET_MINOR, r->minor};
    }
    return (MsBucket){MS_BUCKET_PATCH, r->has_patch ? r->patch : 0};
}

bool ms_requirement_matches(const MsRequirement *r, const MsVersion *v) {
    if (v->pre[0] != 0 && r->pre[0] == 0) {
        return false;
    }
    if (!ms_bucket_equal(ms_version_bucket(v), ms_requirement_bucket(r))) {
        return false;
    }
    const MsVersion floor = {.major = r->major, .minor = r->has_minor ? r->minor : 0, .patch = r->has_patch ? r->patch : 0, .pre = r->pre};
    if (ms_version_compare(v, &floor) < 0) {
        return false;
    }
    switch (r->op) {
    case MS_REQ_EXACT:
        if (r->has_minor && r->has_patch) {
            return ms_version_compare(v, &floor) == 0;
        }
        return !r->has_minor || v->minor == r->minor;
    case MS_REQ_TILDE: return !r->has_minor || v->minor == r->minor;
    case MS_REQ_CARET: break;
    }
    /* Inside the bucket, a caret on a fully written 0.0.x is that one version. */
    return r->major != 0 || !r->has_minor || r->minor != 0 || ms_version_compare(v, &floor) == 0;
}

const char *ms_requirement_text(MsArena *a, const MsRequirement *r) {
    MsBuf out = {0};
    static const char operators[] = {'^', '~', '='};
    ms_buf_putc(&out, operators[r->op]);
    ms_buf_printf(&out, "%llu", (unsigned long long)r->major);
    if (r->has_minor) {
        ms_buf_printf(&out, ".%llu", (unsigned long long)r->minor);
    }
    if (r->has_patch) {
        ms_buf_printf(&out, ".%llu", (unsigned long long)r->patch);
    }
    if (r->pre[0] != 0) {
        ms_buf_printf(&out, "-%s", r->pre);
    }
    char *text = ms_arena_strndup(a, out.data, out.len);
    ms_buf_free(&out);
    return text;
}
