/* Unit test for src/runtime/std/json_*.c, which `make c-test` builds with ASan and UBSan over the real src/runtime/core.
 * It replays src/runtime/tests/oracle/json.tsv (recorded from Go's encoding/json: parse, stringify, float text and scalar
 * decoding cases), then checks the document accessors, the typed-decode error text, the writer's undo and the tree
 * natives with a small recursive alternative. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms_rt/alloc.h"
#include "ms_rt/json.h"
#include "ms_rt/list.h"
#include "ms_rt/map.h"
#include "ms_rt/safe.h"
#include "ms_rt/string.h"
#include "ms_rt/utf8.h"
#include "append.h"
#include "rt_stubs.h"

static int checks;

static void check(bool ok, int line, const char *text) {
    checks++;
    if (!ok) {
        fprintf(stderr, "json_test.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

enum { OK = 0, INVALID_INPUT = 1, LIMIT_EXCEEDED = 3, INVALID_DATA = 4 };
enum { KIND_NULL = 0, KIND_BOOL = 1, KIND_NUMBER = 2, KIND_STRING = 3, KIND_ARRAY = 4, KIND_OBJECT = 5 };

/* A string value that borrows `bytes`. */
static MsStr view(const uint8_t *bytes, size_t length) {
    return (MsStr){.bytes = bytes, .tagged = ((uint64_t)3 << MS_STR_TAG_SHIFT) | length};
}

static MsStr lit(const char *text) { return view((const uint8_t *)text, strlen(text)); }

static const char *status_name(int status) {
    switch (status) {
    case INVALID_INPUT: return "InvalidInput";
    case LIMIT_EXCEEDED: return "LimitExceeded";
    case INVALID_DATA: return "InvalidData";
    default: return "Other";
    }
}

/* ---- the recorded cases ---- */

enum { TEXT_CAP = 1 << 20 };

/* The bytes of a recorded `x<hex>` token; returns the length. */
static size_t unhex(const char *token, uint8_t *out) {
    size_t length = 0;
    for (const char *p = token + 1; p[0] != '\0'; p += 2) {
        unsigned value = 0;
        CHECK(sscanf(p, "%2x", &value) == 1);
        out[length++] = (uint8_t)value;
    }
    return length;
}

static void put_hex(char *dst, size_t cap, const uint8_t *bytes, size_t length) {
    for (size_t i = 0; i < length; i++) {
        msx_append(dst, cap, "%02x", bytes[i]);
    }
}

/* A limit token: `-` is unset. */
static void limit_of(const char *token, uint8_t *has, int64_t *value) {
    *has = token[0] != '-' || token[1] != '\0';
    *value = *has ? strtoll(token, NULL, 10) : 0;
}

/* The dump form of a document: N, T, F, #<number>; s<hex>; [..] {<hexkey>:..}. */
static void dump(const void *doc, uint32_t id, char *out, size_t cap) {
    switch (msstd_json_kind(doc, id)) {
    case KIND_NULL: msx_append(out, cap, "N"); break;
    case KIND_BOOL: msx_append(out, cap, msstd_json_bool(doc, id) ? "T" : "F"); break;
    case KIND_NUMBER: {
        MsStr text;
        msstd_json_text(doc, id, &text);
        msx_append(out, cap, "#%.*s;", (int)ms_str_len(&text), (const char *)ms_str_data(&text));
        msrt_string_free(&text);
        break;
    }
    case KIND_STRING: {
        MsStr text;
        msstd_json_text(doc, id, &text);
        msx_append(out, cap, "s");
        put_hex(out, cap, ms_str_data(&text), ms_str_len(&text));
        msrt_string_free(&text);
        msx_append(out, cap, ";");
        break;
    }
    case KIND_ARRAY:
        msx_append(out, cap, "[");
        for (int64_t i = 0; i < msstd_json_len(doc, id); i++) {
            dump(doc, msstd_json_item(doc, id, i), out, cap);
        }
        msx_append(out, cap, "]");
        break;
    default:
        msx_append(out, cap, "{");
        for (int64_t i = 0; i < msstd_json_len(doc, id); i++) {
            MsStr key;
            msstd_json_key(doc, id, i, &key);
            put_hex(out, cap, ms_str_data(&key), ms_str_len(&key));
            msrt_string_free(&key);
            msx_append(out, cap, ":");
            dump(doc, msstd_json_item(doc, id, i), out, cap);
        }
        msx_append(out, cap, "}");
        break;
    }
}

