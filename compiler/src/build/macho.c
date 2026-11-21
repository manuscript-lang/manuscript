/* The global symbols of Mach-O objects and archives (ms/build_macho.h). */
#include "ms/build_macho.h"

#include <string.h>

#define MACHO_MAGIC_64 0xfeedfacfu

enum {
    MACHO_LC_SEGMENT_64 = 0x19,
    MACHO_LC_SYMTAB = 0x2,
    MACHO_N_EXT = 0x01,
    MACHO_N_PEXT = 0x10,
    MACHO_N_STAB = 0xe0,
    MACHO_N_TYPE = 0x0e,
    MACHO_HEADER_SIZE = 32,
    MACHO_SEGMENT_SIZE = 72,
    MACHO_SECTION_SIZE = 80,
    MACHO_NLIST_SIZE = 16,
    AR_HEADER_SIZE = 60,
};

static uint32_t macho_u32(const char *p) {
    uint32_t v;
    memcpy(&v, p, sizeof v);
    return v; /* the hosts that link are little-endian, as the objects are */
}

static uint64_t macho_u64(const char *p) {
    uint64_t v;
    memcpy(&v, p, sizeof v);
    return v;
}

/* Whether `[at, at + size)` lies inside `len` bytes. */
static bool macho_within(size_t len, uint64_t at, uint64_t size) { return at <= len && size <= len - at; }

/* The symbols of one Mach-O object. */
static void macho_object(const char *data, size_t len, MsMachoSymbols *out) {
    if (len < MACHO_HEADER_SIZE || macho_u32(data) != MACHO_MAGIC_64) {
        return;
    }
    const uint32_t ncmds = macho_u32(data + 16);
    size_t at = MACHO_HEADER_SIZE;
    for (uint32_t c = 0; c < ncmds && macho_within(len, at, 8); c++) {
        const uint32_t cmd = macho_u32(data + at), size = macho_u32(data + at + 4);
        if (size < 8 || !macho_within(len, at, size)) {
            return;
        }
        if (cmd == MACHO_LC_SEGMENT_64 && size >= MACHO_SEGMENT_SIZE) {
            const uint32_t nsects = macho_u32(data + at + 64);
            for (uint32_t s = 0; s < nsects && MACHO_SEGMENT_SIZE + (size_t)(s + 1) * MACHO_SECTION_SIZE <= size; s++) {
                const char *section = data + at + MACHO_SEGMENT_SIZE + (size_t)s * MACHO_SECTION_SIZE;
                out->debug = out->debug || strncmp(section, "__debug_info", 16) == 0;
            }
        } else if (cmd == MACHO_LC_SYMTAB && size >= 24) {
            const uint32_t symoff = macho_u32(data + at + 8), nsyms = macho_u32(data + at + 12);
            const uint32_t stroff = macho_u32(data + at + 16), strsize = macho_u32(data + at + 20);
            if (!macho_within(len, symoff, (uint64_t)nsyms * MACHO_NLIST_SIZE) || !macho_within(len, stroff, strsize)) {
                return;
            }
            for (uint32_t i = 0; i < nsyms; i++) {
                const char *entry = data + symoff + (size_t)i * MACHO_NLIST_SIZE;
                const uint32_t name = macho_u32(entry);
                const uint8_t type = (uint8_t)entry[4];
                if ((type & MACHO_N_STAB) != 0 || (type & (MACHO_N_EXT | MACHO_N_PEXT)) != MACHO_N_EXT || name >= strsize) {
                    continue; /* a debugging entry, or a local symbol */
                }
                const char *text = data + stroff + name;
                const char *end = memchr(text, 0, strsize - name);
                const size_t n = end != NULL ? (size_t)(end - text) : (size_t)(strsize - name);
                if (n == 0) {
                    continue;
                }
                const MsStr symbol = {text, (uint32_t)n};
                MsBuf *list = (type & MACHO_N_TYPE) == 0 && macho_u64(entry + 8) == 0 ? &out->undefined : &out->defined;
                MS_VEC_PUSH(*list, MsStr, symbol);
            }
        }
        at += size;
    }
}

/* The decimal number in the first `n` bytes of `field`, up to its padding spaces. */
static size_t macho_decimal(const char *field, size_t n) {
    size_t value = 0;
    for (size_t i = 0; i < n && field[i] >= '0' && field[i] <= '9'; i++) {
        value = value * 10 + (size_t)(field[i] - '0');
    }
    return value;
}

void ms_macho_collect(const char *data, size_t len, MsMachoSymbols *out) {
    static const char magic[] = "!<arch>\n";
    if (len < sizeof magic - 1 || memcmp(data, magic, sizeof magic - 1) != 0) {
        macho_object(data, len, out);
        return;
    }
    size_t at = sizeof magic - 1;
    while (macho_within(len, at, AR_HEADER_SIZE)) {
        const char *header = data + at;
        size_t size = macho_decimal(header + 48, 10);
        const size_t body = at + AR_HEADER_SIZE;
        if (!macho_within(len, body, size)) {
            return;
        }
        size_t skip = 0; /* BSD archives put a long member name at the start of its data: `#1/N` */
        if (strncmp(header, "#1/", 3) == 0) {
            skip = macho_decimal(header + 3, 13);
        }
        if (skip <= size) {
            macho_object(data + body + skip, size - skip, out);
        }
        at = body + size + (size & 1);
    }
}

void ms_macho_free(MsMachoSymbols *symbols) {
    ms_buf_free(&symbols->defined);
    ms_buf_free(&symbols->undefined);
}
