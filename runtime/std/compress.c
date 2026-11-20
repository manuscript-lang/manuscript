/* @std/io/archive natives on zlib: gzip, zlib and raw deflate, whole-buffer and streaming. A whole-buffer call is the
 * streaming codec run over one chunk, so the two cannot disagree. Malformed data is InvalidData, output past the limit
 * is LimitExceeded, and an out-of-range level is InvalidInput. The compressed bytes are zlib's; the gzip header carries
 * no name or time and the operating system 255 (unknown). */
#define ZLIB_CONST
#include <limits.h>
#include <string.h>
#include <zlib.h>

#include "abi.h"
#include "ms_rt/compress.h"
#include "ms_rt/safe.h"

typedef enum Format { FORMAT_GZIP, FORMAT_ZLIB, FORMAT_DEFLATE } Format;

enum {
    LEVEL_MAX = 9,
    OUTPUT_CHUNK = 16 * 1024,    /* the room reserved before each zlib call */
    OUTPUT_CALL_MAX = 1 << 30,   /* the most one zlib call may produce, so avail_out never overflows */
    WINDOW_BITS = 15,
    GZIP_WRAPPER = 16,           /* added to the window bits: a gzip wrapper (encode) or gzip detection (decode) */
    UNKNOWN_OS = 255,
};

static bool parse_format(const MsStr *name, Format *out) {
    static const struct {
        const char *text;
        Format format;
    } known[] = {{"gzip", FORMAT_GZIP}, {"zlib", FORMAT_ZLIB}, {"deflate", FORMAT_DEFLATE}};
    const size_t length = msrt_str_len(name);
    for (size_t i = 0; i < MS_COUNT_OF(known); i++) {
        if (strlen(known[i].text) == length && memcmp(known[i].text, msrt_str_data(name), length) == 0) {
            *out = known[i].format;
            return true;
        }
    }
    return false;
}

/* The `windowBits` argument that selects the wrapper. */
static int window_bits(Format format) {
    switch (format) {
    case FORMAT_GZIP: return WINDOW_BITS + GZIP_WRAPPER;
    case FORMAT_ZLIB: return WINDOW_BITS;
    case FORMAT_DEFLATE: return -WINDOW_BITS;
    }
    return WINDOW_BITS;
}

/* ---- the output buffer ------------------------------------------------------------------------------------------- */

typedef struct Sink {
    uint8_t *data; /* msrt_alloc'd, or NULL while empty */
    size_t len, cap;
} Sink;

/* Makes room for at least `extra` more bytes. */
static void sink_reserve(Sink *sink, size_t extra) {
    if (sink->cap - sink->len >= extra) {
        return;
    }
    size_t wanted = 0;
    size_t grown = 0;
    // An overflowing request is passed on as the largest size: the allocator refuses it.
    if (!ms_size_add(sink->len, extra, &wanted)) {
        wanted = SIZE_MAX;
    }
    if (!ms_size_mul(sink->cap > OUTPUT_CHUNK ? sink->cap : OUTPUT_CHUNK, 2, &grown)) {
        grown = wanted;
    }
    sink->cap = grown > wanted ? grown : wanted;
    sink->data = msrt_realloc(sink->data, sink->cap);
}

/* Gives the bytes to `out` as an allocation of exactly their length (null when there are none). */
static void sink_finish(Sink *sink, MsVec *out) {
    if (sink->len == 0) {
        msrt_free(sink->data);
        msrt_write_bytes(out, NULL, 0);
    } else {
        out->ptr = msrt_realloc(sink->data, sink->len);
        out->len = out->cap = sink->len;
    }
    *sink = (Sink){0};
}

static void sink_discard(Sink *sink, MsVec *out) {
    msrt_free(sink->data);
    *sink = (Sink){0};
    msrt_write_bytes(out, NULL, 0);
}

/* Points zlib's output at the free room of `sink`, at most `limit` bytes of it. */
static uInt sink_room(Sink *sink, uint64_t limit, Bytef **next) {
    sink_reserve(sink, OUTPUT_CHUNK);
    uint64_t room = sink->cap - sink->len;
    room = room > OUTPUT_CALL_MAX ? OUTPUT_CALL_MAX : room;
    room = room > limit ? limit : room;
    *next = sink->data + sink->len;
    return (uInt)room;
}