static bool valid_utf8(const uint8_t *bytes, size_t length) {
    for (size_t at = 0; at < length;) {
        const MsRune rune = ms_utf8_decode(bytes + at, length - at);
        if (rune.rune == MS_RUNE_ERROR && rune.width == 1) {
            return false;
        }
        at += rune.width;
    }
    return true;
}

/* Parses the case's text under its limits and appends the answer; false for a case this test does not run. */
static bool parse_case(char **fields, char *got, size_t cap) {
    static uint8_t bytes[TEXT_CAP];
    const size_t length = unhex(fields[1], bytes);
    if (!valid_utf8(bytes, length)) {
        return false;
    }
    uint8_t has[3];
    int64_t value[3];
    for (int i = 0; i < 3; i++) {
        limit_of(fields[2 + i], &has[i], &value[i]);
    }
    const MsStr text = view(bytes, length);
    void *doc = NULL;
    uint32_t root = 0;
    const int status = msstd_json_parse(&text, has[0], value[0], has[1], value[1], has[2], value[2], &doc, &root, NULL);
    if (status != OK) {
        msx_append(got, cap, "err %s", status_name(status));
        return true;
    }
    msx_append(got, cap, "ok ");
    dump(doc, root, got, cap);
    ((MsObj *)doc)->drop(doc);
    return true;
}

/* The next `x<hex>` token or dump form of a stringify case, as a tree built in place. */
typedef struct Node Node;
struct Node {
    char kind; /* N T F # s [ { */
    char *text;
    size_t length;
    Node **children;
    char **keys;
    size_t count;
};

static void node_free(Node *node) {
    for (size_t i = 0; i < node->count; i++) {
        node_free(node->children[i]);
        free(node->keys ? node->keys[i] : NULL);
    }
    free(node->children);
    free(node->keys);
    free(node->text);
    free(node);
}

static Node *node_load(const char *dump_text, size_t *pos);

/* The hex run up to `end`, as bytes in a new allocation. */
static char *take_hex(const char *text, size_t *pos, char end, size_t *length) {
    const char *stop = strchr(text + *pos, end);
    CHECK(stop != NULL);
    const size_t digits = (size_t)(stop - (text + *pos));
    char *token = malloc(digits + 2);
    token[0] = 'x';
    memcpy(token + 1, text + *pos, digits);
    token[digits + 1] = '\0';
    uint8_t *bytes = malloc(digits / 2 + 1);
    *length = unhex(token, bytes);
    free(token);
    *pos = (size_t)(stop - text) + 1;
    return (char *)bytes;
}

static Node *node_load(const char *text, size_t *pos) {
    Node *node = calloc(1, sizeof *node);
    node->kind = text[(*pos)++];
    if (node->kind == '#') {
        const char *stop = strchr(text + *pos, ';');
        node->length = (size_t)(stop - (text + *pos));
        node->text = malloc(node->length + 1);
        memcpy(node->text, text + *pos, node->length);
        node->text[node->length] = '\0';
        *pos = (size_t)(stop - text) + 1;
    } else if (node->kind == 's') {
        node->text = take_hex(text, pos, ';', &node->length);
    } else if (node->kind == '[' || node->kind == '{') {
        const char close = node->kind == '[' ? ']' : '}';
        while (text[*pos] != close) {
            char *key = NULL;
            size_t key_length = 0;
            if (node->kind == '{') {
                key = take_hex(text, pos, ':', &key_length);
                key = realloc(key, key_length + 1);
                key[key_length] = '\0';
            }
            Node *child = node_load(text, pos);
            size_t at = node->count;
            for (size_t i = 0; key != NULL && i < node->count; i++) {
                if (strcmp(node->keys[i], key) == 0) { /* a repeated key keeps its first place and the last value */
                    at = i;
                }
            }
            if (at < node->count) {
                node_free(node->children[at]);
                node->children[at] = child;
                free(key);
                continue;
            }
            node->children = realloc(node->children, (node->count + 1) * sizeof *node->children);
            node->keys = realloc(node->keys, (node->count + 1) * sizeof *node->keys);
            node->children[node->count] = child;
            node->keys[node->count] = key;
            node->count++;
        }
        (*pos)++;
    }
    return node;
}

