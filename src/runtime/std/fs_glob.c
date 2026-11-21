/* `glob_entries` of @std/fs: the paths under a root that match any of a list of patterns and none of the exclusions,
 * sorted by path. Patterns are compiled by the @std/os/path matcher (path.c). It runs on the runtime thread because
 * the exclusion filter is program code; the system calls block, as the operation has always done. Everything it owns
 * is in one GlobWalk, which a cleanup frees if the filter leaves by a jump. */
#include <stdlib.h>
#include <string.h>

#include "fs_tree.h"
#include "ms_rt/fs.h"
#include "ms_rt/path.h"

enum { GLOB_MAX_DEPTH = 1024 };

/* A compiled pattern with what is needed to apply it. */
typedef struct Pattern {
    MsObj *glob;            /* owned: the compiled matcher */
    bool directories_only;  /* the pattern ended in `/`: only directories, and links to them, match */
    bool absolute;          /* the pattern starts with `/`: matched against the absolute path */
} Pattern;

typedef struct Patterns {
    Pattern *items; /* owned */
    size_t count;
} Patterns;

/* One match. */
typedef struct Found {
    uint8_t *text; /* owned: the path, then the name */
    size_t path_length;
    size_t name_length;
    bool directory;
    bool symlink;
    size_t order; /* the order of discovery, which keeps the first of equal paths */
} Found;

typedef struct GlobWalk {
    MsFsFail fail;
    bool follow_links;
    int64_t remaining; /* entries the walk may still visit */
    int64_t max_results;
    MsFsClosure *filter;
    Patterns patterns;
    Patterns excluded;
    MsFsBuffer root;      /* the absolute root every matched path is relative to */
    MsFsBuffer ancestors; /* the canonical directories being walked, as names */
    Found *found;         /* owned */
    size_t found_count;
    size_t found_capacity;
    MsFsArguments arguments;
    MsStr relative_value; /* the two texts a visit matches against */
    MsStr absolute_value;
    bool values_live;
} GlobWalk;

static void patterns_free(Patterns *patterns) {
    for (size_t i = 0; i < patterns->count; i++) {
        patterns->items[i].glob->drop(patterns->items[i].glob);
    }
    free(patterns->items);
    *patterns = (Patterns){0};
}

static void values_free(GlobWalk *walk) {
    if (walk->values_live) {
        msrt_string_free(&walk->relative_value);
        msrt_string_free(&walk->absolute_value);
        walk->values_live = false;
    }
}

static void found_free(GlobWalk *walk) {
    for (size_t i = 0; i < walk->found_count; i++) {
        free(walk->found[i].text);
    }
    free(walk->found);
    walk->found = NULL;
    walk->found_count = 0;
    walk->found_capacity = 0;
}

static void walk_free(GlobWalk *walk) {
    ms_fs_fail_free(&walk->fail);
    patterns_free(&walk->patterns);
    patterns_free(&walk->excluded);
    ms_fs_buffer_free(&walk->root);
    ms_fs_buffer_free(&walk->ancestors);
    found_free(walk);
    ms_fs_arguments_free(&walk->arguments);
    values_free(walk);
}

static void walk_cleanup(uint8_t *argument) { walk_free((GlobWalk *)__builtin_assume_aligned(argument, _Alignof(GlobWalk))); }

static bool fail_status(GlobWalk *walk, uint8_t status) {
    ms_fs_fail_status(&walk->fail, status);
    return false;
}

static bool fail_memory(GlobWalk *walk) {
    ms_fs_fail_text(&walk->fail, "out of memory");
    return false;
}

static bool fail_at(GlobWalk *walk, MsSysError error, const char *operation, MsBytes path) {
    ms_fs_fail_errno_at(&walk->fail, error, operation, path);
    return false;
}

static bool is_kind(MsSysError error, MsSysErrorKind kind) { return ms_sys_fs_error_kind(error) == kind; }

/* ---- compiling patterns ---- */

/* `text` without its `.` and empty segments, so `./a`, `a/./b` and `a//b` match as the cleaned path does. A leading
 * `/` stays; `..` segments stay. */
