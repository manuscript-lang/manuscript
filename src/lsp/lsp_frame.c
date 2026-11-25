/* lsp/lsp_frame.c: `Content-Length` framing and JSON text for `ms lsp`. */
#include <ctype.h>
#include <string.h>

#include "lsp/lsp_internal.h"

#include "base/chars.h"

enum { MAX_HEADER = 8192, MAX_BODY = 16 << 20 };

/* Reads one header line without its terminator into `line`; false at end of input with nothing read. */
static LspFrameStatus read_line(FILE *input, MsStrBuild *line, size_t *header_size, const char **error) {
  size_t read = 0;
  for (;;) {
    const int c = fgetc(input);
    if (c == EOF) {
      if (read == 0 && *header_size == 0) return LSP_FRAME_EOF;
      *error = "unexpected EOF";
      return LSP_FRAME_FAILED;
    }
    read++;
    (*header_size)++;
    if (*header_size > MAX_HEADER) {
      *error = "protocol header exceeds 8192 bytes";
      return LSP_FRAME_FAILED;
    }
    if (c == '\n') return LSP_FRAME_OK;
    ms_strbuild_append_byte(line, (uint8_t)c);
  }
}

static bool header_is_length(const uint8_t *key, size_t length) {
  static const char NAME[] = "content-length";
  if (length != sizeof NAME - 1) return false;
  for (size_t i = 0; i < length; i++) {
    if (tolower(key[i]) != NAME[i]) return false;
  }
  return true;
}

LspFrameStatus lsp_read_frame(FILE *input, MsStrBuild *body, const char **error) {
  bool have_length = false;
  size_t length = 0, header_size = 0;
  for (;;) {
    MsStrBuild line = ms_strbuild_new();
    const LspFrameStatus status = read_line(input, &line, &header_size, error);
    if (status != LSP_FRAME_OK) {
      ms_strbuild_free(&line);
      return status;
    }
    const MsSpan text = ms_span_trim(ms_strbuild_span(&line));
    if (text.len == 0) {
      ms_strbuild_free(&line);
      break;
    }
    const uint8_t *colon = memchr(text.ptr, ':', text.len);
    if (colon == NULL) {
      ms_strbuild_free(&line);
      *error = "malformed protocol header";
      return LSP_FRAME_FAILED;
    }
    const size_t key_len = (size_t)(colon - text.ptr);
    if (key_len == 14 && header_is_length(text.ptr, key_len)) {
      if (have_length) {
        ms_strbuild_free(&line);
        *error = "duplicate Content-Length";
        return LSP_FRAME_FAILED;
      }
      const MsSpan value = ms_span_trim(ms_span_of(colon + 1, text.len - key_len - 1));
      size_t number = 0;
      bool valid = value.len > 0 && value.len < 12;
      for (size_t i = 0; valid && i < value.len; i++) {
        if (value.ptr[i] < '0' || value.ptr[i] > '9') valid = false;
        else number = number * 10 + (size_t)(value.ptr[i] - '0');
      }
      if (!valid || number > MAX_BODY) {
        ms_strbuild_free(&line);
        *error = "invalid Content-Length";
        return LSP_FRAME_FAILED;
      }
      have_length = true;
      length = number;
    }
    ms_strbuild_free(&line);
  }
  if (!have_length) {
    *error = "invalid Content-Length";
    return LSP_FRAME_FAILED;
  }
  ms_strbuild_clear(body);
  for (size_t i = 0; i < length; i++) {
    const int c = fgetc(input);
    if (c == EOF) {
      *error = "unexpected EOF";
      return LSP_FRAME_FAILED;
    }
    ms_strbuild_append_byte(body, (uint8_t)c);
  }
  return LSP_FRAME_OK;
}

void lsp_write_frame(FILE *output, MsSpan body) {
  (void)fprintf(output, "Content-Length: %zu\r\n\r\n", body.len);
  (void)fwrite(body.ptr, 1, body.len, output);
  (void)fflush(output);
}

/* A range as the JSON object LSP carries. */
void lsp_json_range(MsStrBuild *out, LspRange range) {
  ms_strbuild_printf(out, "{\"start\":{\"line\":%zu,\"character\":%zu},\"end\":{\"line\":%zu,\"character\":%zu}}",
                     range.start.line, range.start.character, range.end.line, range.end.character);
}

void lsp_json_string(MsStrBuild *out, MsSpan text) {
  ms_strbuild_append_byte(out, '"');
  for (size_t i = 0; i < text.len; i++) {
    const uint8_t c = text.ptr[i];
    if (c == '"' || c == '\\') {
      ms_strbuild_append_byte(out, '\\');
      ms_strbuild_append_byte(out, c);
    } else if (c == '\n') {
      ms_strbuild_append_text(out, "\\n");
    } else if (c == '\r') {
      ms_strbuild_append_text(out, "\\r");
    } else if (c == '\t') {
      ms_strbuild_append_text(out, "\\t");
    } else if (c < 0x20) {
      ms_strbuild_printf(out, "\\u%04x", (unsigned)c);
    } else {
      ms_strbuild_append_byte(out, c);
    }
  }
  ms_strbuild_append_byte(out, '"');
}