static void emit(void *writer, const Node *node) {
    switch (node->kind) {
    case 'N': msstd_json_w_null(writer); break;
    case 'T': msstd_json_w_bool(writer, 1); break;
    case 'F': msstd_json_w_bool(writer, 0); break;
    case '#': {
        const MsStr text = view((const uint8_t *)node->text, node->length);
        msstd_json_w_number(writer, &text);
        break;
    }
    case 's': {
        const MsStr text = view((const uint8_t *)node->text, node->length);
        msstd_json_w_string(writer, &text);
        break;
    }
    case '[':
        msstd_json_w_begin_array(writer);
        for (size_t i = 0; i < node->count; i++) {
            msstd_json_w_item(writer);
            emit(writer, node->children[i]);
        }
        msstd_json_w_end_array(writer);
        break;
    default:
        msstd_json_w_begin_object(writer);
        for (size_t i = 0; i < node->count; i++) {
            const MsStr key = lit(node->keys[i]);
            msstd_json_w_key(writer, &key);
            emit(writer, node->children[i]);
        }
        msstd_json_w_end_object(writer);
        break;
    }
}

/* Writes a result string as `ok x<hex>` or `err <name>`. */
static void answer(char *got, size_t cap, int status, const MsStr *out) {
    if (status != OK) {
        msx_append(got, cap, "err %s", status_name(status));
        return;
    }
    msx_append(got, cap, "ok x");
    put_hex(got, cap, ms_str_data(out), ms_str_len(out));
    ms_str_release(out);
}

static void stringify_case(char **fields, char *got, size_t cap) {
    uint8_t has[2];
    int64_t value[2];
    limit_of(fields[2], &has[0], &value[0]);
    limit_of(fields[3], &has[1], &value[1]);
    size_t pos = 0;
    Node *root = node_load(fields[1], &pos);
    void *writer = msstd_json_writer_new(has[0], value[0], has[1], value[1]);
    emit(writer, root);
    MsStr out = {0};
    answer(got, cap, msstd_json_w_finish(writer, &out), &out);
    ((MsObj *)writer)->drop(writer);
    node_free(root);
}

static void float_case(char **fields, char *got, size_t cap) {
    const uint64_t bits = strtoull(fields[1], NULL, 16);
    double number = 0;
    memcpy(&number, &bits, sizeof number);
    void *writer = msstd_json_writer_new(0, 0, 0, 0);
    msstd_json_w_float(writer, number);
    MsStr out = {0};
    CHECK(msstd_json_w_finish(writer, &out) == OK);
    if (ms_str_len(&out) == 4 && memcmp(ms_str_data(&out), "null", 4) == 0) {
        msx_append(got, cap, "N");
    } else {
        msx_append(got, cap, "#%.*s;", (int)ms_str_len(&out), (const char *)ms_str_data(&out));
    }
    ms_str_release(&out);
    ((MsObj *)writer)->drop(writer);
}

static void scalar_case(char **fields, char *got, size_t cap) {
    static uint8_t bytes[TEXT_CAP];
    const MsStr text = view(bytes, unhex(fields[1], bytes));
    int64_t integer = 0;
    double number = 0;
    const bool int_ok = msstd_json_dec_int(&text, &integer) == OK;
    const bool float_ok = msstd_json_dec_float(&text, &number) == OK;
    uint64_t bits = 0;
    memcpy(&bits, &number, sizeof bits);
    msx_append(got, cap, "%d %lld %d %llx", int_ok, (long long)(int_ok ? integer : 0), float_ok,
               (unsigned long long)(float_ok ? bits : 0));
}

static void deep_case(char **fields, char *got, size_t cap) {
    const size_t depth = (size_t)strtoull(fields[1], NULL, 10);
    char *text = malloc(depth * 2 + 1);
    memset(text, '[', depth);
    memset(text + depth, ']', depth);
    text[depth * 2] = '\0';
    const MsStr input = lit(text);
    void *doc = NULL;
    uint32_t root = 0;
    const int status = msstd_json_parse(&input, 0, 0, 0, 0, 0, 0, &doc, &root, NULL);
    if (status == OK) {
        msx_append(got, cap, "ok deep");
        ((MsObj *)doc)->drop(doc);
    } else {
        msx_append(got, cap, "err %s", status_name(status));
    }
    free(text);
}

