/* Builds src/runtime/std/tzdata.bin, the zone database @std/time embeds on every platform.
 *
 *   zic -b fat -d zones tzdata.zi        (zic 2.39's slim output stops Gaza's Ramadan rules in 2072)
 *   cc -O1 -o pack tools/tzdata/pack.c && ./pack zones tzdata.zi windowsZones.xml src/runtime/std/tzdata.bin
 *
 * tzdata.zi is the IANA source (`/usr/share/zoneinfo/tzdata.zi`, or a release's); windowsZones.xml is CLDR's
 * common/supplemental/windowsZones.xml (Windows zone key to IANA name). The data keeps only the TZif version
 * 2+ block of each zone. Format, all integers big endian: "MSTZ", u32 version text length and the text, u32
 * entry count, then the entries sorted by name (u8 name length, name, u32 offset from the start of the file,
 * u32 length), then the data. Names are IANA zone names and `windows/<Windows key>`, whose data is the IANA
 * name. Equal data is stored once. */
#define _XOPEN_SOURCE 700
#include <ftw.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  char name[200];
  uint8_t *data;
  size_t size;
  size_t offset;
} Entry;

static Entry *entries;
static size_t count;
static const char *root;

static uint32_t be32(const uint8_t *p) {
  return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3];
}

static void put32(FILE *out, uint32_t v) {
  const uint8_t b[4] = {(uint8_t)(v >> 24), (uint8_t)(v >> 16), (uint8_t)(v >> 8), (uint8_t)v};
  fwrite(b, 1, 4, out);
}

static void add(const char *name, uint8_t *data, size_t size) {
  entries = realloc(entries, (count + 1) * sizeof *entries);
  Entry *e = &entries[count++];
  snprintf(e->name, sizeof e->name, "%s", name);
  e->data = data;
  e->size = size;
  e->offset = 0;
}

static uint8_t *read_file(const char *path, size_t *size) {
  FILE *in = fopen(path, "rb");
  if (!in) {
    perror(path);
    exit(1);
  }
  fseek(in, 0, SEEK_END);
  *size = (size_t)ftell(in);
  fseek(in, 0, SEEK_SET);
  uint8_t *data = malloc(*size + 1);
  if (fread(data, 1, *size, in) != *size) {
    exit(1);
  }
  fclose(in);
  data[*size] = 0;
  return data;
}

static int visit(const char *path, const struct stat *st, int flag, struct FTW *ftw) {
  (void)st;
  (void)ftw;
  if (flag != FTW_F) {
    return 0;
  }
  size_t size;
  uint8_t *data = read_file(path, &size);
  if (size < 44 || memcmp(data, "TZif", 4) != 0 || data[4] < '2') {
    return 0; /* posixrules, leapseconds and the like */
  }
  const uint32_t isut = be32(data + 20), isstd = be32(data + 24), leap = be32(data + 28),
                 times = be32(data + 32), types = be32(data + 36), chars = be32(data + 40);
  const size_t skip = 44 + times * 5ul + types * 6ul + chars + leap * 8ul + isstd + isut;
  add(path + strlen(root) + 1, data + skip, size - skip);
  return 0;
}

static int by_name(const void *a, const void *b) {
  return strcmp(((const Entry *)a)->name, ((const Entry *)b)->name);
}

/* The value of `key="..."` in the tag at `tag`, up to its `>`. */
static int attribute(const char *tag, const char *key, char *out, size_t cap) {
  char pattern[32];
  snprintf(pattern, sizeof pattern, " %s=\"", key);
  const char *end = strchr(tag, '>');
  const char *at = strstr(tag, pattern);
  if (!at || at > end) {
    return 0;
  }
  at += strlen(pattern);
  const char *stop = strchr(at, '"');
  snprintf(out, cap, "%.*s", (int)(stop - at), at);
  return 1;
}

static void add_windows(const char *xml_path) {
  size_t size;
  char *xml = (char *)read_file(xml_path, &size);
  for (const char *tag = strstr(xml, "<mapZone "); tag; tag = strstr(tag + 1, "<mapZone ")) {
    char territory[16], other[160], type[200], name[200];
    if (!attribute(tag, "territory", territory, sizeof territory) || strcmp(territory, "001") != 0 ||
        !attribute(tag, "other", other, sizeof other) || !attribute(tag, "type", type, sizeof type)) {
      continue;
    }
    type[strcspn(type, " ")] = 0;
    snprintf(name, sizeof name, "windows/%s", other);
    add(name, (uint8_t *)strdup(type), strlen(type));
  }
}

int main(int argc, char **argv) {
  if (argc != 5) {
    fprintf(stderr, "usage: pack <zic output dir> <tzdata.zi> <windowsZones.xml> <output>\n");
    return 2;
  }
  root = argv[1];
  size_t zi_size;
  const char *zi = (const char *)read_file(argv[2], &zi_size);
  const char *tag = strstr(zi, "# version ");
  char version[32] = "";
  if (tag) {
    sscanf(tag + 10, "%31s", version);
  }
  nftw(root, visit, 16, FTW_PHYS);
  add_windows(argv[3]);
  qsort(entries, count, sizeof *entries, by_name);

  size_t at = 4 + 4 + strlen(version) + 4;
  for (size_t i = 0; i < count; i++) {
    at += 1 + strlen(entries[i].name) + 8;
  }
  for (size_t i = 0; i < count; i++) { /* equal data is stored once */
    entries[i].offset = 0;
    for (size_t j = 0; j < i && !entries[i].offset; j++) {
      if (entries[j].size == entries[i].size &&
          memcmp(entries[j].data, entries[i].data, entries[i].size) == 0) {
        entries[i].offset = entries[j].offset;
      }
    }
    if (!entries[i].offset) {
      entries[i].offset = at;
      at += entries[i].size;
    }
  }
  FILE *out = fopen(argv[4], "wb");
  fwrite("MSTZ", 1, 4, out);
  put32(out, (uint32_t)strlen(version));
  fwrite(version, 1, strlen(version), out);
  put32(out, (uint32_t)count);
  for (size_t i = 0; i < count; i++) {
    fputc((int)strlen(entries[i].name), out);
    fwrite(entries[i].name, 1, strlen(entries[i].name), out);
    put32(out, (uint32_t)entries[i].offset);
    put32(out, (uint32_t)entries[i].size);
  }
  /* the data, each blob where its first entry put it */
  for (size_t i = 0; i < count; i++) {
    int first = 1;
    for (size_t j = 0; j < i; j++) {
      first &= entries[j].offset != entries[i].offset;
    }
    if (first) {
      fwrite(entries[i].data, 1, entries[i].size, out);
    }
  }
  fclose(out);
  printf("%zu names, %zu bytes, version %s\n", count, at, version);
  return 0;
}