static bool without_dot_segments(MsBytes text, MsFsBuffer *out) {
    bool ok = text.len == 0 || text.ptr[0] != '/' || ms_fs_buffer_push(out, '/');
    bool first = true;
    size_t start = 0;
    for (size_t i = 0; ok && i <= text.len; i++) {
        if (i < text.len && text.ptr[i] != '/') {
            continue;
        }
        const size_t length = i - start;
        const bool skipped = length == 0 || (length == 1 && text.ptr[start] == '.');
        if (!skipped) {
            ok = (first || ms_fs_buffer_push(out, '/')) && ms_fs_buffer_append(out, text.ptr + start, length);
            first = false;
        }
        start = i + 1;
    }
    return ok;
}

/* Compiles the cleaned pattern; false with `walk->fail` set (an unusable pattern is invalid input). */
static bool compile_one(GlobWalk *walk, MsBytes pattern, Pattern *out) {
    if (!ms_fs_valid_utf8(pattern)) {
        return fail_status(walk, STATUS_INVALID_INPUT);
    }
    MsFsBuffer cleaned = {0};
    if (!without_dot_segments(pattern, &cleaned)) {
        ms_fs_buffer_free(&cleaned);
        return fail_memory(walk);
    }
    MsStr value;
    msrt_string_from_bytes(cleaned.data, cleaned.length, &value);
    ms_fs_buffer_free(&cleaned);
    MsObj *glob = NULL;
    const uint8_t status = msstd_path_compile_glob(0, &value, &glob);
    msrt_string_free(&value);
    if (status != STATUS_OK) {
        return status == STATUS_INVALID_INPUT ? fail_status(walk, STATUS_INVALID_INPUT) : fail_memory(walk);
    }
    out->glob = glob;
    out->directories_only = pattern.len > 0 && pattern.ptr[pattern.len - 1] == '/';
    out->absolute = pattern.len > 0 && pattern.ptr[0] == '/';
    return true;
}

static bool compile_list(GlobWalk *walk, const MsVec *list, Patterns *out) {
    const MsStr *items = list->ptr;
    out->items = list->len == 0 ? NULL : calloc(list->len, sizeof(Pattern));
    if (list->len > 0 && out->items == NULL) {
        return fail_memory(walk);
    }
    for (size_t i = 0; i < list->len; i++) {
        if (!compile_one(walk, msrt_str_bytes(&items[i]), &out->items[i])) {
            return false;
        }
        out->count = i + 1;
    }
    return true;
}

/* ---- the texts of one visit ---- */

/* Whether `pattern` matches the text it applies to; false on a matcher failure, which is set in `walk`. */
static bool pattern_hit(GlobWalk *walk, const Pattern *pattern, bool names_directory, bool *hit) {
    *hit = false;
    if (pattern->directories_only && !names_directory) {
        return true;
    }
    uint8_t matched = 0;
    const MsStr *value = pattern->absolute ? &walk->absolute_value : &walk->relative_value;
    const uint8_t status = msstd_path_glob_matches(pattern->glob, value, &matched);
    if (status != STATUS_OK) {
        return fail_memory(walk);
    }
    *hit = matched != 0;
    return true;
}

/* Whether any of `patterns` applies; `skip_relative` leaves out the relative ones (the root is not an entry inside
 * itself, so `.*` must not list it). */
static bool any_hit(GlobWalk *walk, const Patterns *patterns, bool names_directory, bool skip_relative, bool *hit) {
    *hit = false;
    for (size_t i = 0; i < patterns->count && !*hit; i++) {
        if (skip_relative && !patterns->items[i].absolute) {
            continue;
        }
        if (!pattern_hit(walk, &patterns->items[i], names_directory, hit)) {
            return false;
        }
    }
    return true;
}

/* ---- paths relative to the root ---- */

/* The next element of a cleaned path; an absolute path's root is an element of its own ("/"). */
static bool next_element(MsBytes path, size_t *cursor, MsBytes *element) {
    const bool at_start = *cursor == 0;
    if (at_start && path.len > 0 && ms_fs_is_separator(path.ptr[0])) {
        *cursor = 1;
        *element = ms_bytes_of(path.ptr, 1);
        return true;
    }
    while (*cursor < path.len) {
        while (*cursor < path.len && ms_fs_is_separator(path.ptr[*cursor])) {
            *cursor += 1;
        }
        const size_t start = *cursor;
        while (*cursor < path.len && !ms_fs_is_separator(path.ptr[*cursor])) {
            *cursor += 1;
        }
        const size_t length = *cursor - start;
        if (length > 0 && !(length == 1 && path.ptr[start] == '.')) {
            *element = ms_bytes_of(path.ptr + start, length);
            return true;
        }
    }
    return false;
}

