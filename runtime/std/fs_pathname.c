/* Lexical path names for @std/fs: clean, join, base, dir and absolute (fs_support.h), by the host's rules. */
#include "fs_support.h"

#include <string.h>

#ifdef _WIN32
#define HOST_RULES MS_FS_RULES_WINDOWS
#else
#define HOST_RULES MS_FS_RULES_UNIX
#endif

typedef enum { PREFIX_NONE, PREFIX_DISK, PREFIX_OTHER } PrefixKind;

/* A path split into volume prefix, root and the elements after them. */
typedef struct Parsed {
    MsFsRules rules;
    PrefixKind prefix_kind;
    size_t prefix_length;
    bool verbatim; /* \\?\ : only the backslash separates */
    bool physical_root;
    bool implicit_root; /* UNC, verbatim and device volumes are rooted by themselves */
    size_t body;        /* where the elements start */
} Parsed;

bool ms_fs_is_separator_with(MsFsRules rules, uint8_t byte) {
    return byte == '/' || (rules == MS_FS_RULES_WINDOWS && byte == '\\');
}

static bool is_sep(const Parsed *parsed, uint8_t byte) {
    if (parsed->verbatim) {
        return byte == '\\';
    }
    return ms_fs_is_separator_with(parsed->rules, byte);
}

