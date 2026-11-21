/* ms.lock and dependency specs (lock.h). */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/lock.h"

static bool lock_space(char c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f'; }

static bool lock_control(char c) { return (unsigned char)c < 0x20 || c == 0x7f; }

bool ms_is_hex(const char *text, size_t length) {
    if (strlen(text) != length) {
        return false;
    }
    for (size_t i = 0; i < length; i++) {
        if (!((text[i] >= '0' && text[i] <= '9') || (text[i] >= 'a' && text[i] <= 'f'))) {
            return false;
        }
    }
    return true;
}

const char *ms_spec_check(MsArena *a, const char *spec) {
    const char *hash = strchr(spec, '#');
    bool bad = hash == NULL || hash == spec || hash[1] == 0;
    for (const char *c = spec; !bad && *c != 0; c++) {
        bad = lock_space(*c) || lock_control(*c);
    }
    if (bad) {
        return ms_arena_fmt(a, "invalid dependency %s; write \"<git url>#<tag or commit>\", for example \"https://github.com/acme/pg.git#v1.0.0\"", ms_debug_quote(a, spec)).ptr;
    }
    const char *url = ms_arena_strndup(a, spec, (size_t)(hash - spec));
    const char *tag = hash + 1;
    if (strncmp(url, "https://", 8) != 0 && strncmp(url, "file://", 7) != 0) {
        return ms_arena_fmt(a, "dependency URL %s must start with https:// (or file:// for a local repository); other git transports are not supported", ms_debug_quote(a, url)).ptr;
    }
    const size_t length = strlen(tag);
    if (tag[0] == '-' || strstr(tag, "..") != NULL || strpbrk(tag, "~^:?*[\\") != NULL || tag[0] == '/' || tag[length - 1] == '/') {
        return ms_arena_fmt(a, "dependency tag %s is not a plain tag name or full commit", ms_debug_quote(a, tag)).ptr;
    }
    return NULL;
}

const char *ms_repo_key(MsArena *a, const char *url) {
    const char *rest = url;
    bool local = false;
    const char *scheme = strstr(url, "://");
    if (scheme != NULL) {
        local = scheme - url == 4 && strncmp(url, "file", 4) == 0;
        rest = scheme + 3;
    }
    size_t length = strlen(rest);
    while (length > 0 && rest[length - 1] == '/') {
        length--;
    }
    if (length >= 4 && memcmp(rest + length - 4, ".git", 4) == 0) {
        length -= 4;
    }
    if (local) {
        while (length > 0 && *rest == '/') {
            rest++;
            length--;
        }
        return ms_arena_fmt(a, "file/%.*s", (int)length, rest).ptr;
    }
    char *key = ms_arena_strndup(a, rest, length);
    const char *slash = strchr(key, '/');
    const size_t host = slash != NULL ? (size_t)(slash - key) : length;
    for (size_t i = 0; i < host; i++) {
        if (key[i] >= 'A' && key[i] <= 'Z') {
            key[i] = (char)(key[i] - 'A' + 'a');
        }
    }
    return key;
}

const char *ms_copy_id(MsArena *a, const char *url, const char *reference) {
    return ms_arena_fmt(a, "%s@%s", ms_repo_key(a, url), reference).ptr;
}

const char *ms_spec_id(MsArena *a, const char *spec) {
    const char *hash = strchr(spec, '#');
    if (hash == NULL) {
        return NULL;
    }
    return ms_copy_id(a, ms_arena_strndup(a, spec, (size_t)(hash - spec)), hash + 1);
}

bool ms_lock_entry_version(MsArena *a, const MsLockEntry *entry, MsVersion *out) {
    const char *hash = strchr(entry->spec, '#');
    return hash != NULL && ms_version_of_tag(a, hash + 1, out);
}

/* ---- reading ---- */

static bool lock_fail(MsProjectError *err, const char *message) {
    ms_project_error_message(err, message);
    return false;
}

static const char *lock_trim(MsArena *a, const char *begin, const char *end, bool quotes) {
    while (begin < end && (lock_space(*begin) || (quotes && *begin == '"'))) {
        begin++;
    }
    while (end > begin && (lock_space(end[-1]) || (quotes && end[-1] == '"'))) {
        end--;
    }
    return ms_arena_strndup(a, begin, (size_t)(end - begin));
}

/* Splits `value` on whitespace into at most `max` words; returns how many there were. */
static size_t lock_words(MsArena *a, const char *value, const char *words[4]) {
    size_t count = 0;
    const char *c = value;
    for (;;) {
        while (*c != 0 && lock_space(*c)) {
            c++;
        }
        if (*c == 0) {
            return count;
        }
        const char *start = c;
        while (*c != 0 && !lock_space(*c)) {
            c++;
        }
        if (count < 4) {
            words[count] = ms_arena_strndup(a, start, (size_t)(c - start));
        }
        count++;
    }
}

static int lock_entry_order(const void *x, const void *y) {
    const MsLockEntry *left = x, *right = y;
    return strcmp(left->key, right->key);
}

/* One line, already trimmed and not a comment. */
static bool lock_parse_line(MsArena *a, const char *line, uint32_t number, MsLockEntry *entry, MsProjectError *err) {
    const char *shape = ms_arena_fmt(a, "ms.lock line %u is not `\"@name\" = \"url#tag revision sha256:hash\"`; delete ms.lock and run ms install to pin again", number).ptr;
    const char *equals = strchr(line, '=');
    if (equals == NULL) {
        return lock_fail(err, shape);
    }
    const char *key = lock_trim(a, line, equals, true);
    const char *value = lock_trim(a, equals + 1, equals + strlen(equals), true);
    bool key_bad = key[0] == 0;
    for (const char *c = key; *c != 0; c++) {
        key_bad |= lock_space(*c) || lock_control(*c);
    }
    const char *words[4] = {0};
    if (key_bad || lock_words(a, value, words) != 3 || strncmp(words[2], "sha256:", 7) != 0) {
        return lock_fail(err, shape);
    }
    const char *hash = words[2] + 7;
    if (!ms_is_hex(words[1], 40) || !ms_is_hex(hash, 64)) {
        return lock_fail(err, ms_arena_fmt(a, "ms.lock line %u must hold a 40-digit commit and a 64-digit sha256, both lowercase hexadecimal; delete ms.lock and run ms install to pin again", number).ptr);
    }
    const char *why = ms_spec_check(a, words[0]);
    if (why != NULL) {
        ms_project_error_message(err, ms_arena_fmt(a, "ms.lock line %u: %s", number, why).ptr);
        return false;
    }
    const char *id = ms_spec_id(a, words[0]);
    if (id == NULL || strcmp(id, key) != 0) {
        return lock_fail(err, ms_arena_fmt(a, "ms.lock line %u is keyed %s, but its source is %s; delete ms.lock and run ms install to pin again", number, key, words[0]).ptr);
    }
    *entry = (MsLockEntry){.key = key, .spec = words[0], .revision = words[1], .sha256 = hash};
    return true;
}

bool ms_lock_parse(MsArena *a, const char *text, MsLock *out, MsProjectError *err) {
    if (strncmp(text, "\xef\xbb\xbf", 3) == 0) {
        text += 3;
    }
    MsBuf entries = {0};
    bool ok = true;
    uint32_t number = 0;
    while (ok && *text != 0) {
        const char *end = strchr(text, '\n');
        const char *next = end != NULL ? end + 1 : text + strlen(text);
        if (end == NULL) {
            end = next;
        }
        number++;
        const char *line = lock_trim(a, text, end, false);
        text = next;
        if (line[0] == 0 || line[0] == '#') {
            continue;
        }
        MsLockEntry entry;
        ok = lock_parse_line(a, line, number, &entry, err);
        for (size_t i = 0; ok && i < MS_VEC_LEN(entries, MsLockEntry); i++) {
            if (strcmp(MS_VEC_AT(entries, MsLockEntry, i).key, entry.key) == 0) {
                ok = lock_fail(err, ms_arena_fmt(a, "ms.lock line %u repeats %s; a merge may have kept both sides, so delete ms.lock and run ms install to pin again", number, entry.key).ptr);
            }
        }
        if (ok) {
            MS_VEC_PUSH(entries, MsLockEntry, entry);
        }
    }
    if (ok) {
        const size_t count = MS_VEC_LEN(entries, MsLockEntry);
        out->entries = MS_NEW_N(a, MsLockEntry, count + 1);
        out->count = (uint32_t)count;
        if (count > 0) {
            memcpy(out->entries, ms_buf_items(&entries), count * sizeof(MsLockEntry));
            qsort(out->entries, count, sizeof(MsLockEntry), lock_entry_order);
        }
    }
    ms_buf_free(&entries);
    return ok;
}

bool ms_lock_read(MsArena *a, const char *root, MsLock *out, MsProjectError *err) {
    *out = (MsLock){0};
    const char *path = MS_PATH_JOIN(a, root, "ms.lock");
    FILE *f = fopen(path, "rbe");
    if (f == NULL) {
        if (errno == ENOENT) {
            out->entries = MS_NEW(a, MsLockEntry);
            return true;
        }
        ms_project_error_path(err, a, "open", path, errno);
        return false;
    }
    MsBuf data = {0};
    char chunk[4096];
    size_t n;
    while ((n = fread(chunk, 1, sizeof chunk, f)) > 0) {
        ms_buf_put(&data, chunk, n);
    }
    const bool failed = ferror(f) != 0;
    fclose(f);
    if (failed) {
        ms_buf_free(&data);
        ms_project_error_path(err, a, "read", path, EIO);
        return false;
    }
    char *text = ms_arena_strndup(a, data.data == NULL ? "" : data.data, data.len);
    ms_buf_free(&data);
    return ms_lock_parse(a, text, out, err);
}

const MsLockEntry *ms_lock_find(const MsLock *lock, const char *key) {
    for (uint32_t i = 0; i < lock->count; i++) {
        if (strcmp(lock->entries[i].key, key) == 0) {
            return &lock->entries[i];
        }
    }
    return NULL;
}

const char *ms_lock_text(MsArena *a, MsLockEntry *entries, uint32_t count) {
    if (count > 1) {
        qsort(entries, count, sizeof(MsLockEntry), lock_entry_order);
    }
    MsBuf text = {0};
    ms_buf_puts(&text, "# Written by `ms install`. Commit it: it pins each package to a commit and a content hash.\n");
    for (uint32_t i = 0; i < count; i++) {
        ms_buf_printf(&text, "\"%s\" = \"%s %s sha256:%s\"\n", entries[i].key, entries[i].spec, entries[i].revision, entries[i].sha256);
    }
    char *result = ms_arena_strndup(a, text.data, text.len);
    ms_buf_free(&text);
    return result;
}
