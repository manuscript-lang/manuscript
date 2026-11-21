/* The @std/math, @std/data/checksum and @std/random natives (src/runtime/std/stdmath.c, checksum.c, random.c). */
#include <math.h>
#include <stdio.h>
#include <string.h>

#include "ms_rt/checksum.h"
#include "ms_rt/random.h"
#include "ms_rt/stdmath.h"
#include "fake_rt.h"

static double not_a_number(void) { return nan(""); }

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

/* A Bytes value over `storage`, which holds `text`: a string literal is const, a Bytes buffer is not. */
static MsVec bytes_in(char *storage, const char *text) {
    const size_t length = strlen(text);
    memcpy(storage, text, length);
    return (MsVec){storage, length, length};
}

static void test_round_and_sign(void) {
    CHECK(msstd_math_round(2.5) == 3.0);
    CHECK(msstd_math_round(-2.5) == -2.0);
    CHECK(signbit(msstd_math_round(-0.2)));
    CHECK(msstd_math_round(0.49999999999999994) == 0.0);
    CHECK(isnan(msstd_math_round(not_a_number())) && isinf(msstd_math_round(HUGE_VAL)));
    CHECK(msstd_math_round_to_even(2.5) == 2.0 && msstd_math_round_to_even(3.5) == 4.0);
    CHECK(msstd_math_sign(-7.0) == -1.0 && msstd_math_sign(HUGE_VAL) == 1.0);
    CHECK(signbit(msstd_math_sign(-0.0)) && isnan(msstd_math_sign(not_a_number())));
}

static void test_special_values(void) {
    CHECK(msstd_math_pow(1.0, not_a_number()) == 1.0);
    CHECK(isnan(msstd_math_sqrt(-1.0)));
    CHECK(msstd_math_log(0.0) == -HUGE_VAL);
    CHECK(msstd_math_remainder(5.5, 2.0) == 1.5);
    CHECK(msstd_math_ieee_remainder(5.5, 2.0) == -0.5);
    CHECK(msstd_math_hypot(3.0, 4.0) == 5.0);
    CHECK(msstd_math_is_integer(3.0) == 1 && msstd_math_is_integer(HUGE_VAL) == 0 && msstd_math_is_integer(2.5) == 0);
    CHECK(msstd_math_is_safe_integer(9007199254740991.0) == 1 && msstd_math_is_safe_integer(9007199254740992.0) == 0);
    CHECK(msstd_math_sign_bit(-0.0) == 1 && msstd_math_sign_bit(0.0) == 0);
    CHECK(msstd_math_next_after(1.0, 1.0) == 1.0 && msstd_math_next_after(0.0, 1.0) > 0.0);
    CHECK(msstd_math_ldexp(1.0, 3) == 8.0 && msstd_math_ldexp(1.0, INT64_MAX) == HUGE_VAL && msstd_math_ldexp(1.0, INT64_MIN) == 0.0);
}

static void test_float_parts(void) {
    MsBinaryFloatParts frexp_parts;
    msstd_math_frexp(8.0, &frexp_parts);
    CHECK(frexp_parts.fraction == 0.5 && frexp_parts.exponent == 4);
    msstd_math_frexp(HUGE_VAL, &frexp_parts);
    CHECK(frexp_parts.fraction == HUGE_VAL && frexp_parts.exponent == 0);
    MsFloatParts parts;
    msstd_math_modf(-2.75, &parts);
    CHECK(parts.integer == -2.0 && parts.fraction == -0.75);
}

static void test_wide_words(void) {
    MsWordSum sum;
    msstd_math_add_with_carry(UINT64_MAX, 0, 1, &sum);
    CHECK(sum.sum == 0 && sum.carry == 1);
    msstd_math_add_with_carry(1, 2, 0, &sum);
    CHECK(sum.sum == 3 && sum.carry == 0);
    MsWordDifference difference;
    msstd_math_subtract_with_borrow(0, 0, 1, &difference);
    CHECK(difference.difference == UINT64_MAX && difference.borrow == 1);
    msstd_math_subtract_with_borrow(5, 2, 1, &difference);
    CHECK(difference.difference == 2 && difference.borrow == 0);
    MsWideProduct product;
    msstd_math_multiply_wide(UINT64_MAX, UINT64_MAX, &product);
    CHECK(product.high == UINT64_MAX - 1 && product.low == 1);
    MsWordDivision division;
    CHECK(msstd_math_divide_wide(0, 7, 0, &division) == 1);
    CHECK(msstd_math_divide_wide(3, 0, 3, &division) == 2);
    CHECK(msstd_math_divide_wide(1, 0, 3, &division) == 0 && division.quotient == 0x5555555555555555u && division.remainder == 1);
    uint64_t remainder;
    CHECK(msstd_math_remainder_wide(1, 0, 0, &remainder) == 1);
    CHECK(msstd_math_remainder_wide(5, 9, 4, &remainder) == 0 && remainder == (((uint64_t)5 << 32) % 4 + 9) % 4);
}

static void test_checksums(void) {
    char storage[16];
    const MsVec check = bytes_in(storage, "123456789");
    CHECK(msstd_checksum_crc32(&check) == 0xCBF43926);
    char wiki_storage[16];
    const MsVec wiki = bytes_in(wiki_storage, "Wikipedia");
    CHECK(msstd_checksum_adler32_update(1, &wiki) == 0x11E60398);
    const MsVec empty = {NULL, 0, 0};
    CHECK(msstd_checksum_crc32(&empty) == 0);
    CHECK(msstd_checksum_crc32_update(0xCBF43926, &empty) == 0xCBF43926);
    CHECK(msstd_checksum_adler32_update(0x11E60398, &empty) == 0x11E60398);
    char head_storage[8], tail_storage[8];
    const MsVec head = bytes_in(head_storage, "1234"), tail = bytes_in(tail_storage, "56789");
    const int64_t first = msstd_checksum_crc32(&head);
    CHECK(msstd_checksum_crc32_update(first, &tail) == 0xCBF43926);
}

static void test_random(void) {
    MsVec out = {NULL, 0, 0};
    CHECK(msstd_random_os_bytes(-1, &out, NULL) == 1);
    CHECK(msstd_random_os_bytes(16 * 1024 * 1024 + 1, &out, NULL) == 1);
    CHECK(msstd_random_os_bytes(0, &out, NULL) == 0 && out.len == 0);
    CHECK(msstd_random_os_bytes(32, &out, NULL) == 0 && out.len == 32);
    msrt_free(out.ptr);
    const int64_t first = msstd_random_v7_next(1000, 5);
    CHECK((first >> 12) == 1000);
    CHECK(msstd_random_v7_next(1000, 2) == first + 1);
    CHECK(msstd_random_v7_next(999, 2) == first + 2);
    CHECK(msstd_random_v7_next(1001, 9) > first + 2);
}

int main(void) {
    test_round_and_sign();
    test_special_values();
    test_float_parts();
    test_wide_words();
    test_checksums();
    test_random();
    puts(failures == 0 ? "std_core: ok" : "std_core: FAILED");
    return failures == 0 ? 0 : 1;
}