static MsBytes bytes_in(const MsVec *data) { return ms_bytes_of(data->ptr, data->len); }

/* ---- encoding ---------------------------------------------------------------------------------------------------- */

typedef struct Encoder {
    MsObj header;
    z_stream stream;
    gz_header gzip; /* zlib reads it while writing the first bytes */
    bool finished;
} Encoder;

/* Deflates `input` with `flush` (Z_NO_FLUSH, or Z_FINISH to end the stream) and appends the output to `sink`. */
static void encode_chunks(Encoder *encoder, MsBytes input, int flush, Sink *sink) {
    z_stream *stream = &encoder->stream;
    const uint8_t *next = input.ptr;
    size_t left = input.len;
    for (;;) {
        const uInt step = left > UINT_MAX ? UINT_MAX : (uInt)left;
        const bool last = step == left;
        stream->next_in = next;
        stream->avail_in = step;
        do {
            Bytef *out_next = NULL;
            stream->avail_out = sink_room(sink, UINT64_MAX, &out_next);
            stream->next_out = out_next;
            const uInt offered = stream->avail_out;
            (void)deflate(stream, last ? flush : Z_NO_FLUSH);
            sink->len += offered - stream->avail_out;
        } while (stream->avail_out == 0);
        if (last) {
            return;
        }
        next += step;
        left -= step;
    }
}

static void encoder_drop(MsObj *object) {
    Encoder *encoder = (Encoder *)object;
    deflateEnd(&encoder->stream);
    msrt_free(encoder);
}

/* Starts an encoder at `level` (0 to 9) for `format`. Null on failure. */
static Encoder *encoder_open(Format format, int level) {
    Encoder *encoder = msrt_alloc_zeroed(sizeof *encoder);
    encoder->header.drop = encoder_drop;
    const int memory_level = 8;
    if (deflateInit2(&encoder->stream, level, Z_DEFLATED, window_bits(format), memory_level, Z_DEFAULT_STRATEGY) != Z_OK) {
        msrt_free(encoder);
        return NULL;
    }
    if (format == FORMAT_GZIP) {
        encoder->gzip.os = UNKNOWN_OS;
        (void)deflateSetHeader(&encoder->stream, &encoder->gzip);
    }
    return encoder;
}

uint8_t msstd_compress_compress(const MsVec *data, const MsStr *format_name, int64_t level, uint8_t has_max, int64_t max,
                                MsVec *out) {
    msrt_write_bytes(out, NULL, 0);
    Format format = FORMAT_GZIP;
    if ((has_max && max < 0) || level < 0 || level > LEVEL_MAX) {
        return STATUS_INVALID_INPUT;
    }
    if (!parse_format(format_name, &format)) {
        return STATUS_UNSUPPORTED;
    }
    Encoder *encoder = encoder_open(format, (int)level);
    if (encoder == NULL) {
        return STATUS_FAILED;
    }
    Sink sink = {0};
    encode_chunks(encoder, bytes_in(data), Z_FINISH, &sink);
    encoder_drop(&encoder->header);
    if (has_max && sink.len > (uint64_t)max) {
        sink_discard(&sink, out);
        return STATUS_LIMIT_EXCEEDED;
    }
    sink_finish(&sink, out);
    return STATUS_OK;
}

uint8_t msstd_compress_encoder_new(const MsStr *name, int64_t level, void **out) {
    Format format = FORMAT_GZIP;
    if (!parse_format(name, &format)) {
        return STATUS_UNSUPPORTED;
    }
    if (level < 0 || level > LEVEL_MAX) {
        return STATUS_INVALID_INPUT;
    }
    Encoder *encoder = encoder_open(format, (int)level);
    if (encoder == NULL) {
        return STATUS_FAILED;
    }
    *out = encoder;
    return STATUS_OK;
}

void msstd_compress_encoder_push(void *handle, const MsVec *data, MsVec *out) {
    Encoder *encoder = handle;
    Sink sink = {0};
    if (!encoder->finished) {
        encode_chunks(encoder, bytes_in(data), Z_NO_FLUSH, &sink);
    }
    sink_finish(&sink, out);
}

void msstd_compress_encoder_end(void *handle, MsVec *out) {
    Encoder *encoder = handle;
    Sink sink = {0};
    if (!encoder->finished) {
        encoder->finished = true;
        encode_chunks(encoder, ms_bytes_of(NULL, 0), Z_FINISH, &sink);
    }
    sink_finish(&sink, out);
}