static void test_recorded_cases(void) {
    FILE *file = fopen("src/runtime/tests/oracle/json.tsv", "r");
    CHECK(file != NULL);
    static char line[TEXT_CAP];
    static char got[TEXT_CAP];
    size_t cases = 0;
    while (fgets(line, sizeof line, file) != NULL) {
        line[strcspn(line, "\n")] = '\0';
        if (line[0] == '#') {
            continue;
        }
        char *fields[8] = {0};
        size_t count = 0;
        for (char *p = line; p != NULL && count < 8;) {
            fields[count++] = p;
            p = strchr(p, '\t');
            if (p != NULL) {
                *p++ = '\0';
            }
        }
        got[0] = '\0';
        const char *kind = fields[0];
        bool ran = true;
        if (strcmp(kind, "parse") == 0) {
            ran = parse_case(fields, got, sizeof got);
        } else if (strcmp(kind, "deep") == 0) {
            deep_case(fields, got, sizeof got);
        } else if (strcmp(kind, "stringify") == 0) {
            stringify_case(fields, got, sizeof got);
        } else if (strcmp(kind, "float") == 0) {
            float_case(fields, got, sizeof got);
        } else {
            scalar_case(fields, got, sizeof got);
        }
        if (!ran) {
            continue;
        }
        cases++;
        const char *want = fields[count - 1];
        if (strcmp(got, want) != 0) {
            fprintf(stderr, "case %.120s\n  got  %.200s\n  want %.200s\n", line, got, want);
            abort();
        }
    }
    fclose(file);
    CHECK(cases > 5000);
}


/* ---- targeted checks ---- */

static bool same(const MsStr *text, const char *want) {
    return ms_str_len(text) == strlen(want) && memcmp(ms_str_data(text), want, strlen(want)) == 0;
}

/* Parses `source` (no limits) and returns the status; the document or the error text goes to the out parameters. */
static int parse_plain(const char *source, void **doc, uint32_t *root, MsStr *err) {
    const MsStr text = lit(source);
    return msstd_json_parse(&text, 0, 0, 0, 0, 0, 0, doc, root, err);
}

static void expect_error_text(const char *source, const char *want) {
    void *doc = NULL;
    uint32_t root = 0;
    MsStr err = {0};
    CHECK(parse_plain(source, &doc, &root, &err) == INVALID_DATA);
    const bool matches = same(&err, want);
    if (!matches) {
        fprintf(stderr, "error text of %s: got %.*s\n", source, (int)ms_str_len(&err), (const char *)ms_str_data(&err));
    }
    CHECK(matches);
    ms_str_release(&err);
}

static void test_error_text(void) {
    expect_error_text("{\"a\":1,}", "line 1, column 8: unexpected character `}`");
    expect_error_text("[1,\n2,\n x]", "line 3, column 2: unexpected character `x`");
    expect_error_text("{\"a\":1,\"a\":2}", "line 1, column 14: duplicate object key");
    expect_error_text("[1,", "line 1, column 4: unexpected end of input");
    expect_error_text("[1,\x01]", "line 1, column 4: unexpected character U+0001");
    expect_error_text("\xc3\xa9", "line 1, column 1: unexpected character `\xc3\xa9`");
    /* A bad separator is consumed before it is reported, so the error is at the byte after it, counted in scalars. */
    expect_error_text("[\"\xc3\xa9\" x]", "line 1, column 7: unexpected character `]`");
}

/* The caller may read the error slot for any failure status, so a failure without text leaves it the empty string. */
static void test_error_slot_is_always_valid(void) {
    const MsStr text = lit("true");
    void *doc = NULL;
    uint32_t root = 0;
    MsStr err;
    memset(&err, 0xFF, sizeof err);
    CHECK(msstd_json_parse(&text, 0, 0, 0, 0, 1, 0, &doc, &root, &err) == LIMIT_EXCEEDED);
    CHECK(ms_str_len(&err) == 0);
    memset(&err, 0xFF, sizeof err);
    CHECK(msstd_json_parse(&text, 0, 0, 0, 0, 1, -1, &doc, &root, &err) == INVALID_INPUT);
    CHECK(ms_str_len(&err) == 0);
}