static bool elements_equal(MsBytes a, MsBytes b) {
    if (a.len == 1 && b.len == 1 && ms_fs_is_separator(a.ptr[0]) && ms_fs_is_separator(b.ptr[0])) {
        return true;
    }
    return a.len == b.len && (a.len == 0 || memcmp(a.ptr, b.ptr, a.len) == 0);
}

static bool append_element(MsFsBuffer *out, MsBytes element) {
    return (out->length == 0 || ms_fs_buffer_push(out, '/')) && ms_fs_buffer_append(out, element.ptr, element.len);
}

/* `filepath.Rel(root, p)` for a `p` at or under `root`, or reached through `..` patterns, with `/` between the
 * elements on every host. */
static bool relative_path(MsBytes root, MsBytes path, MsFsBuffer *out) {
    MsFsBuffer clean_root = {0};
    MsFsBuffer clean_path = {0};
    bool ok = ms_fs_path_clean(root, &clean_root) && ms_fs_path_clean(path, &clean_path);
    const MsBytes from = ms_fs_buffer_view(&clean_root);
    const MsBytes to = ms_fs_buffer_view(&clean_path);
    size_t from_cursor = 0;
    size_t to_cursor = 0;
    MsBytes left;
    MsBytes right;
    bool have_left = ok && next_element(from, &from_cursor, &left);
    bool have_right = ok && next_element(to, &to_cursor, &right);
    while (have_left && have_right && elements_equal(left, right)) {
        have_left = next_element(from, &from_cursor, &left);
        have_right = next_element(to, &to_cursor, &right);
    }
    const MsBytes up = ms_bytes_of((const uint8_t *)"..", 2);
    while (ok && have_left) {
        ok = append_element(out, up);
        have_left = next_element(from, &from_cursor, &left);
    }
    while (ok && have_right) {
        ok = append_element(out, right);
        have_right = next_element(to, &to_cursor, &right);
    }
    ok = ok && (out->length > 0 || ms_fs_buffer_push(out, '.'));
    ms_fs_buffer_free(&clean_root);
    ms_fs_buffer_free(&clean_path);
    return ok;
}

/* ---- results ---- */

static bool found_add(GlobWalk *walk, MsBytes path, MsBytes name, bool directory, bool symlink) {
    if ((int64_t)walk->found_count >= walk->max_results) {
        return fail_status(walk, STATUS_LIMIT_EXCEEDED);
    }
    if (walk->found_count == walk->found_capacity) {
        size_t capacity = walk->found_capacity == 0 ? 16 : walk->found_capacity;
        size_t bytes = 0;
        if (walk->found_capacity > 0 && !ms_size_mul(capacity, 2, &capacity)) {
            return fail_memory(walk);
        }
        if (!ms_size_mul(capacity, sizeof(Found), &bytes)) {
            return fail_memory(walk);
        }
        Found *grown = realloc(walk->found, bytes);
        if (grown == NULL) {
            return fail_memory(walk);
        }
        walk->found = grown;
        walk->found_capacity = capacity;
    }
    size_t total = 0;
    if (!ms_size_add(path.len, name.len, &total)) {
        return fail_memory(walk);
    }
    uint8_t *text = malloc(total == 0 ? 1 : total);
    if (text == NULL) {
        return fail_memory(walk);
    }
    memcpy(text, path.ptr, path.len);
    memcpy(text + path.len, name.ptr, name.len);
    walk->found[walk->found_count] = (Found){text, path.len, name.len, directory, symlink, walk->found_count};
    walk->found_count += 1;
    return true;
}

/* ---- visiting ---- */

