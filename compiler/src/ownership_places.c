/* Places for the ownership pass (ms/ownership.h); `places.rs` in the Rust checker. */
#include "ms/ownership.h"

#include <string.h>

MsPlace ms_place_local(uint32_t root) {
    MsPlace p = {root, NULL, 0};
    return p;
}

MsPlace ms_place_join(MsArena *a, MsPlace p, const MsStep *more, uint32_t nmore) {
    MsPlace out = {p.root, p.path, p.len};
    if (nmore == 0) {
        return out;
    }
    MsStep *path = MS_NEW_N(a, MsStep, (size_t)p.len + nmore);
    if (p.len > 0) {
        memcpy(path, p.path, sizeof(MsStep) * p.len);
    }
    memcpy(path + p.len, more, sizeof(MsStep) * nmore);
    out.path = path;
    out.len = p.len + nmore;
    return out;
}

MsPlace ms_place_then(MsArena *a, MsPlace p, MsStep step) {
    return ms_place_join(a, p, &step, 1);
}

/* Whether two steps can denote the same storage. */
static bool step_may_alias(MsStep x, MsStep y) {
    if (x.kind == MS_STEP_INDEX && y.kind == MS_STEP_INDEX) {
        return x.index == y.index;
    }
    if (x.kind == MS_STEP_FIELD && y.kind == MS_STEP_FIELD) {
        return x.name == y.name;
    }
    if (x.kind == MS_STEP_FIELD || y.kind == MS_STEP_FIELD) {
        return false;
    }
    return true;
}

bool ms_place_overlaps(MsPlace a, MsPlace b) {
    if (a.root != b.root) {
        return false;
    }
    uint32_t shared = a.len < b.len ? a.len : b.len;
    for (uint32_t i = 0; i < shared; i++) {
        if (!step_may_alias(a.path[i], b.path[i])) {
            return false;
        }
    }
    return true;
}

void ms_place_show(MsBuf *out, const MsNames *names, MsPlace p, MsSym root_name) {
    MsStr root = ms_name(names, root_name);
    ms_buf_put(out, root.ptr, root.len);
    for (uint32_t i = 0; i < p.len; i++) {
        MsStep step = p.path[i];
        if (step.kind == MS_STEP_FIELD) {
            MsStr field = ms_name(names, step.name);
            ms_buf_putc(out, '.');
            ms_buf_put(out, field.ptr, field.len);
        } else if (step.kind == MS_STEP_ELEMENT) {
            ms_buf_puts(out, "[..]");
        } else {
            ms_buf_printf(out, "[%llu]", (unsigned long long)step.index);
        }
    }
}