/* ---- decoding ---------------------------------------------------------------------------------------------------- */

typedef struct Decoder {
    MsObj header;
    z_stream stream;
    Format format;
    int64_t max, total;
    bool ended;   /* the current payload's trailer was read */
    bool done;    /* nothing may follow: a zlib or raw payload ended */
    uint8_t failure; /* the first error, repeated by every later call */
} Decoder;

static void decoder_drop(MsObj *object) {
    Decoder *decoder = (Decoder *)object;
    inflateEnd(&decoder->stream);
    msrt_free(decoder);
}

static Decoder *decoder_open(Format format, int64_t max) {
    Decoder *decoder = msrt_alloc_zeroed(sizeof *decoder);
    decoder->header.drop = decoder_drop;
    decoder->format = format;
    decoder->max = max < 0 ? 0 : max; /* a negative bound fails on the first output byte */
    if (inflateInit2(&decoder->stream, window_bits(format)) != Z_OK) {
        msrt_free(decoder);
        return NULL;
    }
    return decoder;
}

/* The bytes the output may still grow by before it passes the limit, plus the one that proves it did. */
static uint64_t decoder_room(const Decoder *decoder) {
    const uint64_t left = decoder->max < decoder->total ? 0 : (uint64_t)(decoder->max - decoder->total);
    return left + 1;
}

/* Inflates the front of `input` until zlib needs more of it or the payload ends; appends the output to `sink` and
 * returns zlib's last code. `consumed` is how much input zlib took. */
static int inflate_some(Decoder *decoder, MsBytes input, Sink *sink, size_t *consumed, uint8_t *status) {
    z_stream *stream = &decoder->stream;
    const uInt step = input.len > UINT_MAX ? UINT_MAX : (uInt)input.len;
    stream->next_in = input.ptr;
    stream->avail_in = step;
    int code = Z_OK;
    do {
        Bytef *out_next = NULL;
        stream->avail_out = sink_room(sink, decoder_room(decoder), &out_next);
        stream->next_out = out_next;
        const uInt offered = stream->avail_out;
        code = inflate(stream, Z_NO_FLUSH);
        const uInt produced = offered - stream->avail_out;
        sink->len += produced;
        decoder->total = decoder->total > INT64_MAX - (int64_t)produced ? INT64_MAX : decoder->total + (int64_t)produced;
        if (decoder->total > decoder->max) {
            *status = STATUS_LIMIT_EXCEEDED;
            return code;
        }
        if (code != Z_OK && code != Z_STREAM_END && code != Z_BUF_ERROR) {
            *status = STATUS_INVALID_DATA; /* corrupt data, a preset dictionary, or a stream state error */
            return code;
        }
    } while (code == Z_OK && stream->avail_out == 0);
    *consumed = step - stream->avail_in;
    return code;
}

/* Decodes as far as `input` allows. At `eof` a payload that has not ended is InvalidData. */
static uint8_t decode(Decoder *decoder, MsBytes input, bool eof, Sink *sink) {
    const uint8_t *next = input.ptr;
    size_t left = input.len;
    for (;;) {
        if (decoder->done || (decoder->ended && decoder->format != FORMAT_GZIP)) {
            decoder->done = true;
            return left == 0 ? STATUS_OK : STATUS_INVALID_DATA; /* nothing may follow the payload */
        }
        if (decoder->ended) { /* gzip: another member follows, or the stream is complete */
            if (left == 0) {
                return STATUS_OK;
            }
            (void)inflateReset(&decoder->stream);
            decoder->ended = false;
        }
        size_t consumed = 0;
        uint8_t status = STATUS_OK;
        const int code = inflate_some(decoder, ms_bytes_of(next, left), sink, &consumed, &status);
        if (status != STATUS_OK) {
            return status;
        }
        next += consumed;
        left -= consumed;
        if (code == Z_STREAM_END) {
            decoder->ended = true;
            continue;
        }
        if (left == 0) { /* zlib wants more input */
            return eof ? STATUS_INVALID_DATA : STATUS_OK;
        }
    }
}