/* What a visit needs to know about one path. */
typedef struct Visit {
    MsFsBuffer relative; /* owned: the portable relative path, lossy UTF-8 */
    MsFsBuffer name;     /* owned: the last element, lossy UTF-8 */
    MsFsBuffer absolute; /* owned: the path, lossy UTF-8 */
    bool directory;
    bool symlink;
} Visit;

static void visit_free(Visit *visit) {
    ms_fs_buffer_free(&visit->relative);
    ms_fs_buffer_free(&visit->name);
    ms_fs_buffer_free(&visit->absolute);
}

static bool visit_fill(GlobWalk *walk, MsBytes path, const MsSysStat *info, Visit *visit) {
    MsFsBuffer raw = {0};
    const bool ok = relative_path(ms_fs_buffer_view(&walk->root), path, &raw) &&
                    ms_fs_buffer_append_lossy(&visit->relative, raw.data, raw.length) &&
                    ms_fs_buffer_append_lossy(&visit->name, ms_fs_path_base(path).ptr, ms_fs_path_base(path).len) &&
                    ms_fs_buffer_append_lossy(&visit->absolute, path.ptr, path.len);
    ms_fs_buffer_free(&raw);
    visit->directory = ms_fs_stat_is_directory(info);
    visit->symlink = ms_fs_stat_is_link(info);
    return ok || fail_memory(walk);
}

/* A link to a directory counts as one for a pattern that ends in `/`. */
static bool names_directory(const Visit *visit, MsBytes path) {
    if (visit->directory) {
        return true;
    }
    MsSysStat target;
    return visit->symlink && ms_fs_stat_bytes(path, true, &target) == 0 && ms_fs_stat_is_directory(&target);
}

/* Matches the visit against the exclusions and the patterns; `*excluded` and `*selected` are the answers. */
static bool classify(GlobWalk *walk, const Visit *visit, MsBytes path, bool *excluded, bool *selected) {
    msrt_string_from_bytes(visit->relative.data, visit->relative.length, &walk->relative_value);
    msrt_string_from_bytes(visit->absolute.data, visit->absolute.length, &walk->absolute_value);
    walk->values_live = true;
    const bool directory = names_directory(visit, path);
    bool ok = any_hit(walk, &walk->excluded, directory, false, excluded);
    *selected = false;
    if (ok && !*excluded) {
        const bool is_root = visit->relative.length == 1 && visit->relative.data[0] == '.';
        ok = any_hit(walk, &walk->patterns, directory, is_root, selected);
    }
    values_free(walk);
    return ok;
}

/* Asks the exclusion filter about an entry; true to leave it out. */
static bool filter_excludes(GlobWalk *walk, const Visit *visit) {
    if (walk->filter == NULL) {
        return false;
    }
    ms_fs_arguments_set(&walk->arguments, ms_fs_buffer_view(&visit->relative), ms_fs_buffer_view(&visit->name));
    const MsFsArguments *arguments = &walk->arguments;
    const uint8_t excluded = walk->filter->code.entry(walk->filter, arguments->first.low_bits, arguments->first.tagged,
                                                       arguments->second.low_bits, arguments->second.tagged,
                                                       visit->directory ? 1 : 0, visit->symlink ? 1 : 0);
    ms_fs_arguments_free(&walk->arguments);
    return excluded != 0;
}

static bool visit_path(GlobWalk *walk, MsBytes path, size_t depth);

/* Visits every child of the directory `path`. */
static bool visit_children(GlobWalk *walk, MsBytes path, size_t depth) {
    MsFsBuffer names = {0};
    bool ok = ms_fs_names_read(path, &names, &walk->fail);
    size_t cursor = 0;
    MsBytes name;
    while (ok && ms_fs_names_next(&names, &cursor, &name)) {
        MsFsBuffer child = {0};
        ok = ms_fs_path_join(path, name, &child) || fail_memory(walk);
        ok = ok && visit_path(walk, ms_fs_buffer_view(&child), depth + 1);
        ms_fs_buffer_free(&child);
    }
    ms_fs_buffer_free(&names);
    return ok;
}

