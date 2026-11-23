/* runtime/std/http_sniff.c: http.DetectContentType over the first 512 bytes of a body. Signatures are tried
 * in the order of the Go table; a mask byte of 0xff compares the byte, 0x00 ignores it. */
#include "runtime/std/http_wire.h"

enum { SNIFF_LIMIT = 512 };

static bool is_space(uint8_t b) {
  return b == '\t' || b == '\n' || b == '\f' || b == '\r' || b == ' ';
}

static MsSpan skip_space(MsSpan data) {
  size_t n = 0;
  while (n < data.len && is_space(data.ptr[n])) {
    n++;
  }
  return ms_span_of(data.ptr + n, data.len - n);
}

static bool html_tag(MsSpan data, const char *tag) {
  const MsSpan t = ms_span_of_text(tag);
  data = skip_space(data);
  if (data.len <= t.len) {
    return false;
  }
  for (size_t i = 0; i < t.len; i++) {
    const uint8_t c = data.ptr[i];
    if ((uint8_t)(c >= 'a' && c <= 'z' ? c - 32 : c) != t.ptr[i]) {
      return false;
    }
  }
  return data.ptr[t.len] == ' ' || data.ptr[t.len] == '>';
}

/* A signature of `n` bytes; a mask of null means the whole pattern must match. */
static bool masked(MsSpan data, const char *pattern, const char *mask, size_t n, bool skip) {
  if (skip) {
    data = skip_space(data);
  }
  if (data.len < n) {
    return false;
  }
  for (size_t i = 0; i < n; i++) {
    const uint8_t m = mask == NULL ? 0xff : (uint8_t)mask[i];
    if ((data.ptr[i] & m) != (uint8_t)pattern[i]) {
      return false;
    }
  }
  return true;
}

static bool exact(MsSpan data, const char *sig, size_t n) {
  return masked(data, sig, NULL, n, false);
}

static bool is_mp4(MsSpan data) {
  if (data.len < 12) {
    return false;
  }
  const size_t size =
      (size_t)data.ptr[0] << 24 | (size_t)data.ptr[1] << 16 | (size_t)data.ptr[2] << 8 | data.ptr[3];
  if (data.len < size || size % 4 != 0 || !exact(ms_span_of(data.ptr + 4, data.len - 4), "ftyp", 4)) {
    return false;
  }
  for (size_t at = 8; at < size; at += 4) {
    if (at == 12) {
      continue;
    }
    if (at + 3 > data.len) {
      break;
    }
    if (exact(ms_span_of(data.ptr + at, data.len - at), "mp4", 3)) {
      return true;
    }
  }
  return false;
}

/* Bit b is set for each control byte b that text does not hold. */
static bool is_text(MsSpan data) {
  for (size_t i = 0; i < data.len; i++) {
    const uint8_t b = data.ptr[i];
    if (b < 0x20 && ((0xf7ffc9ffu >> b) & 1u) != 0) {
      return false;
    }
  }
  return true;
}

static const char *const HTML_TAGS[] = {
    "<!DOCTYPE HTML", "<HTML",  "<HEAD", "<SCRIPT", "<IFRAME", "<H1", "<DIV", "<FONT", "<TABLE", "<A",
    "<STYLE",         "<TITLE", "<B",    "<BODY",   "<BR",     "<P",  "<!--"};

typedef struct Signature {
  const char *pattern;
  const char *mask; /* null: exact */
  size_t length;
  const char *type;
} Signature;

/* The signatures after the text ones, in order. RIFF and FORM leave the size bytes (4 to 7) unmasked. */
#define RIFF_MASK "\xff\xff\xff\xff\x00\x00\x00\x00\xff\xff\xff\xff"
static const Signature SIGNATURES[] = {
    {"GIF87a", NULL, 6, "image/gif"},
    {"GIF89a", NULL, 6, "image/gif"},
    {"\x89PNG\x0d\x0a\x1a\x0a", NULL, 8, "image/png"},
    {"\xff\xd8\xff", NULL, 3, "image/jpeg"},
    {"BM", NULL, 2, "image/bmp"},
    {"RIFF\0\0\0\0WEBPVP", "\xff\xff\xff\xff\x00\x00\x00\x00\xff\xff\xff\xff\xff\xff", 14, "image/webp"},
    {"\0\0\x01\0", NULL, 4, "image/x-icon"},
    {"\0\0\x02\0", NULL, 4, "image/x-icon"},
    {"FORM\0\0\0\0AIFF", RIFF_MASK, 12, "audio/aiff"},
    {"ID3", NULL, 3, "audio/mpeg"},
    {"OggS\0", NULL, 5, "application/ogg"},
    {"MThd\0\0\0\x06", NULL, 8, "audio/midi"},
    {"RIFF\0\0\0\0AVI ", RIFF_MASK, 12, "video/avi"},
    {"RIFF\0\0\0\0WAVE", RIFF_MASK, 12, "audio/wave"},
};

