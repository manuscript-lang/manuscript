/* ms_rt/compress.h: the @std/io/archive natives (runtime/std/compress.c, on zlib). A format is named "gzip", "zlib" or
 * "deflate" (raw). Fallible functions return a status (0 ok, 1 InvalidInput, 3 LimitExceeded, 4 InvalidData,
 * 9 Unsupported) and always write `out`: empty unless the call succeeds. `has_max`/`max` bound the output size. A
 * codec is a handle the caller owns; encoders and decoders feed one chunk at a time and return the output it completes.
 * Symbols are listed in runtime/symbols/compress.txt. */
#ifndef MS_RT_COMPRESS_H
#define MS_RT_COMPRESS_H

#include "ms_rt/base.h"
#include "ms_rt/string.h"

/* ms-sig: msstd_compress_compress(data: *const VecVal, format: *const StrVal, level: i64, has_max: HasRaw, max: i64, out: *mut VecVal) -> u8 @domain=compression */
uint8_t msstd_compress_compress(const MsVec *data, const MsStr *format, int64_t level, uint8_t has_max, int64_t max, MsVec *out);
/* ms-sig: msstd_compress_decompress(data: *const VecVal, format: *const StrVal, has_max: HasRaw, max: i64, out: *mut VecVal) -> u8 @domain=compression */
uint8_t msstd_compress_decompress(const MsVec *data, const MsStr *format, uint8_t has_max, int64_t max, MsVec *out);
/* ms-sig: msstd_compress_encoder_new(name: *const StrVal, level: i64, out: *mut *mut ObjCell<EncoderObj>) -> u8 @domain=compression */
uint8_t msstd_compress_encoder_new(const MsStr *name, int64_t level, void **out);
/* ms-sig: msstd_compress_encoder_push(handle e: *const ObjCell<EncoderObj>, data: *const VecVal, out: *mut VecVal) @domain=compression */
void msstd_compress_encoder_push(void *handle, const MsVec *data, MsVec *out);
/* ms-sig: msstd_compress_encoder_end(handle e: *const ObjCell<EncoderObj>, out: *mut VecVal) @domain=compression */
void msstd_compress_encoder_end(void *handle, MsVec *out);
/* ms-sig: msstd_compress_decoder_new(name: *const StrVal, has_max: HasRaw, max: i64, out: *mut *mut ObjCell<DecoderObj>) -> u8 @domain=compression */
uint8_t msstd_compress_decoder_new(const MsStr *name, uint8_t has_max, int64_t max, void **out);
/* ms-sig: msstd_compress_decoder_push(handle decoder: *const ObjCell<DecoderObj>, data: *const VecVal, out: *mut VecVal) -> u8 @domain=compression */
uint8_t msstd_compress_decoder_push(void *handle, const MsVec *data, MsVec *out);
/* ms-sig: msstd_compress_decoder_end(handle decoder: *const ObjCell<DecoderObj>, out: *mut VecVal) -> u8 @domain=compression */
uint8_t msstd_compress_decoder_end(void *handle, MsVec *out);

#endif
