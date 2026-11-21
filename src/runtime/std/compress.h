/* runtime/std/compress.h: the @std/io/archive natives (src/runtime/std/compress.c, on zlib). A format is
 * named "gzip", "zlib" or "deflate" (raw). Fallible functions return a status (0 ok, 1 InvalidInput, 3
 * LimitExceeded, 4 InvalidData, 9 Unsupported) and always write `out`: empty unless the call succeeds.
 * `has_max`/`max` bound the output size. A codec is a handle the caller owns; encoders and decoders feed one
 * chunk at a time and return the output it completes. Symbols are listed in src/runtime/symbols/compress.txt.
 */
#ifndef MS_RUNTIME_STD_COMPRESS_H
#define MS_RUNTIME_STD_COMPRESS_H

#include "abi/status.h"
#include "base/bytes.h"
#include "base/string.h"

/* The status of a format the codec does not know (the catalogue numbers it 9; abi/status.h lists no such
 * code). */
enum { COMPRESS_STATUS_UNSUPPORTED = 9 };

/* ms-sig: msstd_compress_compress(data: *const VecVal, format: *const StrVal, level: i64, has_max: HasRaw,
 * max: i64, out: *mut VecVal) -> u8 @domain=compression */
uint8_t msstd_compress_compress(const MsBytes *data, const MsString *format, int64_t level, uint8_t has_max,
                                int64_t max, MsBytes *out);
/* ms-sig: msstd_compress_decompress(data: *const VecVal, format: *const StrVal, has_max: HasRaw, max: i64,
 * out: *mut VecVal) -> u8 @domain=compression */
uint8_t msstd_compress_decompress(const MsBytes *data, const MsString *format, uint8_t has_max, int64_t max,
                                  MsBytes *out);
/* ms-sig: msstd_compress_encoder_new(name: *const StrVal, level: i64, out: *mut *mut ObjCell<EncoderObj>) ->
 * u8 @domain=compression */
uint8_t msstd_compress_encoder_new(const MsString *name, int64_t level, void **out);
/* ms-sig: msstd_compress_encoder_push(handle e: *const ObjCell<EncoderObj>, data: *const VecVal, out: *mut
 * VecVal) @domain=compression */
void msstd_compress_encoder_push(void *handle, const MsBytes *data, MsBytes *out);
/* ms-sig: msstd_compress_encoder_end(handle e: *const ObjCell<EncoderObj>, out: *mut VecVal)
 * @domain=compression */
void msstd_compress_encoder_end(void *handle, MsBytes *out);
/* ms-sig: msstd_compress_decoder_new(name: *const StrVal, has_max: HasRaw, max: i64, out: *mut *mut
 * ObjCell<DecoderObj>) -> u8 @domain=compression */
uint8_t msstd_compress_decoder_new(const MsString *name, uint8_t has_max, int64_t max, void **out);
/* ms-sig: msstd_compress_decoder_push(handle decoder: *const ObjCell<DecoderObj>, data: *const VecVal, out:
 * *mut VecVal) -> u8 @domain=compression */
uint8_t msstd_compress_decoder_push(void *handle, const MsBytes *data, MsBytes *out);
/* ms-sig: msstd_compress_decoder_end(handle decoder: *const ObjCell<DecoderObj>, out: *mut VecVal) -> u8
 * @domain=compression */
uint8_t msstd_compress_decoder_end(void *handle, MsBytes *out);

/* A resumable gunzip over concatenated members, for the HTTP client (src/runtime/std/compress.c). Not a
 * catalogued native: only Rust calls it. `ms_gunzip_step` inflates from `in` into `out` and reports how much
 * of each it used. OK: call again with the unused input and fresh room (no use of either means it waits for
 * input); DONE: every member ended and `more` is false; INVALID: not gzip or corrupt; TRUNCATED: the input
 * ended inside a member and `more` is false. */
typedef struct MsGunzip MsGunzip;
typedef enum MsGunzipStatus {
  MS_GUNZIP_OK,
  MS_GUNZIP_DONE,
  MS_GUNZIP_INVALID,
  MS_GUNZIP_TRUNCATED
} MsGunzipStatus;
MsGunzip *ms_gunzip_new(void);
void ms_gunzip_free(MsGunzip *gunzip);
uint8_t ms_gunzip_step(MsGunzip *gunzip, const uint8_t *in, size_t in_len, bool more, uint8_t *out,
                       size_t out_cap, size_t *in_used, size_t *out_used);

#endif