static void test_document_accessors(void) {
    void *doc = NULL;
    uint32_t root = 0;
    CHECK(parse_plain("{\"name\":\"x\",\"tags\":[\"a\",\"b\"],\"n\":3,\"ok\":true,\"e\\u00e9\":null}", &doc, &root, NULL) == OK);
    CHECK(msstd_json_kind(doc, root) == KIND_OBJECT);
    CHECK(msstd_json_len(doc, root) == 5);
    const MsStr tags = lit("tags");
    const MsStr missing = lit("missing");
    const int64_t tags_at = msstd_json_find(doc, root, &tags);
    CHECK(tags_at == 1 && msstd_json_find(doc, root, &missing) == -1);
    const uint32_t tag_list = msstd_json_item(doc, root, tags_at);
    CHECK(msstd_json_kind(doc, tag_list) == KIND_ARRAY && msstd_json_len(doc, tag_list) == 2);
    MsStr key = {0};
    msstd_json_key(doc, root, 4, &key);
    CHECK(same(&key, "e\xc3\xa9"));
    msrt_string_free(&key);
    CHECK(msstd_json_bool(doc, msstd_json_item(doc, root, 3)) == 1);

    /* A list of known names: every member is known, then one is not. */
    MsList names = {0};
    msrt_list_with_capacity(&msrt_desc_string, 5, &names);
    const char *const known[] = {"name", "tags", "n", "ok", "e\xc3\xa9"};
    for (size_t i = 0; i < 5; i++) {
        MsStr entry = {0};
        msrt_string_from_bytes((const uint8_t *)known[i], strlen(known[i]), &entry);
        msrt_list_push(&names, &msrt_desc_string, (const uint8_t *)&entry);
    }
    CHECK(msstd_json_has_unknown(doc, root, &names) == 0);
    int64_t payload = 0;
    CHECK(msstd_json_variant(doc, root, &names, &payload) == -1);

    /* The typed decode of tags[1] failed: the message names its path. */
    const MsStr wanted = lit("Int");
    msstd_json_mismatch(doc, msstd_json_item(doc, tag_list, 1), 1, &wanted);
    MsStr message = {0};
    msstd_json_mismatch_text(doc, root, &message);
    CHECK(same(&message, "JSON: invalid data: at $.tags[1]: expected Int, found string"));
    ms_str_release(&message);
    msstd_json_mismatch(doc, root, 2, &tags);
    msstd_json_mismatch_text(doc, root, &message);
    CHECK(same(&message, "JSON: invalid data: at $: missing field \"tags\""));
    ms_str_release(&message);
    msstd_json_mismatch(doc, msstd_json_item(doc, root, 2), 0, &wanted);
    msstd_json_mismatch_text(doc, root, &message);
    CHECK(same(&message, "JSON: invalid data: at $.n: number does not fit Int"));
    ms_str_release(&message);
    msrt_list_drop(&names, &msrt_desc_string);
    ((MsObj *)doc)->drop(doc);

    /* A variant is a bare name or a single-key object. */
    CHECK(parse_plain("\"b\"", &doc, &root, NULL) == OK);
    MsList variants = {0};
    msrt_list_with_capacity(&msrt_desc_string, 2, &variants);
    for (size_t i = 0; i < 2; i++) {
        MsStr entry = {0};
        msrt_string_from_bytes((const uint8_t *)(i == 0 ? "a" : "b"), 1, &entry);
        msrt_list_push(&variants, &msrt_desc_string, (const uint8_t *)&entry);
    }
    CHECK(msstd_json_variant(doc, root, &variants, &payload) == 1 && payload == -1);
    ((MsObj *)doc)->drop(doc);
    CHECK(parse_plain("{\"a\":[1]}", &doc, &root, NULL) == OK);
    CHECK(msstd_json_variant(doc, root, &variants, &payload) == 0 && msstd_json_kind(doc, (uint32_t)payload) == KIND_ARRAY);
    ((MsObj *)doc)->drop(doc);
    msrt_list_drop(&variants, &msrt_desc_string);
}

