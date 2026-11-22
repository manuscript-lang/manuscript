/* The receiver operations of the sized number types. Every integer type travels as an int64 that holds its value
 * sign-extended (UInt8, UInt16 and UInt32 zero-extended; UInt64 as its bit pattern), and Float32 as a double
 * that holds a binary32 value, so one family of functions per type is written from a few macros. */
#include "runtime/core/fault_abi.h"
#include "runtime/core/num.h"
#include "runtime/core/num_sized.h"

/* ---- shared by every integer type ---- */

/* The text of `v` in `radix` when it is 2 through 36; none otherwise. `is_unsigned` reads `v` as a bit pattern. */
static uint8_t radix_text(int64_t v, int64_t radix, bool is_unsigned, MsString *out) {
  return is_unsigned ? msrt_uint_to_string_radix(v, radix, out) : msrt_int_to_string_radix(v, radix, out);
}

/* One integer type: its text, radix forms, float conversions and comparison. */
#define TEXT_OPS(name, is_unsigned)                                                                              \
  void msrt_##name##_to_string(int64_t v, MsString *out) {                                                     \
    if (is_unsigned) {                                                                                         \
      msrt_uint_to_string(v, out);                                                                             \
    } else {                                                                                                   \
      msrt_int_to_string(v, out);                                                                              \
    }                                                                                                          \
  }                                                                                                            \
  uint8_t msrt_##name##_to_string_radix(int64_t v, int64_t radix, MsString *out) {                             \
    return radix_text(v, radix, is_unsigned, out);                                                             \
  }

#define NUMBER_OPS(name, is_unsigned)                                                                            \
  void msrt_##name##_to_hex(int64_t v, MsString *out) {                                                        \
    (void)radix_text(v, 16, is_unsigned, out);                                                                 \
  }                                                                                                            \
  void msrt_##name##_to_binary(int64_t v, MsString *out) {                                                     \
    (void)radix_text(v, 2, is_unsigned, out);                                                                  \
  }                                                                                                            \
  double msrt_##name##_to_float(int64_t v) {                                                                   \
    return is_unsigned ? msrt_uint_to_float(v) : (double)v;                                                    \
  }                                                                                                            \
  double msrt_##name##_to_float32(int64_t v) {                                                                 \
    return is_unsigned ? msrt_uint_to_float32(v) : (double)(float)v;                                           \
  }

#define COMPARE_OPS(name, is_unsigned)                                                                           \
  int64_t msrt_##name##_compare(int64_t a, int64_t b) {                                                        \
    return is_unsigned ? msrt_uint_compare(a, b) : msrt_int_compare(a, b);                                     \
  }

#define INTEGER_OPS(name, is_unsigned)                                                                           \
  TEXT_OPS(name, is_unsigned)                                                                                  \
  NUMBER_OPS(name, is_unsigned)                                                                                \
  COMPARE_OPS(name, is_unsigned)

/* A signed type's abs and sign; the most negative value has no absolute value in the type. */
#define SIGNED_OPS(name, minimum)                                                                                \
  int64_t msrt_##name##_abs(int64_t v) {                                                                       \
    if (v == (minimum)) {                                                                                      \
      msrt_fault_int_range();                                                                                  \
    }                                                                                                          \
    return v < 0 ? -v : v;                                                                                     \
  }                                                                                                            \
  int64_t msrt_##name##_sign(int64_t v) {                                                                      \
    return (int64_t)(v > 0) - (int64_t)(v < 0);                                                                \
  }

/* Int has its text and comparison natives in num.c and num_text.c. */
NUMBER_OPS(int, false)
INTEGER_OPS(int8, false)
INTEGER_OPS(int16, false)
INTEGER_OPS(int32, false)
INTEGER_OPS(int64, false)
INTEGER_OPS(uint8, false)
INTEGER_OPS(uint16, false)
INTEGER_OPS(uint32, false)
INTEGER_OPS(uint64, true)

/* Int.abs is the one with a message of its own. */
int64_t msrt_int_abs(int64_t v) {
  if (v == INT64_MIN) {
    msrt_fault_int_overflow();
  }
  return v < 0 ? -v : v;
}
int64_t msrt_int_sign(int64_t v) {
  return (int64_t)(v > 0) - (int64_t)(v < 0);
}
SIGNED_OPS(int8, INT8_MIN)
SIGNED_OPS(int16, INT16_MIN)
SIGNED_OPS(int32, INT32_MIN)
int64_t msrt_int64_abs(int64_t v) {
  return msrt_int_abs(v);
}
int64_t msrt_int64_sign(int64_t v) {
  return msrt_int_sign(v);
}

