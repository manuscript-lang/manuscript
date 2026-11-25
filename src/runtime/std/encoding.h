/* ms_rt/encoding.h: the Base64 natives of @std/data/encoding (src/runtime/std/encoding.c). Decoders return a status (0
 * ok, 1 InvalidInput, 3 LimitExceeded, 4 InvalidData) and always write `out`: empty unless the call succeeds.
 * `has_max`/`max` bound the decoded size. Symbols are listed in src/runtime/symbols/encoding.txt. */
#ifndef MS_RUNTIME_STD_ENCODING_H
#define MS_RUNTIME_STD_ENCODING_H

#include "abi/status.h"
#include "base/bytes.h"
#include "base/string.h"

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

#endif