static const Signature AFTER_MP4[] = {
    {"\x1a\x45\xdf\xa3", NULL, 4, "video/webm"},
    {"\0\1\0\0", NULL, 4, "font/ttf"},
    {"OTTO", NULL, 4, "font/otf"},
    {"ttcf", NULL, 4, "font/collection"},
    {"wOFF", NULL, 4, "font/woff"},
    {"wOF2", NULL, 4, "font/woff2"},
    {"\x1f\x8b\x08", NULL, 3, "application/x-gzip"},
    {"PK\x03\x04", NULL, 4, "application/zip"},
    {"Rar!\x1a\x07\0", NULL, 7, "application/x-rar-compressed"},
    {"Rar!\x1a\x07\x01\0", NULL, 8, "application/x-rar-compressed"},
    {"\0asm", NULL, 4, "application/wasm"},
};

static const char *find_signature(MsSpan data, const Signature *table, size_t count) {
  if (data.len == 0) {
    return NULL;
  }
  for (size_t i = 0; i < count; i++) {
    const uint8_t first_mask = table[i].mask == NULL ? 0xff : (uint8_t)table[i].mask[0];
    if ((data.ptr[0] & first_mask) != (uint8_t)table[i].pattern[0]) {
      continue; /* most signatures differ in the first byte */
    }
    if (masked(data, table[i].pattern, table[i].mask, table[i].length, false)) {
      return table[i].type;
    }
  }
  return NULL;
}

static bool is_embedded_font(MsSpan data) {
  /* 34 zero bytes (the EOT header fields), then "LP". */
  if (data.len < 36) {
    return false;
  }
  for (size_t i = 0; i < 34; i++) {
    if (data.ptr[i] != 0) {
      return false;
    }
  }
  return data.ptr[34] == 'L' && data.ptr[35] == 'P';
}

static const char *early_type(MsSpan data) {
  const MsSpan body = skip_space(data);
  if (body.len > 0 && body.ptr[0] == '<') { /* every tag and the XML prolog start with it */
    for (size_t i = 0; i < sizeof HTML_TAGS / sizeof HTML_TAGS[0]; i++) {
      if (html_tag(body, HTML_TAGS[i])) {
        return "text/html; charset=utf-8";
      }
    }
    if (masked(body, "<?xml", "\xff\xff\xff\xff\xff", 5, false)) {
      return "text/xml; charset=utf-8";
    }
  }
  if (exact(data, "%PDF-", 5)) {
    return "application/pdf";
  }
  if (exact(data, "%!PS-Adobe-", 11)) {
    return "application/postscript";
  }
  if (masked(data, "\xfe\xff\0\0", "\xff\xff\0\0", 4, false)) {
    return "text/plain; charset=utf-16be";
  }
  if (masked(data, "\xff\xfe\0\0", "\xff\xff\0\0", 4, false)) {
    return "text/plain; charset=utf-16le";
  }
  if (masked(data, "\xef\xbb\xbf\0", "\xff\xff\xff\0", 4, false)) {
    return "text/plain; charset=utf-8";
  }
  return NULL;
}

/* Whether any signature, tag or box can match data that starts with `first`. The tables above are tried one by one, so
 * a body of plain text or JSON (the usual answer) would otherwise run them all. This lists the first byte of every
 * entry: the HTML tags and the XML prolog (`<` after white space), "%PDF-" and "%!PS-Adobe-", the byte order marks
 * (0xfe, 0xff, 0xef), and the first bytes of SIGNATURES and AFTER_MP4. An MP4 box and an embedded font start with
 * any byte (the size) or a zero, and are checked apart. */
static bool may_match(uint8_t first) {
  switch (first) {
    case '\t': case '\n': case '\f': case '\r': case ' ': case '<': case '%': case 0xfe: case 0xff: case 0xef:
    case 'G': case 0x89: case 'B': case 'R': case 0x00: case 'F': case 'I': case 'O': case 'M': case 0x1a:
    case 0x1f: case 'P': case 't': case 'w':
      return true;
    default:
      return false;
  }
}

const char *ms_http_detect_content_type(MsSpan data) {
  if (data.len > SNIFF_LIMIT) {
    data.len = SNIFF_LIMIT;
  }
  if (data.len > 0 && !may_match(data.ptr[0]) && !is_mp4(data)) {
    return is_text(data) ? "text/plain; charset=utf-8" : "application/octet-stream";
  }
  const char *type = early_type(data);
  if (type == NULL) {
    type = find_signature(data, SIGNATURES, sizeof SIGNATURES / sizeof SIGNATURES[0]);
  }
  if (type == NULL && is_mp4(data)) {
    type = "video/mp4";
  }
  if (type == NULL && is_embedded_font(data)) {
    type = "application/vnd.ms-fontobject";
  }
  if (type == NULL) {
    type = find_signature(data, AFTER_MP4, sizeof AFTER_MP4 / sizeof AFTER_MP4[0]);
  }
  if (type != NULL) {
    return type;
  }
  return is_text(data) ? "text/plain; charset=utf-8" : "application/octet-stream";
}
