/* runtime/std/http_h1_body.c: the incremental decoder of request bodies: fixed length, chunked coding with
 * trailers, or until close. Strict about line ends: every CR and LF of the chunk framing is part of a CRLF.
 */
#include "runtime/std/http_h1.h"

enum { SIZE_LINE_LIMIT = 4096, TRAILER_LINE_LIMIT = 8192, MAX_HEX_DIGITS = 16 };

MsH1Body ms_h1_body_new(MsH1Framing framing) {
  MsH1Body body = {.state = MS_H1_S_DONE};
  switch (framing.kind) {
  case MS_H1_NO_BODY:
    break;
  case MS_H1_LENGTH:
    body.state = framing.length == 0 ? MS_H1_S_DONE : MS_H1_S_LENGTH;
    body.left = framing.length;
    break;
  case MS_H1_CHUNKED:
    body.state = MS_H1_S_SIZE;
    break;
  case MS_H1_UNTIL_CLOSE:
    body.state = MS_H1_S_UNTIL_CLOSE;
    break;
  }
  return body;
}

void ms_h1_body_free(MsH1Body *body) {
  ms_bytes_free(&body->size_line);
}

bool ms_h1_body_is_done(const MsH1Body *body) {
  return body->state == MS_H1_S_DONE;
}

bool ms_h1_body_finish_on_eof(const MsH1Body *body) {
  return body->state == MS_H1_S_UNTIL_CLOSE || body->state == MS_H1_S_DONE;
}

/* Copies up to `left` bytes of input[at..] to out; returns the count taken. */
static size_t take_data(MsH1Body *body, MsSpan input, size_t at, MsBytes *out) {
  const uint64_t room = input.len - at;
  const size_t n = (size_t)(room < body->left ? room : body->left);
  if (n > 0) {
    uint8_t *dst = ms_list_extend(out, 1, n);
    __builtin_memcpy(dst, input.ptr + at, n);
  }
  body->left -= n;
  return n;
}

static bool hex_digit(uint8_t c, unsigned *value) {
  if (c >= '0' && c <= '9') {
    *value = (unsigned)(c - '0');
  } else if (c >= 'a' && c <= 'f') {
    *value = (unsigned)(c - 'a' + 10);
  } else if (c >= 'A' && c <= 'F') {
    *value = (unsigned)(c - 'A' + 10);
  } else {
    return false;
  }
  return true;
}

/* A collected size line (without its LF): `hex[;extension]` ending in CR. */
static const char *parse_size_line(MsH1Body *body) {
  MsSpan line = ms_bytes_span(&body->size_line);
  if (line.len == 0 || line.ptr[line.len - 1] != '\r') {
    return "chunk size line must end with CRLF";
  }
  line.len--;
  size_t end = 0;
  while (end < line.len && line.ptr[end] != ';') {
    end++;
  }
  size_t start = 0;
  while (start < end && (line.ptr[start] == ' ' || line.ptr[start] == '\t')) {
    start++;
  }
  while (end > start && (line.ptr[end - 1] == ' ' || line.ptr[end - 1] == '\t')) {
    end--;
  }
  uint64_t n = 0;
  if (end == start || end - start > MAX_HEX_DIGITS) {
    return "invalid chunk size";
  }
  for (size_t i = start; i < end; i++) {
    unsigned digit = 0;
    if (!hex_digit(line.ptr[i], &digit)) {
      return "invalid chunk size";
    }
    n = n << 4 | digit;
  }
  body->left = n;
  body->state = n == 0 ? MS_H1_S_TRAILER : MS_H1_S_DATA;
  body->trailer_line = 0;
  body->size_line.len = 0;
  return NULL;
}

/* The chunk size state: collects bytes up to LF, then parses the line. */
static const char *feed_size(MsH1Body *body, MsSpan input, size_t *at) {
  size_t lf = *at;
  while (lf < input.len && input.ptr[lf] != '\n') {
    lf++;
  }
  const size_t take = lf - *at;
  if (body->size_line.len + take > SIZE_LINE_LIMIT) {
    return "chunk size line too long";
  }
  if (take > 0) {
    __builtin_memcpy(ms_list_extend(&body->size_line, 1, take), input.ptr + *at, take);
  }
  if (lf == input.len) {
    *at = input.len;
    return NULL;
  }
  *at = lf + 1;
  return parse_size_line(body);
}

/* The CRLF after chunk data, possibly split across reads. */
static const char *feed_data_end(MsH1Body *body, MsSpan input, size_t *at) {
  while (*at < input.len) {
    const uint8_t c = input.ptr[(*at)++];
    if (c == '\r' && !body->cr) {
      body->cr = true;
    } else if (c == '\n' && body->cr) {
      body->cr = false;
      body->state = MS_H1_S_SIZE;
      return NULL;
    } else {
      return "malformed chunk terminator";
    }
  }
  return NULL;
}

/* Skips trailer lines up to the empty line. */
static const char *feed_trailer(MsH1Body *body, MsSpan input, size_t *at) {
  while (*at < input.len) {
    const uint8_t c = input.ptr[(*at)++];
    if (c == '\n') {
      if (!body->cr) {
        return "trailer line must end with CRLF";
      }
      body->cr = false;
      if (body->trailer_line == 0) {
        body->state = MS_H1_S_DONE;
        return NULL;
      }
      body->trailer_line = 0;
    } else if (body->cr) {
      return "bare CR in trailer";
    } else if (c == '\r') {
      body->cr = true;
    } else if (++body->trailer_line > TRAILER_LINE_LIMIT) {
      return "trailer too long";
    }
  }
  return NULL;
}

/* One step of the decoder; returns an error text or null. */
static const char *step(MsH1Body *body, MsSpan input, size_t *at, MsBytes *out) {
  switch (body->state) {
  case MS_H1_S_UNTIL_CLOSE:
    if (*at < input.len) {
      __builtin_memcpy(ms_list_extend(out, 1, input.len - *at), input.ptr + *at, input.len - *at);
    }
    *at = input.len;
    return NULL;
  case MS_H1_S_LENGTH:
    *at += take_data(body, input, *at, out);
    body->state = body->left == 0 ? MS_H1_S_DONE : MS_H1_S_LENGTH;
    return NULL;
  case MS_H1_S_SIZE:
    return feed_size(body, input, at);
  case MS_H1_S_DATA:
    *at += take_data(body, input, *at, out);
    body->state = body->left == 0 ? MS_H1_S_DATA_END : MS_H1_S_DATA;
    return NULL;
  case MS_H1_S_DATA_END:
    return feed_data_end(body, input, at);
  case MS_H1_S_TRAILER:
    return feed_trailer(body, input, at);
  case MS_H1_S_DONE:
    return NULL;
  }
  return NULL;
}

bool ms_h1_body_feed(MsH1Body *body, MsSpan input, MsBytes *out, size_t *used, MsH1Progress *progress,
                     const char **error) {
  size_t at = 0;
  *error = NULL;
  for (;;) {
    if (body->state == MS_H1_S_DONE) {
      break;
    }
    const MsH1BodyState before = body->state;
    *error = step(body, input, &at, out);
    if (*error != NULL) {
      return false;
    }
    /* Input is exhausted when a step neither moved nor changed the state. */
    if (at == input.len && body->state == before) {
      break;
    }
  }
  *used = at;
  *progress = body->state == MS_H1_S_DONE ? MS_H1_DONE : MS_H1_MORE;
  return true;
}
