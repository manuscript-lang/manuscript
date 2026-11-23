/* runtime/std/http_h1_write.c: the writers of response heads and chunked bodies. */
#include "runtime/std/http_h1.h"
#include "runtime/std/time_internal.h"

typedef struct StatusName {
  uint16_t code;
  const char *text;
} StatusName;

static const StatusName STATUS_NAMES[] = {
    {100, "Continue"},
    {101, "Switching Protocols"},
    {102, "Processing"},
    {103, "Early Hints"},
    {200, "OK"},
    {201, "Created"},
    {202, "Accepted"},
    {203, "Non-Authoritative Information"},
    {204, "No Content"},
    {205, "Reset Content"},
    {206, "Partial Content"},
    {207, "Multi-Status"},
    {208, "Already Reported"},
    {226, "IM Used"},
    {300, "Multiple Choices"},
    {301, "Moved Permanently"},
    {302, "Found"},
    {303, "See Other"},
    {304, "Not Modified"},
    {305, "Use Proxy"},
    {307, "Temporary Redirect"},
    {308, "Permanent Redirect"},
    {400, "Bad Request"},
    {401, "Unauthorized"},
    {402, "Payment Required"},
    {403, "Forbidden"},
    {404, "Not Found"},
    {405, "Method Not Allowed"},
    {406, "Not Acceptable"},
    {407, "Proxy Authentication Required"},
    {408, "Request Timeout"},
    {409, "Conflict"},
    {410, "Gone"},
    {411, "Length Required"},
    {412, "Precondition Failed"},
    {413, "Request Entity Too Large"},
    {414, "Request URI Too Long"},
    {415, "Unsupported Media Type"},
    {416, "Requested Range Not Satisfiable"},
    {417, "Expectation Failed"},
    {418, "I'm a teapot"},
    {421, "Misdirected Request"},
    {422, "Unprocessable Entity"},
    {423, "Locked"},
    {424, "Failed Dependency"},
    {425, "Too Early"},
    {426, "Upgrade Required"},
    {428, "Precondition Required"},
    {429, "Too Many Requests"},
    {431, "Request Header Fields Too Large"},
    {451, "Unavailable For Legal Reasons"},
    {500, "Internal Server Error"},
    {501, "Not Implemented"},
    {502, "Bad Gateway"},
    {503, "Service Unavailable"},
    {504, "Gateway Timeout"},
    {505, "HTTP Version Not Supported"},
    {506, "Variant Also Negotiates"},
    {507, "Insufficient Storage"},
    {508, "Loop Detected"},
    {510, "Not Extended"},
    {511, "Network Authentication Required"},
};

const char *ms_h1_status_text(uint16_t code) {
  for (size_t i = 0; i < sizeof STATUS_NAMES / sizeof STATUS_NAMES[0]; i++) {
    if (STATUS_NAMES[i].code == code) {
      return STATUS_NAMES[i].text;
    }
  }
  return "";
}

void ms_h1_status_line(MsStrBuild *out, uint16_t status) {
  const char *text = ms_h1_status_text(status);
  ms_strbuild_append_text(out, "HTTP/1.1 ");
  ms_strbuild_append_u64(out, status);
  ms_strbuild_append_byte(out, ' ');
  if (text[0] == '\0') {
    ms_strbuild_append_text(out, "status code ");
    ms_strbuild_append_u64(out, status);
  } else {
    ms_strbuild_append_text(out, text);
  }
  ms_strbuild_append_text(out, "\r\n");
}

void ms_h1_header_line(MsStrBuild *out, MsSpan name, MsSpan value) {
  ms_strbuild_append(out, name);
  ms_strbuild_append_text(out, ": ");
  ms_strbuild_append(out, value);
  ms_strbuild_append_text(out, "\r\n");
}

void ms_h1_header_number(MsStrBuild *out, MsSpan name, uint64_t n) {
  ms_strbuild_append(out, name);
  ms_strbuild_append_text(out, ": ");
  ms_strbuild_append_u64(out, n);
  ms_strbuild_append_text(out, "\r\n");
}

void ms_h1_chunk(MsStrBuild *out, MsSpan data) {
  if (data.len == 0) {
    return;
  }
  ms_strbuild_append_u64_radix(out, data.len, 16);
  ms_strbuild_append_text(out, "\r\n");
  ms_strbuild_append(out, data);
  ms_strbuild_append_text(out, "\r\n");
}

static void append_two_digits(MsStrBuild *out, int64_t value) {
  ms_strbuild_append_byte(out, (uint8_t)('0' + value / 10 % 10));
  ms_strbuild_append_byte(out, (uint8_t)('0' + value % 10));
}

static void format_http_date(MsStrBuild *out, int64_t unix_seconds) {
  static const char *const DAYS[] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
  static const char *const MONTHS[] = {"Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                       "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
  const MsCivil civil = ms_civil_of(unix_seconds, 0);
  ms_strbuild_append_text(out, DAYS[civil.weekday]);
  ms_strbuild_append_text(out, ", ");
  append_two_digits(out, civil.day);
  ms_strbuild_append_byte(out, ' ');
  ms_strbuild_append_text(out, MONTHS[civil.month - 1]);
  ms_strbuild_append_byte(out, ' ');
  ms_strbuild_append_i64(out, civil.year);
  ms_strbuild_append_byte(out, ' ');
  append_two_digits(out, civil.hour);
  ms_strbuild_append_byte(out, ':');
  append_two_digits(out, civil.minute);
  ms_strbuild_append_byte(out, ':');
  append_two_digits(out, civil.second);
  ms_strbuild_append_text(out, " GMT");
}

/* Every response carries the date, and it changes once a second: the last text a thread formatted answers the
 * requests of the same second. */
void ms_h1_http_date(MsStrBuild *out, int64_t unix_seconds) {
  enum { DATE_MAX = 48 };
  static _Thread_local int64_t cached_seconds = -1;
  static _Thread_local size_t cached_length;
  static _Thread_local char cached_text[DATE_MAX];
  if (cached_seconds != unix_seconds) {
    MsStrBuild text = ms_strbuild_new();
    format_http_date(&text, unix_seconds);
    const MsSpan span = ms_strbuild_span(&text);
    cached_length = span.len < DATE_MAX ? span.len : 0;
    if (cached_length != 0) {
      __builtin_memcpy(cached_text, span.ptr, cached_length);
      cached_seconds = unix_seconds;
    }
    ms_strbuild_append(out, span);
    ms_strbuild_free(&text);
    return;
  }
  ms_strbuild_append(out, ms_span_of((const uint8_t *)cached_text, cached_length));
}