/* Enters the directory `path` unless it is one already being walked (a link back up). */
static bool enter_directory(GlobWalk *walk, MsBytes path, size_t depth) {
    MsFsBuffer canonical = {0};
    const MsSysError error = ms_fs_eval_symlinks(path, &canonical);
    if (error != 0) {
        ms_fs_buffer_free(&canonical);
        return fail_at(walk, error, "lstat", path);
    }
    if (ms_fs_names_contain(&walk->ancestors, ms_fs_buffer_view(&canonical))) {
        ms_fs_buffer_free(&canonical);
        return true;
    }
    const size_t mark = walk->ancestors.length;
    const bool pushed = ms_fs_names_push(&walk->ancestors, ms_fs_buffer_view(&canonical));
    ms_fs_buffer_free(&canonical);
    if (!pushed) {
        return fail_memory(walk);
    }
    const bool ok = visit_children(walk, path, depth);
    walk->ancestors.length = mark;
    return ok;
}

/* Whether the entry is a directory to enter, following a link when asked; false without a failure for a dangling or
 * looping link. */
static bool enterable(GlobWalk *walk, MsBytes path, MsSysStat *info, bool *enter) {
    *enter = false;
    if (ms_fs_stat_is_link(info) && walk->follow_links) {
        const MsSysError error = ms_fs_stat_bytes(path, true, info);
        if (is_kind(error, MS_SYS_ERR_NOT_FOUND) || is_kind(error, MS_SYS_ERR_LINK_LOOP)) {
            return true;
        }
        if (error != 0) {
            return fail_at(walk, error, "stat", path);
        }
    }
    *enter = ms_fs_stat_is_directory(info);
    return true;
}

static bool visit_path(GlobWalk *walk, MsBytes path, size_t depth) {
    if (ms_fs_poll_cancel(&walk->fail)) {
        return false;
    }
    if (walk->remaining == 0 || depth > GLOB_MAX_DEPTH) {
        return fail_status(walk, STATUS_LIMIT_EXCEEDED);
    }
    walk->remaining -= 1;
    MsSysStat info;
    const MsSysError error = ms_fs_stat_bytes(path, false, &info);
    if (error != 0) {
        return fail_at(walk, error, "lstat", path);
    }
    Visit visit = {0};
    bool excluded = false;
    bool selected = false;
    bool ok = visit_fill(walk, path, &info, &visit) && classify(walk, &visit, path, &excluded, &selected);
    if (ok && !excluded) {
        excluded = filter_excludes(walk, &visit);
    }
    // The key is the path, so a path that is already there is kept as it was.
    if (ok && !excluded && selected) {
        ok = found_add(walk, ms_fs_buffer_view(&visit.relative), ms_fs_buffer_view(&visit.name), visit.directory, visit.symlink);
    }
    visit_free(&visit);
    if (!ok || excluded) {
        return ok;
    }
    bool enter = false;
    return enterable(walk, path, &info, &enter) && (!enter || enter_directory(walk, path, depth));
}

/* ---- where the walk starts ---- */

static bool has_glob_character(MsBytes part) {
    for (size_t i = 0; i < part.len; i++) {
        static const uint8_t special[] = {'*', '?', '[', ']', '{', '}', '(', ')', '!'};
        if (memchr(special, part.ptr[i], sizeof special) != NULL) {
            return true;
        }
    }
    return false;
}

/* The directory a pattern's literal prefix leads to: `a/b/ then a star-suffix` starts at `a/b`, a leading `..` climbs. */
static bool pattern_base(GlobWalk *walk, MsBytes pattern, MsFsBuffer *base) {
    bool ok = ms_fs_buffer_append(base, walk->root.data, walk->root.length);
    size_t start = 0;
    if (ms_fs_is_absolute(pattern)) {
        base->length = 0;
        ok = ms_fs_buffer_push(base, '/');
        while (start < pattern.len && pattern.ptr[start] == '/') {
            start += 1;
        }
    }
    for (size_t i = start; ok && i <= pattern.len; i++) {
        if (i < pattern.len && pattern.ptr[i] != '/') {
            continue;
        }
        const MsBytes part = ms_bytes_of(pattern.ptr + start, i - start);
        start = i + 1;
        MsFsBuffer next = {0};
        if (part.len == 0 || (part.len == 1 && part.ptr[0] == '.')) {
            continue;
        }
        if (has_glob_character(part)) {
            break;
        }
        if (part.len == 2 && part.ptr[0] == '.' && part.ptr[1] == '.') {
            ok = ms_fs_path_dir(ms_fs_buffer_view(base), &next);
        } else {
            ok = ms_fs_path_join(ms_fs_buffer_view(base), part, &next);
        }
        if (ok) {
            ms_fs_buffer_free(base);
            *base = next;
        } else {
            ms_fs_buffer_free(&next);
        }
    }
    return ok || fail_memory(walk);
}