/* One step of a decoder handle: feeds `data`, returns the output it completes in `out`. */
static uint8_t decoder_step(Decoder *decoder, MsBytes data, bool eof, MsVec *out) {
    msrt_write_bytes(out, NULL, 0);
    if (decoder->failure != STATUS_OK) {
        return decoder->failure;
    }
    Sink sink = {0};
    decoder->failure = decode(decoder, data, eof, &sink);
    if (decoder->failure != STATUS_OK) {
        sink_discard(&sink, out);
        return decoder->failure;
    }
    sink_finish(&sink, out);
    return STATUS_OK;
}

uint8_t msstd_compress_decompress(const MsVec *data, const MsStr *format_name, uint8_t has_max, int64_t max, MsVec *out) {
    msrt_write_bytes(out, NULL, 0);
    Format format = FORMAT_GZIP;
    if (has_max && max < 0) {
        return STATUS_INVALID_INPUT;
    }
    if (!parse_format(format_name, &format)) {
        return STATUS_UNSUPPORTED;
    }
    Decoder *decoder = decoder_open(format, has_max ? max : INT64_MAX);
    if (decoder == NULL) {
        return STATUS_FAILED;
    }
    const uint8_t status = decoder_step(decoder, bytes_in(data), true, out);
    decoder_drop(&decoder->header);
    return status;
}

uint8_t msstd_compress_decoder_new(const MsStr *name, uint8_t has_max, int64_t max, void **out) {
    Format format = FORMAT_GZIP;
    if (!parse_format(name, &format)) {
        return STATUS_UNSUPPORTED;
    }
    Decoder *decoder = decoder_open(format, has_max ? max : INT64_MAX);
    if (decoder == NULL) {
        return STATUS_FAILED;
    }
    *out = decoder;
    return STATUS_OK;
}

uint8_t msstd_compress_decoder_push(void *handle, const MsVec *data, MsVec *out) {
    return decoder_step(handle, bytes_in(data), false, out);
}

uint8_t msstd_compress_decoder_end(void *handle, MsVec *out) {
    return decoder_step(handle, ms_bytes_of(NULL, 0), true, out);
}

/* ---- the resumable gunzip the Rust HTTP client calls --------------------------------------------------------------- */

struct MsGunzip {
    z_stream stream;
    bool ended;   /* a member's trailer was read: the next input starts another member */
};

MsGunzip *ms_gunzip_new(void) {
    MsGunzip *gunzip = msrt_alloc_zeroed(sizeof *gunzip);
    if (inflateInit2(&gunzip->stream, window_bits(FORMAT_GZIP)) != Z_OK) {
        msrt_free(gunzip);
        return NULL;
    }
    return gunzip;
}

void ms_gunzip_free(MsGunzip *gunzip) {
    if (gunzip != NULL) {
        inflateEnd(&gunzip->stream);
        msrt_free(gunzip);
    }
}

uint8_t ms_gunzip_step(MsGunzip *gunzip, const uint8_t *in, size_t in_len, bool more, uint8_t *out, size_t out_cap,
                              size_t *in_used, size_t *out_used) {
    z_stream *stream = &gunzip->stream;
    *in_used = 0;
    *out_used = 0;
    if (gunzip->ended) {
        if (in_len == 0) { /* between members: finished once no more input can follow */
            return more ? MS_GUNZIP_OK : MS_GUNZIP_DONE;
        }
        (void)inflateReset(stream);
        gunzip->ended = false;
    }
    const uInt step_in = in_len > UINT_MAX ? UINT_MAX : (uInt)in_len;
    const uInt step_out = out_cap > UINT_MAX ? UINT_MAX : (uInt)out_cap;
    stream->next_in = in;
    stream->avail_in = step_in;
    stream->next_out = out;
    stream->avail_out = step_out;
    const int code = inflate(stream, Z_NO_FLUSH);
    *in_used = step_in - stream->avail_in;
    *out_used = step_out - stream->avail_out;
    if (code == Z_STREAM_END) {
        gunzip->ended = true;
        return MS_GUNZIP_OK;
    }
    if (code != Z_OK && code != Z_BUF_ERROR) {
        return MS_GUNZIP_INVALID;
    }
    if (stream->avail_out == 0 || *in_used < in_len) {
        return MS_GUNZIP_OK; /* more room or the rest of the input is wanted */
    }
    return more ? MS_GUNZIP_OK : MS_GUNZIP_TRUNCATED;
}