static void test_scalars(void) {
    int64_t integer = 0;
    double number = 0;
    const MsStr plus = lit("+5");
    const MsStr minus_zero = lit("-0");
    const MsStr spaced = lit(" 5");
    const MsStr empty = lit("");
    CHECK(msstd_json_dec_int(&plus, &integer) == OK && integer == 5);
    CHECK(msstd_json_dec_int(&spaced, &integer) != OK && msstd_json_dec_int(&empty, &integer) != OK);
    CHECK(msstd_json_dec_uint(&plus, &integer) == OK && integer == 5);
    CHECK(msstd_json_dec_uint(&minus_zero, &integer) != OK);
    const MsStr max_uint = lit("18446744073709551615");
    CHECK(msstd_json_dec_uint(&max_uint, &integer) == OK && integer == -1);
    const MsStr over = lit("18446744073709551616");
    CHECK(msstd_json_dec_uint(&over, &integer) != OK);
    const MsStr small = lit("300");
    CHECK(msstd_json_dec_int_in(&small, -128, 127, &integer) != OK && msstd_json_dec_int_in(&small, 0, 300, &integer) == OK);
    const MsStr third = lit("0.1");
    const MsStr huge = lit("3.4e38");
    const MsStr too_huge = lit("3.5e38");
    CHECK(msstd_json_dec_float32(&third, &number) == OK && number == (double)0.1f);
    CHECK(msstd_json_dec_float32(&huge, &number) == OK && msstd_json_dec_float32(&too_huge, &number) != OK);
    const MsStr word = lit("inf");
    CHECK(msstd_json_dec_float(&word, &number) != OK);
}

static MsStr finish_text(void *writer, int *status) {
    MsStr out = {0};
    *status = msstd_json_w_finish(writer, &out);
    return out;
}

static void test_writer(void) {
    int status = 0;
    /* Indented output, a key written already quoted, a lost field removed with undo. */
    void *writer = msstd_json_writer_new(0, 0, 1, 2);
    msstd_json_w_begin_object(writer);
    const MsStr quoted = lit("\"a\"");
    msstd_json_w_key_quoted(writer, &quoted);
    msstd_json_w_int(writer, -7);
    const MsStr dropped = lit("dropped");
    msstd_json_w_key(writer, &dropped);
    msstd_json_w_undo(writer);
    const MsStr list_key = lit("l");
    msstd_json_w_key(writer, &list_key);
    msstd_json_w_begin_array(writer);
    msstd_json_w_item(writer);
    msstd_json_w_float(writer, 1e21);
    msstd_json_w_item(writer);
    msstd_json_w_float32(writer, (double)0.1f);
    msstd_json_w_item(writer);
    msstd_json_w_uint(writer, -1);
    msstd_json_w_end_array(writer);
    msstd_json_w_end_object(writer);
    msstd_json_w_no_form(writer);
    CHECK(msstd_json_w_lost(writer) == 1);
    MsStr out = finish_text(writer, &status);
    CHECK(status == OK);
    CHECK(same(&out, "{\n  \"a\": -7,\n  \"l\": [\n    1e+21,\n    0.1,\n    18446744073709551615\n  ]\n}"));
    ms_str_release(&out);
    ((MsObj *)writer)->drop(writer);

    /* A number that is not JSON, an unclosed container, a byte budget, a negative budget. */
    writer = msstd_json_writer_new(0, 0, 0, 0);
    const MsStr bad_number = lit("01");
    msstd_json_w_number(writer, &bad_number);
    msstd_json_w_null(writer);
    (void)finish_text(writer, &status);
    CHECK(status == INVALID_DATA);
    ((MsObj *)writer)->drop(writer);
    writer = msstd_json_writer_new(0, 0, 0, 0);
    msstd_json_w_begin_array(writer);
    (void)finish_text(writer, &status);
    CHECK(status == INVALID_DATA);
    ((MsObj *)writer)->drop(writer);
    writer = msstd_json_writer_new(1, 3, 0, 0);
    msstd_json_w_bool(writer, 1);
    (void)finish_text(writer, &status);
    CHECK(status == LIMIT_EXCEEDED);
    ((MsObj *)writer)->drop(writer);
    writer = msstd_json_writer_new(0, 0, 1, -1);
    (void)finish_text(writer, &status);
    CHECK(status == INVALID_INPUT);
    ((MsObj *)writer)->drop(writer);

    /* Text with escapes and a long result (more than an inline string holds). */
    writer = msstd_json_writer_new(0, 0, 0, 0);
    const MsStr text = lit("a\"b\\c\n\x01 long enough to leave the inline form");
    msstd_json_w_string(writer, &text);
    out = finish_text(writer, &status);
    CHECK(status == OK && same(&out, "\"a\\\"b\\\\c\\n\\u0001 long enough to leave the inline form\""));
    ms_str_release(&out);
    ((MsObj *)writer)->drop(writer);
}

