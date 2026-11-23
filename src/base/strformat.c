/* Owns ms_strbuild_printf, the small formatter for IR and diagnostics text (see strbuild.h). */
#include <stdarg.h>

#include "base/strbuild.h"

typedef enum Length { LENGTH_INT, LENGTH_SIZE, LENGTH_LONG_LONG } Length;

static void append_signed(MsStrBuild *builder, va_list *args, Length length) {
  switch (length) {
  case LENGTH_LONG_LONG:
    ms_strbuild_append_i64(builder, va_arg(*args, long long));
    return;
  case LENGTH_SIZE:
  case LENGTH_INT:
    ms_strbuild_append_i64(builder, va_arg(*args, int));
    return;
  }
}

static void append_unsigned(MsStrBuild *builder, va_list *args, Length length) {
  switch (length) {
  case LENGTH_LONG_LONG:
    ms_strbuild_append_u64(builder, va_arg(*args, unsigned long long));
    return;
  case LENGTH_SIZE:
    ms_strbuild_append_u64(builder, va_arg(*args, size_t));
    return;
  case LENGTH_INT:
    ms_strbuild_append_u64(builder, va_arg(*args, unsigned));
    return;
  }
}

static void append_counted(MsStrBuild *builder, va_list *args) {
  int length = va_arg(*args, int);
  const char *text = va_arg(*args, const char *);
  if (length > 0) {
    ms_strbuild_append(builder, ms_span_of((const uint8_t *)text, (size_t)length));
  }
}

/* Formats the verb at `format` (just past the `%`); returns the characters it used. */
static size_t append_verb(MsStrBuild *builder, const char *format, va_list *args) {
  size_t used = 0;
  Length length = LENGTH_INT;
  if (format[0] == '.' && format[1] == '*' && format[2] == 's') {
    append_counted(builder, args);
    return 3;
  }
  if (format[0] == 'z') {
    length = LENGTH_SIZE;
    used = 1;
  } else if (format[0] == 'l' && format[1] == 'l') {
    length = LENGTH_LONG_LONG;
    used = 2;
  }
  switch (format[used]) {
  case 'u':
    append_unsigned(builder, args, length);
    break;
  case 'd':
    append_signed(builder, args, length);
    break;
  case 's':
    ms_strbuild_append_text(builder, va_arg(*args, const char *));
    break;
  default:
    ms_strbuild_append_byte(builder, '%');
    return 0;
  }
  return used + 1;
}

void ms_strbuild_printf(MsStrBuild *builder, const char *format, ...) {
  va_list args;
  va_start(args, format);
  while (*format != '\0') {
    if (*format != '%') {
      const char *run = format;
      while (*format != '\0' && *format != '%') {
        format++;
      }
      ms_strbuild_append(builder, ms_span_of((const uint8_t *)run, (size_t)(format - run)));
      continue;
    }
    format++;
    if (*format == '%') {
      ms_strbuild_append_byte(builder, '%');
      format++;
      continue;
    }
    format += append_verb(builder, format, &args);
  }
  va_end(args);
}
