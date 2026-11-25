/* runtime/std/tls_pem.c: the CERTIFICATE blocks of a PEM text. */
#include "runtime/std/tls.h"

#include "base/chars.h"
#include "base/strbuild.h"
#include "runtime/std/encoding.h"

static const char begin_line[] = "-----BEGIN CERTIFICATE-----";
static const char end_line[] = "-----END CERTIFICATE-----";

/* The next line (without its newline) and the text after it; false at the end of the text. */
static bool next_line(MsSpan *text, MsSpan *line) {
  if (text->len == 0) {
    return false;
  }
  size_t at = 0;
  while (at < text->len && text->ptr[at] != '\n') {
    at++;
  }
  *line = ms_span_of(text->ptr, at);
  const size_t skip = at < text->len ? at + 1 : at;
  *text = ms_span_of(text->ptr + skip, text->len - skip);
  return true;
}

static bool has_colon(MsSpan line) {
  for (size_t i = 0; i < line.len; i++) {
    if (line.ptr[i] == ':') {
      return true;
    }
  }
  return false;
}

/* One block at the start of `*text`: its DER bytes; false when it is not a plain CERTIFICATE block. */
static bool block(MsSpan *text, MsBytes *der) {
  MsSpan line;
  if (!next_line(text, &line) || !ms_span_is_text(ms_span_trim(line), begin_line)) {
    return false;
  }
  MsStrBuild body = ms_strbuild_new();
  bool closed = false;
  while (next_line(text, &line)) {
    const MsSpan item = ms_span_trim(line);
    if (ms_span_is_text(item, end_line)) {
      closed = true;
      break;
    }
    if (has_colon(item)) {
      break; /* a header: not a plain certificate block */
    }
    for (size_t i = 0; i < item.len; i++) {
      if (!ms_ascii_is_space(item.ptr[i])) {
        ms_strbuild_append_byte(&body, item.ptr[i]);
      }
    }
  }
  bool ok = false;
  if (closed) {
    const MsString encoded = ms_strbuild_finish(&body);
    body = ms_strbuild_new();
    ok = msstd_encoding_base64_decode(&encoded, 0, 0, 0, der) == MS_STATUS_OK && der->len > 0;
    MsString release = encoded;
    ms_string_release(&release);
  }
  ms_strbuild_free(&body);
  return ok;
}

uint8_t ms_tls_pem_certificates(MsSpan text, int64_t max, MsList *ders) {
  *ders = (MsList){0};
  MsSpan rest = ms_span_trim(text);
  while (rest.len > 0) {
    MsBytes der = {0};
    if (!block(&rest, &der)) {
      ms_bytes_free(&der);
      ms_bytes_list_free(ders);
      return MS_STATUS_INVALID_DATA;
    }
    if (max >= 0 && ders->len >= (uint64_t)max) {
      ms_bytes_free(&der);
      ms_bytes_list_free(ders);
      return MS_STATUS_LIMIT_EXCEEDED;
    }
    ms_list_push(ders, sizeof der, &der);
    rest = ms_span_trim(rest);
  }
  return MS_STATUS_OK;
}
