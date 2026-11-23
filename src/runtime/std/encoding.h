/* ms_rt/encoding.h: the @std/data/encoding natives (src/runtime/std/encoding.c). Decoders return a status (0
 * ok, 1 InvalidInput, 3 LimitExceeded, 4 InvalidData) and always write `out`: empty unless the call succeeds.
 * `has_max`/`max` bound the decoded size. Symbols are listed in src/runtime/symbols/encoding.txt. */
#ifndef MS_RUNTIME_STD_ENCODING_H
#define MS_RUNTIME_STD_ENCODING_H

#include "abi/status.h"
#include "base/bytes.h"
#include "base/string.h"

/* ms-sig: msstd_encoding_ascii85_decode(text: *const StrVal, has_max: HasRaw, max: i64, out: *mut VecVal) ->
 * u8 @domain=encoding @end */
uint8_t msstd_encoding_ascii85_decode(const MsString *text, uint8_t has_max, int64_t max, MsBytes *out);
/* ms-sig: msstd_encoding_ascii85_encode(data: *const VecVal, out: *mut StrVal) @domain=encoding @end */
void msstd_encoding_ascii85_encode(const MsBytes *data, MsString *out);
/* ms-sig: msstd_encoding_base32_decode(text: *const StrVal, hex_alphabet: u8, padded: u8, has_max: HasRaw,
 * max: i64, out: *mut VecVal) -> u8 @domain=encoding @end */
uint8_t msstd_encoding_base32_decode(const MsString *text, uint8_t hex_alphabet, uint8_t padded,
                                     uint8_t has_max, int64_t max, MsBytes *out);
/* ms-sig: msstd_encoding_base32_encode(data: *const VecVal, hex_alphabet: u8, padded: u8, out: *mut StrVal)
 * @domain=encoding @end */
void msstd_encoding_base32_encode(const MsBytes *data, uint8_t hex_alphabet, uint8_t padded, MsString *out);
/* ms-sig: msstd_encoding_base64_decode(text: *const StrVal, url_safe: u8, has_max: HasRaw, max: i64, out:
 * *mut VecVal) -> u8 @domain=encoding @end */
uint8_t msstd_encoding_base64_decode(const MsString *text, uint8_t url_safe, uint8_t has_max, int64_t max,
                                     MsBytes *out);
/* ms-sig: msstd_encoding_base64_decode_unpadded(text: *const StrVal, url_safe: u8, has_max: HasRaw, max: i64,
 * out: *mut VecVal) -> u8 @domain=encoding @end */
uint8_t msstd_encoding_base64_decode_unpadded(const MsString *text, uint8_t url_safe, uint8_t has_max,
                                              int64_t max, MsBytes *out);
/* ms-sig: msstd_encoding_base64_encode(data: *const VecVal, url_safe: u8, out: *mut StrVal) @domain=encoding
 * */
void msstd_encoding_base64_encode(const MsBytes *data, uint8_t url_safe, MsString *out);
/* ms-sig: msstd_encoding_base64_encode_unpadded(data: *const VecVal, url_safe: u8, out: *mut StrVal)
 * @domain=encoding @end */
void msstd_encoding_base64_encode_unpadded(const MsBytes *data, uint8_t url_safe, MsString *out);
/* ms-sig: msstd_encoding_hex_decode(text: *const StrVal, has_max: HasRaw, max: i64, out: *mut VecVal) -> u8
 * @domain=encoding @end */
uint8_t msstd_encoding_hex_decode(const MsString *text, uint8_t has_max, int64_t max, MsBytes *out);
/* ms-sig: msstd_encoding_hex_encode(data: *const VecVal, out: *mut StrVal) @domain=encoding @end */
void msstd_encoding_hex_encode(const MsBytes *data, MsString *out);

#endif
