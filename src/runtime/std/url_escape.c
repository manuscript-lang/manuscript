/* Percent escaping and unescaping by the rules of Go's net/url (shouldEscape, escape, unescape). */
#include "base/chars.h"
#include "runtime/std/url_internal.h"

static const char UPPER_HEX[] = "0123456789ABCDEF";

static bool is_alnum(uint8_t c) {
  return ms_ascii_is_alnum(c);
}

static bool is_host_safe(uint8_t c) {
  static const char SAFE[] = "!$&'()*+,;=:[]<>\"";
  for (size_t i = 0; SAFE[i] != 0; i++) {
    if ((uint8_t)SAFE[i] == c) {
      return true;
    }
  }
  return false;
}

/* The mode's verdict for one of `$&+,/:;=?@`. */
static bool reserved_escapes(uint8_t c, UrlEnc mode) {
  switch (mode) {
  case URL_ENC_PATH:
    return c == '?';
  case URL_ENC_PATH_SEGMENT:
    return c == '/' || c == ';' || c == ',' || c == '?';
  case URL_ENC_USER_PASSWORD:
    return c == '@' || c == '/' || c == '?' || c == ':';
  case URL_ENC_QUERY_COMPONENT:
    return true;
  case URL_ENC_FRAGMENT:
    return false;
  default:
    return true;
  }
}

static bool url_should_escape(uint8_t c, UrlEnc mode) {
  if (is_alnum(c)) {
    return false;
  }
  if ((mode == URL_ENC_HOST || mode == URL_ENC_ZONE) && is_host_safe(c)) {
    return false;
  }
  if (c == '-' || c == '_' || c == '.' || c == '~') {
    return false;
  }
  if (c == '$' || c == '&' || c == '+' || c == ',' || c == '/' || c == ':' || c == ';' || c == '=' ||
      c == '?' || c == '@') {
    if (mode != URL_ENC_HOST && mode != URL_ENC_ZONE) {
      return reserved_escapes(c, mode);
    }
  }
  if (mode == URL_ENC_FRAGMENT && (c == '!' || c == '(' || c == ')' || c == '*')) {
    return false;
  }
  return true;
}

bool url_find_last(MsSpan text, uint8_t byte, size_t *at) {
  for (size_t i = text.len; i > 0; i--) {
    if (text.ptr[i - 1] == byte) {
      *at = i - 1;
      return true;
    }
  }
  return false;
}

bool url_is_canonical(MsSpan text, UrlEnc mode) {
  for (size_t i = 0; i < text.len; i++) {
    if (text.ptr[i] == '%' || url_should_escape(text.ptr[i], mode)) {
      return false;
    }
  }
  return true;
}

bool url_valid_encoded(MsSpan text, UrlEnc mode) {
  static const char ALLOWED[] = "!$&'()*+,;=:@[]%";
  for (size_t i = 0; i < text.len; i++) {
    const uint8_t c = text.ptr[i];
    bool allowed = false;
    for (size_t k = 0; ALLOWED[k] != 0; k++) {
      allowed = allowed || (uint8_t)ALLOWED[k] == c;
    }
    if (!allowed && url_should_escape(c, mode)) {
      return false;
    }
  }
  return true;
}

bool url_valid_optional_port(MsSpan port) {
  if (port.len == 0) {
    return true;
  }
  if (port.ptr[0] != ':') {
    return false;
  }
  for (size_t i = 1; i < port.len; i++) {
    if (port.ptr[i] < '0' || port.ptr[i] > '9') {
      return false;
    }
  }
  return true;
}

void url_escape(MsSpan text, UrlEnc mode, MsStrBuild *out) {
  for (size_t i = 0; i < text.len; i++) {
    const uint8_t c = text.ptr[i];
    if (c == ' ' && mode == URL_ENC_QUERY_COMPONENT) {
      ms_strbuild_append_byte(out, '+');
    } else if (url_should_escape(c, mode)) {
      ms_strbuild_append_byte(out, '%');
      ms_strbuild_append_byte(out, (uint8_t)UPPER_HEX[c >> 4]);
      ms_strbuild_append_byte(out, (uint8_t)UPPER_HEX[c & 15]);
    } else {
      ms_strbuild_append_byte(out, c);
    }
  }
}

/* Whether the escape at text[i..i+3] is allowed in `mode` (it is well formed). */
static bool escape_allowed(MsSpan text, size_t i, UrlEnc mode) {
  const int high = ms_hex_value(text.ptr[i + 1]);
  const bool is_percent25 = text.ptr[i + 1] == '2' && text.ptr[i + 2] == '5';
  if (mode == URL_ENC_HOST && high < 8 && !is_percent25) {
    return false;
  }
  if (mode == URL_ENC_ZONE) {
    const uint8_t value = (uint8_t)(high * 16 + ms_hex_value(text.ptr[i + 2]));
    if (!is_percent25 && value != ' ' && url_should_escape(value, URL_ENC_HOST)) {
      return false;
    }
  }
  return true;
}

/* Validates `text` for unescaping and reports whether a `%` or a query `+` needs rewriting. */
static bool validate(MsSpan text, UrlEnc mode, bool *rewrite) {
  bool has_percent = false;
  bool has_plus = false;
  for (size_t i = 0; i < text.len;) {
    const uint8_t c = text.ptr[i];
    if (c == '%') {
      has_percent = true;
      if (i + 2 >= text.len || ms_hex_value(text.ptr[i + 1]) < 0 || ms_hex_value(text.ptr[i + 2]) < 0 ||
          !escape_allowed(text, i, mode)) {
        return false;
      }
      i += 3;
      continue;
    }
    if (c == '+') {
      has_plus = mode == URL_ENC_QUERY_COMPONENT;
    } else if ((mode == URL_ENC_HOST || mode == URL_ENC_ZONE) && c < 0x80 && url_should_escape(c, mode)) {
      return false;
    }
    i++;
  }
  *rewrite = has_percent || has_plus;
  return true;
}

bool url_unescape(MsSpan text, UrlEnc mode, MsStrBuild *out) {
  bool rewrite = false;
  if (!validate(text, mode, &rewrite)) {
    return false;
  }
  if (!rewrite) {
    url_append(out, text);
    return true;
  }
  for (size_t i = 0; i < text.len; i++) {
    const uint8_t c = text.ptr[i];
    if (c == '%') {
      ms_strbuild_append_byte(out, (uint8_t)(ms_hex_value(text.ptr[i + 1]) * 16 + ms_hex_value(text.ptr[i + 2])));
      i += 2;
    } else if (c == '+' && mode == URL_ENC_QUERY_COMPONENT) {
      ms_strbuild_append_byte(out, ' ');
    } else {
      ms_strbuild_append_byte(out, c);
    }
  }
  return true;
}