/* The directories to start from, packed as names: the root, and where each pattern's literal prefix leads. */
static bool collect_starts(GlobWalk *walk, const MsVec *patterns, MsFsBuffer *starts) {
    bool ok = ms_fs_names_push(starts, ms_fs_buffer_view(&walk->root)) || fail_memory(walk);
    const MsStr *items = patterns->ptr;
    for (size_t i = 0; ok && i < patterns->len; i++) {
        MsFsBuffer base = {0};
        ok = pattern_base(walk, msrt_str_bytes(&items[i]), &base);
        MsSysStat info;
        const bool directory = ok && ms_fs_stat_bytes(ms_fs_buffer_view(&base), false, &info) == 0 && ms_fs_stat_is_directory(&info);
        if (ok && directory) {
            ok = ms_fs_names_push(starts, ms_fs_buffer_view(&base)) || fail_memory(walk);
        } else if (ok && !ms_bytes_equal(ms_fs_buffer_view(&base), ms_fs_buffer_view(&walk->root))) {
            MsFsBuffer parent = {0};
            ok = (ms_fs_path_dir(ms_fs_buffer_view(&base), &parent) && ms_fs_names_push(starts, ms_fs_buffer_view(&parent))) || fail_memory(walk);
            ms_fs_buffer_free(&parent);
        }
        ms_fs_buffer_free(&base);
    }
    return ok;
}

/* Orders starts by length, then bytes. */
static int compare_starts(const void *left, const void *right) {
    const MsBytes *a = left;
    const MsBytes *b = right;
    if (a->len != b->len) {
        return a->len < b->len ? -1 : 1;
    }
    return a->len == 0 ? 0 : memcmp(a->ptr, b->ptr, a->len);
}

/* The starts without duplicates and without any inside another, shortest first. `*out` is owned (malloc). */
static bool select_starts(GlobWalk *walk, const MsFsBuffer *starts, MsBytes **out, size_t *count) {
    size_t total = 0;
    size_t cursor = 0;
    MsBytes name;
    while (ms_fs_names_next(starts, &cursor, &name)) {
        total += 1;
    }
    size_t bytes = 0;
    MsBytes *all = ms_size_mul(total == 0 ? 1 : total, sizeof(MsBytes), &bytes) ? malloc(bytes) : NULL;
    if (all == NULL) {
        return fail_memory(walk);
    }
    cursor = 0;
    for (size_t i = 0; ms_fs_names_next(starts, &cursor, &name); i++) {
        all[i] = name;
    }
    qsort(all, total, sizeof(MsBytes), compare_starts);
    size_t kept = 0;
    for (size_t i = 0; i < total; i++) {
        bool inside = false;
        for (size_t j = 0; j < kept && !inside; j++) {
            if (!ms_fs_within_path(all[j], all[i], &inside)) {
                free(all);
                return fail_memory(walk);
            }
        }
        if (!inside) {
            all[kept] = all[i];
            kept += 1;
        }
    }
    *out = all;
    *count = kept;
    return true;
}

/* Walks from each selected start; a start that is gone is skipped. */
static bool walk_starts(GlobWalk *walk, const MsVec *patterns) {
    MsFsBuffer starts = {0};
    MsBytes *selected = NULL;
    size_t count = 0;
    bool ok = collect_starts(walk, patterns, &starts) && select_starts(walk, &starts, &selected, &count);
    for (size_t i = 0; ok && i < count; i++) {
        ok = visit_path(walk, selected[i], 0);
        if (!ok && walk->fail.status == STATUS_NOT_FOUND) {
            ms_fs_fail_free(&walk->fail);
            walk->fail = (MsFsFail){0};
            ok = true;
        }
    }
    free(selected);
    ms_fs_buffer_free(&starts);
    return ok;
}

/* ---- the result ---- */