static bool is_ascii_letter(uint8_t byte) { return (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z'); }

/* The end of the element starting at `at`, looking for either separator unless `verbatim`. */
static size_t element_end(MsBytes path, size_t at, bool verbatim) {
    while (at < path.len && !(path.ptr[at] == '\\' || (!verbatim && path.ptr[at] == '/'))) {
        at++;
    }
    return at;
}

static bool has_prefix_bytes(MsBytes path, const char *text) {
    const size_t length = strlen(text);
    return path.len >= length && memcmp(path.ptr, text, length) == 0;
}

/* \\?\UNC\server\share, \\?\C:, \\?\name, \\.\name and \\server\share, with the number of bytes they take. */
static void parse_windows_prefix(MsBytes path, Parsed *parsed) {
    const bool two_seps = path.len >= 2 && (path.ptr[0] == '/' || path.ptr[0] == '\\') &&
                          (path.ptr[1] == '/' || path.ptr[1] == '\\');
    if (two_seps && has_prefix_bytes(path, "\\\\?\\")) {
        parsed->verbatim = true;
        parsed->prefix_kind = PREFIX_OTHER;
        size_t at = 4;
        const size_t first_end = element_end(path, at, true);
        const bool unc = first_end - at == 3 && memcmp(path.ptr + at, "UNC", 3) == 0;
        if (unc) {
            at = first_end < path.len ? first_end + 1 : first_end;
            const size_t server_end = element_end(path, at, true);
            at = server_end < path.len ? server_end + 1 : server_end;
            at = element_end(path, at, true);
        } else if (first_end - at == 2 && is_ascii_letter(path.ptr[at]) && path.ptr[at + 1] == ':') {
            parsed->prefix_kind = PREFIX_DISK;
            at = first_end;
        } else {
            at = first_end;
        }
        parsed->prefix_length = at;
        parsed->implicit_root = parsed->prefix_kind != PREFIX_DISK;
        return;
    }
    if (two_seps && path.len >= 4 && (path.ptr[3] == '/' || path.ptr[3] == '\\') && path.ptr[2] == '.') {
        parsed->prefix_kind = PREFIX_OTHER;
        parsed->prefix_length = element_end(path, 4, false);
        parsed->implicit_root = true;
        return;
    }
    if (two_seps) {
        size_t at = 2;
        const size_t server_end = element_end(path, at, false);
        at = server_end < path.len ? server_end + 1 : server_end;
        at = element_end(path, at, false);
        parsed->prefix_kind = PREFIX_OTHER;
        parsed->prefix_length = at;
        parsed->implicit_root = true;
        return;
    }
    if (path.len >= 2 && is_ascii_letter(path.ptr[0]) && path.ptr[1] == ':') {
        parsed->prefix_kind = PREFIX_DISK;
        parsed->prefix_length = 2;
    }
}

static Parsed parse(MsFsRules rules, MsBytes path) {
    Parsed parsed = {.rules = rules, .prefix_kind = PREFIX_NONE};
    if (rules == MS_FS_RULES_WINDOWS) {
        parse_windows_prefix(path, &parsed);
    }
    size_t at = parsed.prefix_length;
    if (at < path.len && is_sep(&parsed, path.ptr[at])) {
        parsed.physical_root = true;
        at++;
    }
    parsed.body = at;
    return parsed;
}

static bool has_root(const Parsed *parsed) { return parsed->physical_root || parsed->implicit_root; }

bool ms_fs_is_absolute_with(MsFsRules rules, MsBytes path) {
    const Parsed parsed = parse(rules, path);
    if (rules == MS_FS_RULES_UNIX) {
        return parsed.physical_root;
    }
    return parsed.prefix_kind != PREFIX_NONE && has_root(&parsed);
}

/* ---- elements ---- */

typedef struct Element {
    size_t start;
    size_t length;
    bool parent; /* ".." */
} Element;

/* The next element at or after *at, skipping empty ones and "."; false at the end. */
static bool next_element(const Parsed *parsed, MsBytes path, size_t *at, Element *element) {
    size_t i = *at;
    while (i < path.len) {
        while (i < path.len && is_sep(parsed, path.ptr[i])) {
            i++;
        }
        const size_t start = i;
        while (i < path.len && !is_sep(parsed, path.ptr[i])) {
            i++;
        }
        const size_t length = i - start;
        if (length == 0 || (length == 1 && path.ptr[start] == '.')) {
            continue;
        }
        *element = (Element){.start = start, .length = length, .parent = length == 2 && path.ptr[start] == '.' && path.ptr[start + 1] == '.'};
        *at = i;
        return true;
    }
    *at = i;
    return false;
}

/* Counts the elements, and reports the last. */
static size_t last_element(const Parsed *parsed, MsBytes path, Element *last) {
    size_t count = 0;
    size_t at = parsed->body;
    Element element = {0};
    while (next_element(parsed, path, &at, &element)) {
        *last = element;
        count++;
    }
    return count;
}

static const uint8_t separators[] = {'/', '\\'};
static const uint8_t dot_text[] = {'.'};

static uint8_t separator_of(MsFsRules rules) { return rules == MS_FS_RULES_WINDOWS ? '\\' : '/'; }

/* Writes the path without its last `drop` elements, lexically cleaned. */
static bool clean_elements(MsFsRules rules, MsBytes path, size_t drop, MsFsBuffer *out) {
    const Parsed parsed = parse(rules, path);
    const uint8_t sep = separator_of(rules);
    Element last = {0};
    const size_t total = last_element(&parsed, path, &last);
    const size_t keep = total > drop ? total - drop : 0;

    const size_t base = out->length;
    if (!ms_fs_buffer_append(out, path.ptr, parsed.prefix_length)) {
        return false;
    }
    if (parsed.physical_root && !ms_fs_buffer_push(out, sep)) {
        return false;
    }
    const size_t floor = out->length;
    size_t depth = 0;
    size_t at = parsed.body;
    Element element = {0};
    for (size_t index = 0; index < keep && next_element(&parsed, path, &at, &element); index++) {
        if (element.parent && depth > 0) {
            size_t cut = out->length;
            while (cut > floor && out->data[cut - 1] != sep) {
                cut--;
            }
            /* Back over the separator that precedes the element, but never into the root. */
            out->length = cut > floor ? cut - 1 : floor;
            depth--;
            continue;
        }
        if (element.parent && has_root(&parsed)) {
            continue;
        }
        const bool bare_disk = parsed.prefix_kind == PREFIX_DISK && out->length - base == parsed.prefix_length;
        const bool need_sep = out->length > base && out->data[out->length - 1] != sep && !bare_disk;
        if ((need_sep && !ms_fs_buffer_push(out, sep)) ||
            !ms_fs_buffer_append(out, path.ptr + element.start, element.length)) {
            return false;
        }
        if (!element.parent) {
            depth++;
        }
    }
    return out->length > base || ms_fs_buffer_append(out, dot_text, 1);
}

bool ms_fs_path_clean_with(MsFsRules rules, MsBytes path, MsFsBuffer *out) { return clean_elements(rules, path, 0, out); }

bool ms_fs_path_dir_with(MsFsRules rules, MsBytes path, MsFsBuffer *out) {
    const Parsed parsed = parse(rules, path);
    Element last = {0};
    const size_t total = last_element(&parsed, path, &last);
    return clean_elements(rules, path, total > 0 ? 1 : 0, out);
}

MsBytes ms_fs_path_base_with(MsFsRules rules, MsBytes path) {
    const Parsed parsed = parse(rules, path);
    Element last = {0};
    if (last_element(&parsed, path, &last) > 0) {
        return ms_bytes_of(path.ptr + last.start, last.length);
    }
    if (parsed.physical_root && parsed.prefix_length == 0) {
        return ms_bytes_of(&separators[rules == MS_FS_RULES_WINDOWS ? 1 : 0], 1);
    }
    if (parsed.physical_root) {
        return ms_bytes_of(&separators[1], 1);
    }
    if (parsed.prefix_length > 0) {
        return ms_bytes_of(path.ptr, parsed.prefix_length);
    }
    return ms_bytes_of(dot_text, 1);
}

bool ms_fs_path_join_with(MsFsRules rules, MsBytes first, MsBytes second, MsFsBuffer *out) {
    if (first.len == 0) {
        return second.len == 0 || ms_fs_path_clean_with(rules, second, out);
    }
    if (second.len == 0) {
        return ms_fs_path_clean_with(rules, first, out);
    }
    const Parsed tail = parse(rules, second);
    const Parsed head = parse(rules, first);
    if (ms_fs_is_absolute_with(rules, second) || (tail.prefix_kind != PREFIX_NONE && !tail.physical_root &&
                                                  !(head.prefix_kind == PREFIX_DISK && tail.prefix_kind == PREFIX_DISK &&
                                                    head.prefix_length == 2 && (first.ptr[0] | 0x20) == (second.ptr[0] | 0x20)))) {
        return ms_fs_path_clean_with(rules, second, out);
    }
    MsFsBuffer joined = {0};
    bool built = false;
    if (tail.physical_root && tail.prefix_kind == PREFIX_NONE) {
        /* "\x" keeps the volume of the first element and replaces the rest. */
        built = ms_fs_buffer_append(&joined, first.ptr, head.prefix_length) &&
                ms_fs_buffer_append(&joined, second.ptr, second.len);
    } else {
        const MsBytes rest = ms_bytes_of(second.ptr + tail.prefix_length, second.len - tail.prefix_length);
        const uint8_t last = first.ptr[first.len - 1];
        const bool bare_disk = head.prefix_kind == PREFIX_DISK && first.len == head.prefix_length;
        built = ms_fs_buffer_append(&joined, first.ptr, first.len) &&
                (bare_disk || is_sep(&head, last) || ms_fs_buffer_push(&joined, separator_of(rules))) &&
                ms_fs_buffer_append(&joined, rest.ptr, rest.len);
    }
    const bool cleaned = built && ms_fs_path_clean_with(rules, ms_fs_buffer_view(&joined), out);
    ms_fs_buffer_free(&joined);
    return cleaned;
}

/* ---- the host's rules ---- */

uint8_t ms_fs_separator(void) { return separator_of(HOST_RULES); }
bool ms_fs_is_separator(uint8_t byte) { return ms_fs_is_separator_with(HOST_RULES, byte); }
bool ms_fs_is_absolute(MsBytes path) { return ms_fs_is_absolute_with(HOST_RULES, path); }
bool ms_fs_path_clean(MsBytes path, MsFsBuffer *out) { return ms_fs_path_clean_with(HOST_RULES, path, out); }
bool ms_fs_path_join(MsBytes first, MsBytes second, MsFsBuffer *out) { return ms_fs_path_join_with(HOST_RULES, first, second, out); }
MsBytes ms_fs_path_base(MsBytes path) { return ms_fs_path_base_with(HOST_RULES, path); }
bool ms_fs_path_dir(MsBytes path, MsFsBuffer *out) { return ms_fs_path_dir_with(HOST_RULES, path, out); }