/* ---- conversions between integer types ---- */

/* `from.to_<to>()` that always fits: the value, widened. */
#define CONVERT_EXACT(from, to)                                                                                  \
  int64_t msrt_##from##_to_##to(int64_t v) {                                                                   \
    return v;                                                                                                  \
  }

/* `from.to_<to>()` that is none when the value is outside [low, high]. */
#define CONVERT_RANGE(from, to, low, high)                                                                       \
  uint8_t msrt_##from##_to_##to(int64_t v, int64_t *out) {                                                     \
    if (v < (low) || v > (high)) {                                                                             \
      return 0;                                                                                                \
    }                                                                                                          \
    *out = v;                                                                                                  \
    return 1;                                                                                                  \
  }

CONVERT_EXACT(int8, int16)
CONVERT_EXACT(int8, int32)
CONVERT_EXACT(int8, int64)
CONVERT_EXACT(int8, int)
CONVERT_EXACT(int16, int64)
CONVERT_EXACT(int16, int)
CONVERT_EXACT(int32, int64)
CONVERT_EXACT(int32, int)
CONVERT_EXACT(uint8, int)
CONVERT_EXACT(uint16, int)
CONVERT_EXACT(uint32, int64)
CONVERT_EXACT(uint32, int)
CONVERT_EXACT(int, int64)

CONVERT_RANGE(int16, int8, INT8_MIN, INT8_MAX)
CONVERT_RANGE(int32, int8, INT8_MIN, INT8_MAX)
CONVERT_RANGE(int32, int16, INT16_MIN, INT16_MAX)
CONVERT_RANGE(uint16, uint8, 0, UINT8_MAX)
CONVERT_RANGE(uint32, int32, 0, INT32_MAX)
CONVERT_RANGE(int, int8, INT8_MIN, INT8_MAX)
CONVERT_RANGE(int, int16, INT16_MIN, INT16_MAX)
CONVERT_RANGE(int, int32, INT32_MIN, INT32_MAX)
CONVERT_RANGE(int, uint8, 0, UINT8_MAX)
CONVERT_RANGE(int, uint16, 0, UINT16_MAX)
CONVERT_RANGE(int, uint32, 0, UINT32_MAX)

/* Int.to_uint64: the bit pattern of a non-negative value. */
uint8_t msrt_int_to_uint64(int64_t v, int64_t *out) {
  if (v < 0) {
    return 0;
  }
  *out = v;
  return 1;
}

/* UInt64 conversions read the bit pattern as unsigned. */
uint8_t msrt_uint64_to_int(int64_t v, int64_t *out) {
  if (v < 0) {
    return 0;
  }
  *out = v;
  return 1;
}

uint8_t msrt_uint64_to_uint8(int64_t v, int64_t *out) {
  return msrt_uint64_to_int(v, out) && *out <= UINT8_MAX;
}

uint8_t msrt_uint64_to_uint32(int64_t v, int64_t *out) {
  return msrt_uint64_to_int(v, out) && *out <= UINT32_MAX;
}

/* ---- Float32, held in a double ---- */

uint8_t msrt_float32_is_nan(double v) {
  return v != v;
}

uint8_t msrt_float32_is_finite(double v) {
  return v - v == 0.0;
}

int64_t msrt_float32_compare(double a, double b) {
  return msrt_float_compare(a, b);
}

double msrt_float32_abs(double v) {
  return v < 0 ? -v : (v == 0 ? 0.0 : v);
}

double msrt_float32_sign(double v) {
  return v != v ? v : (v > 0 ? 1.0 : (v < 0 ? -1.0 : v));
}

uint8_t msrt_float32_truncate_to_int(double v, int64_t *out) {
  return msrt_float_truncate_to_int(v, out);
}

double msrt_float32_to_float(double v) {
  return v;
}

double msrt_float32_to_float64(double v) {
  return v;
}

/* ---- Int and Float ---- */

double msrt_float_abs(double v) {
  return msrt_float32_abs(v);
}

double msrt_float_sign(double v) {
  return msrt_float32_sign(v);
}