static int compare_found(const void *left, const void *right) {
    const Found *a = left;
    const Found *b = right;
    const size_t common = a->path_length < b->path_length ? a->path_length : b->path_length;
    const int order = common == 0 ? 0 : memcmp(a->text, b->text, common);
    if (order != 0) {
        return order;
    }
    if (a->path_length != b->path_length) {
        return a->path_length < b->path_length ? -1 : 1;
    }
    if (a->order == b->order) {
        return 0;
    }
    return a->order < b->order ? -1 : 1;
}

static void path_entry_drop(const uint8_t *slot) {
    MsFsPathEntry entry;
    memcpy(&entry, slot, sizeof entry);
    msrt_string_free(&entry.path);
    msrt_string_free(&entry.name);
}

static void path_entry_copy(const uint8_t *source, uint8_t *destination) {
    MsFsPathEntry entry;
    memcpy(&entry, source, sizeof entry);
    MsFsPathEntry copy = entry;
    msrt_string_clone(&entry.path, &copy.path);
    msrt_string_clone(&entry.name, &copy.name);
    memcpy(destination, &copy, sizeof copy);
}

static const MsTypeDesc path_entry_desc = {
    .size = sizeof(MsFsPathEntry),
    .align = _Alignof(MsFsPathEntry),
    .kind = MS_TYPE_KIND_CUSTOM,
    .drop = path_entry_drop,
    .copy = path_entry_copy,
};

/* Sorts what was found and writes it as a list, leaving out a path found again. */
static void write_found(GlobWalk *walk, MsVec *out) {
    qsort(walk->found, walk->found_count, sizeof(Found), compare_found);
    msrt_list_with_capacity(&path_entry_desc, (int64_t)walk->found_count, out);
    for (size_t i = 0; i < walk->found_count; i++) {
        const Found *item = &walk->found[i];
        const bool repeated = i > 0 && walk->found[i - 1].path_length == item->path_length &&
                              memcmp(walk->found[i - 1].text, item->text, item->path_length) == 0;
        if (repeated) {
            continue;
        }
        MsFsPathEntry entry = {.directory = item->directory ? 1 : 0, .symlink = item->symlink ? 1 : 0};
        msrt_string_from_bytes(item->text, item->path_length, &entry.path);
        msrt_string_from_bytes(item->text + item->path_length, item->name_length, &entry.name);
        msrt_list_push(out, &path_entry_desc, &entry);
    }
}

/* ---- the native ---- */

static bool prepare(GlobWalk *walk, MsBytes path, const MsVec *patterns, const MsVec *exclude) {
    if (!compile_list(walk, patterns, &walk->patterns) || !compile_list(walk, exclude, &walk->excluded)) {
        return false;
    }
    if (path.len == 0) {
        return fail_status(walk, STATUS_INVALID_INPUT);
    }
    // Keep every traversal start in the same coordinates, including `.` and parent patterns.
    return ms_fs_absolute(path, &walk->root) || fail_memory(walk);
}

uint8_t msstd_fs_glob_entries(const MsStr *path, const MsVec *patterns, const MsVec *exclude, uint8_t follow_links, uint8_t has_max_entries,
                              int64_t max_entries, uint8_t has_max_results, int64_t max_results, void *filter, MsVec *out, MsStr *err) {
    GlobWalk walk = {.follow_links = follow_links != 0, .filter = filter};
    const MsBytes given = msrt_str_bytes(path);
    if (!ms_fs_limit(has_max_entries, max_entries, &walk.remaining) || !ms_fs_limit(has_max_results, max_results, &walk.max_results)) {
        ms_fs_fail_status(&walk.fail, STATUS_INVALID_INPUT);
        return ms_fs_finish_at(&walk.fail, given, err);
    }
    const size_t handle = msrt_cleanup_push(walk_cleanup, (uint8_t *)&walk);
    if (prepare(&walk, given, patterns, exclude)) {
        walk_starts(&walk, patterns);
    }
    msrt_cleanup_discard(handle);
    if (!ms_fs_failed(&walk.fail)) {
        write_found(&walk, out);
    }
    const uint8_t status = ms_fs_finish_at(&walk.fail, given, err);
    walk_free(&walk);
    return status;
}