/* ---- the tree natives, over a small recursive alternative ---- */

typedef struct Value {
    uint64_t kind;
    union {
        uint8_t flag;
        MsStr text;
        MsList list;
        MsMap map;
    } as;
} Value;

static void value_drop(uint8_t *slot);

static const MsTypeDesc VALUE = {.size = sizeof(Value), .align = 8, .kind = MS_KIND_CUSTOM, .drop = value_drop};

static void value_drop(uint8_t *slot) {
    Value value;
    memcpy(&value, slot, sizeof value);
    if (value.kind == KIND_NUMBER || value.kind == KIND_STRING) {
        ms_str_release(&value.as.text);
    } else if (value.kind == KIND_ARRAY) {
        msrt_list_drop(&value.as.list, &VALUE);
    } else if (value.kind == KIND_OBJECT) {
        msrt_map_drop(&value.as.map, &msrt_desc_string, &VALUE);
    }
}

static int64_t value_ctor(int64_t kind, uint8_t *payload, uint8_t *out) {
    Value value = {.kind = (uint64_t)kind};
    switch (kind) {
    case KIND_BOOL: memcpy(&value.as.flag, payload, sizeof value.as.flag); break;
    case KIND_NUMBER:
    case KIND_STRING: memcpy(&value.as.text, payload, sizeof value.as.text); break;
    case KIND_ARRAY: memcpy(&value.as.list, payload, sizeof value.as.list); break;
    case KIND_OBJECT: memcpy(&value.as.map, payload, sizeof value.as.map); break;
    default: break;
    }
    memcpy(out, &value, sizeof value);
    return 0;
}

static void value_view(const uint8_t *slot, uint8_t *sink, uint8_t *walk) {
    Value value;
    memcpy(&value, slot, sizeof value);
    switch (value.kind) {
    case KIND_NULL: msstd_json_w_null(sink); break;
    case KIND_BOOL: msstd_json_w_bool(sink, value.as.flag); break;
    case KIND_NUMBER: msstd_json_w_number(sink, &value.as.text); break;
    case KIND_STRING: msstd_json_w_string(sink, &value.as.text); break;
    case KIND_ARRAY: msstd_json_tree_array((JsonWalk *)(void *)walk, &value.as.list); break;
    default: msstd_json_tree_object((JsonWalk *)(void *)walk, &value.as.map); break;
    }
}

/* Parses `source` into a Value tree and writes it back; the status of the parse, and the text when it succeeded. */
static int tree_roundtrip(const char *source, char *got, size_t cap) {
    const MsStr text = lit(source);
    Value root;
    const int status = msstd_json_parse_tree(&text, 0, 0, 0, 0, 0, 0, &VALUE, value_ctor, (uint8_t *)&root, NULL);
    if (status != OK) {
        return status;
    }
    void *writer = msstd_json_writer_new(0, 0, 0, 0);
    msstd_json_w_tree(writer, &VALUE, value_view, (const uint8_t *)&root);
    MsStr out = {0};
    CHECK(msstd_json_w_finish(writer, &out) == OK);
    msx_append(got, cap, "%.*s", (int)ms_str_len(&out), (const char *)ms_str_data(&out));
    ms_str_release(&out);
    ((MsObj *)writer)->drop(writer);
    value_drop((uint8_t *)&root);
    return OK;
}

static void test_tree(void) {
    char got[256];
    const char *const same_back[] = {"null", "true", "[]", "{}", "[1,\"two\",[3.50],{\"k\":null}]",
                                     "{\"a\":{\"b\":[{}]},\"c\":\"\\u0001x\"}"};
    for (size_t i = 0; i < MS_COUNT_OF(same_back); i++) {
        got[0] = '\0';
        CHECK(tree_roundtrip(same_back[i], got, sizeof got) == OK);
        CHECK(strcmp(got, same_back[i]) == 0);
    }
    /* Whitespace and escapes are normalized, and number text stays as written. */
    got[0] = '\0';
    CHECK(tree_roundtrip(" { \"a\" : [ 1e5 , -0 ,\"\\u00e9\\n\" ] } ", got, sizeof got) == OK);
    CHECK(strcmp(got, "{\"a\":[1e5,-0,\"\xc3\xa9\\n\"]}") == 0);
    /* A repeated key anywhere in the document fails and releases everything built so far. */
    CHECK(tree_roundtrip("[1,{\"x\":[\"s\"],\"y\":true,\"x\":null}]", got, sizeof got) == INVALID_DATA);
    CHECK(tree_roundtrip("[1,", got, sizeof got) == INVALID_DATA);
    /* Deep nesting costs heap, not stack. */
    enum { DEPTH = 3000 };
    static char deep[DEPTH * 2 + 1];
    memset(deep, '[', DEPTH);
    memset(deep + DEPTH, ']', DEPTH);
    static char deep_back[DEPTH * 2 + 1];
    deep_back[0] = '\0';
    CHECK(tree_roundtrip(deep, deep_back, sizeof deep_back) == OK && strcmp(deep, deep_back) == 0);
}

/* The scanner reads eight bytes at a time for strings, spaces and digits, so every offset of a special byte, a run
 * length and the end of the text relative to a word boundary has to give the same answer as a byte at a time. */
static void test_word_boundaries(void) {
    char text[256];
    for (size_t pad = 0; pad < 40; pad++) {
        /* A string of `pad` letters, then an escape, then letters again. */
        char *out = text;
        *out++ = '"';
        memset(out, 'a', pad);
        out += pad;
        memcpy(out, "\\n\\u00e9bb\"", 11);
        out += 11;
        *out = '\0';
        void *doc = NULL;
        uint32_t root = 0;
        CHECK(parse_plain(text, &doc, &root, NULL) == OK);
        MsStr got = {0};
        msstd_json_text(doc, root, &got);
        CHECK(ms_str_len(&got) == pad + 1 + 2 + 2);
        msrt_string_free(&got);
        ((MsObj *)doc)->drop(doc);

        /* A control character, a quote that ends the text, and a missing closing quote after `pad` letters. */
        out = text;
        *out++ = '"';
        memset(out, 'a', pad);
        out += pad;
        *out++ = '\x01';
        *out++ = '"';
        *out = '\0';
        CHECK(parse_plain(text, &doc, &root, NULL) == INVALID_DATA);
        text[pad + 1] = '\0';
        CHECK(parse_plain(text, &doc, &root, NULL) == INVALID_DATA);

        /* Whitespace of `pad` bytes of every kind around a value, and at the very end of the text. */
        const char kinds[] = {' ', '\n', '\t', '\r'};
        for (size_t kind = 0; kind < 4; kind++) {
            out = text;
            *out++ = '[';
            for (size_t i = 0; i < pad; i++) {
                *out++ = i % 7 == 6 ? kinds[kind] : (kind == 0 ? ' ' : kinds[(kind + i) % 4]);
            }
            *out++ = '1';
            for (size_t i = 0; i < pad; i++) {
                *out++ = kinds[(kind + i) % 4];
            }
            *out++ = ']';
            for (size_t i = 0; i < pad; i++) {
                *out++ = ' ';
            }
            *out = '\0';
            CHECK(parse_plain(text, &doc, &root, NULL) == OK);
            CHECK(msstd_json_len(doc, root) == 1);
            ((MsObj *)doc)->drop(doc);
        }

        /* A number of `pad` + 1 digits, with a fraction and an exponent of as many, at the end of the text. */
        out = text;
        memset(out, '7', pad + 1);
        out += pad + 1;
        *out = '\0';
        CHECK(parse_plain(text, &doc, &root, NULL) == OK);
        MsStr number = {0};
        msstd_json_text(doc, root, &number);
        CHECK(ms_str_len(&number) == pad + 1);
        msrt_string_free(&number);
        ((MsObj *)doc)->drop(doc);
        *out++ = '.';
        memset(out, '3', pad + 1);
        out += pad + 1;
        *out++ = 'e';
        *out++ = '-';
        memset(out, '1', pad + 1);
        out += pad + 1;
        *out = '\0';
        CHECK(parse_plain(text, &doc, &root, NULL) == OK);
        ((MsObj *)doc)->drop(doc);
        out[-1] = '.'; /* the exponent ends in a dot: not a number */
        CHECK(parse_plain(text, &doc, &root, NULL) == INVALID_DATA);
    }
}

int main(void) {
    test_recorded_cases();
    test_error_text();
    test_error_slot_is_always_valid();
    test_word_boundaries();
    test_document_accessors();
    test_scalars();
    test_writer();
    test_tree();
    printf("json_test ok (%d checks)\n", checks);
    return 0;
}
