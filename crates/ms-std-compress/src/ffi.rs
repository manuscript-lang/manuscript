//! C ABI shims for `@std/compress.ms` (`msrt_compress_*`). The format is passed by name
//! (`"gzip"`, `"zlib"`, `"deflate"`); `CompressionFormat` methods pass the matching constant.
//! Statuses: `STATUS_INVALID_INPUT`, `STATUS_INVALID_DATA`, `STATUS_LIMIT_EXCEEDED` and
//! `STATUS_UNSUPPORTED` (5); `Failed(message)` is never produced.
#![allow(unsafe_code, clippy::missing_safety_doc)]

use crate::Format;
use crate::stream::{Decoder, Encoder, Poll};
use alloc::boxed::Box;
use ms_rt_abi::Obj;
use ms_std_core::{Fail, StrObj, VecVal, bytes_ref, opt, status_of, str_ref, write_bytes};

unsafe extern "C" {
    fn msrt_alloc(size: usize) -> *mut u8;
    fn msrt_free(p: *mut u8);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_compress_compress(
    data: *const VecVal,
    format: *const StrObj,
    level: i64,
    has_max: u8,
    max: i64,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: `data` is a live Bytes value; `format` is live; `out` is writable.
    unsafe {
        let r = crate::compress(bytes_ref(data), str_ref(format), level, opt(has_max, max));
        if let Ok(b) = &r {
            write_bytes(out, b);
        }
        status_of(&r)
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_compress_decompress(
    data: *const VecVal,
    format: *const StrObj,
    has_max: u8,
    max: i64,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: `data` is a live Bytes value; `format` is live; `out` is writable.
    unsafe {
        let r = crate::decompress_bytes(bytes_ref(data), str_ref(format), opt(has_max, max));
        if let Ok(b) = &r {
            write_bytes(out, b);
        }
        status_of(&r)
    }
}

// ---- streams ----
//
// A stream codec is a refcounted handle. The generated code owns the input `ReadStream` and the
// pull loop: on `POLL_NEED_INPUT` it reads a chunk and calls `feed` (or `finish_input` at the end
// of the input), then polls again.

/// `decoder_poll` status: no output yet, feed more input.
pub const POLL_NEED_INPUT: u8 = 64;
/// `decoder_poll` status: the stream ended cleanly.
pub const POLL_DONE: u8 = 65;

#[repr(C)]
pub struct DecoderObj {
    header: Obj,
    decoder: *mut Decoder,
}

#[repr(C)]
pub struct EncoderObj {
    header: Obj,
    encoder: *mut Encoder,
}

unsafe extern "C" fn decoder_drop(o: *mut Obj) {
    // SAFETY: `o` was built by `msrt_compress_decoder_new`; `decoder` came from `Box::into_raw`.
    unsafe {
        drop(Box::from_raw((*o.cast::<DecoderObj>()).decoder));
        msrt_free(o.cast());
    }
}

unsafe extern "C" fn encoder_drop(o: *mut Obj) {
    // SAFETY: `o` was built by `msrt_compress_encoder_new`; `encoder` came from `Box::into_raw`.
    unsafe {
        drop(Box::from_raw((*o.cast::<EncoderObj>()).encoder));
        msrt_free(o.cast());
    }
}

/// `decompress_stream` codec (+1); `format` is `"gzip"`, `"zlib"` or `"deflate"`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_compress_decoder_new(
    format: *const StrObj,
    has_max: u8,
    max: i64,
    out: *mut *mut DecoderObj,
) -> u8 {
    // SAFETY: `format` is live; `out` is writable; the allocation is sized and initialised here.
    unsafe {
        let Some(format) = Format::from_name(str_ref(format)) else {
            return Fail::Unsupported.status();
        };
        let p = msrt_alloc(core::mem::size_of::<DecoderObj>()).cast::<DecoderObj>();
        p.write(DecoderObj {
            header: Obj {
                rc: 1,
                drop: Some(decoder_drop),
            },
            decoder: Box::into_raw(Box::new(Decoder::new(format, opt(has_max, max)))),
        });
        out.write(p);
        0
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_compress_decoder_feed(d: *mut DecoderObj, data: *const VecVal) {
    // SAFETY: `d` is a live handle; `data` is a live Bytes value.
    unsafe { (*(*d).decoder).feed(bytes_ref(data)) };
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_compress_decoder_finish_input(d: *mut DecoderObj) {
    // SAFETY: `d` is a live handle.
    unsafe { (*(*d).decoder).finish_input() };
}

/// Returns 0 with up to `max` bytes in `out`, `POLL_NEED_INPUT`, `POLL_DONE`, or an error status.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_compress_decoder_poll(
    d: *mut DecoderObj,
    max: i64,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: `d` is a live handle; `out` is writable.
    unsafe {
        match (*(*d).decoder).poll(usize::try_from(max).unwrap_or(1)) {
            Ok(Poll::Output(b)) => {
                write_bytes(out, &b);
                0
            }
            Ok(Poll::NeedInput) => POLL_NEED_INPUT,
            Ok(Poll::Done) => POLL_DONE,
            Err(e) => e.status(),
        }
    }
}

/// `compress_stream` codec (+1); a level outside 0..9 returns `STATUS_INVALID_INPUT`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_compress_encoder_new(
    format: *const StrObj,
    level: i64,
    out: *mut *mut EncoderObj,
) -> u8 {
    // SAFETY: `format` is live; `out` is writable; the allocation is sized and initialised here.
    unsafe {
        let Some(format) = Format::from_name(str_ref(format)) else {
            return Fail::Unsupported.status();
        };
        let encoder = match Encoder::new(format, level) {
            Ok(e) => e,
            Err(e) => return e.status(),
        };
        let p = msrt_alloc(core::mem::size_of::<EncoderObj>()).cast::<EncoderObj>();
        p.write(EncoderObj {
            header: Obj {
                rc: 1,
                drop: Some(encoder_drop),
            },
            encoder: Box::into_raw(Box::new(encoder)),
        });
        out.write(p);
        0
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_compress_encoder_feed(e: *mut EncoderObj, data: *const VecVal) {
    // SAFETY: `e` is a live handle; `data` is a live Bytes value.
    unsafe { (*(*e).encoder).feed(bytes_ref(data)) };
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_compress_encoder_finish(e: *mut EncoderObj) {
    // SAFETY: `e` is a live handle.
    unsafe { (*(*e).encoder).finish() };
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_compress_encoder_has_output(e: *const EncoderObj) -> u8 {
    // SAFETY: `e` is a live handle.
    u8::from(unsafe { (*(*e).encoder).has_output() })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_compress_encoder_is_finished(e: *const EncoderObj) -> u8 {
    // SAFETY: `e` is a live handle.
    u8::from(unsafe { (*(*e).encoder).is_finished() })
}

/// Writes at most `max` buffered output bytes (possibly none) to `out`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_compress_encoder_take(
    e: *mut EncoderObj,
    max: i64,
    out: *mut VecVal,
) {
    // SAFETY: `e` is a live handle; `out` is writable.
    unsafe {
        write_bytes(
            out,
            &(*(*e).encoder).take(usize::try_from(max).unwrap_or(0)),
        )
    };
}

#[cfg(test)]
mod tests {
    use super::*;
    use ms_std_core::new_string;

    #[test]
    fn abi_roundtrip() {
        let mut input = core::mem::MaybeUninit::<VecVal>::uninit();
        let (mut packed, mut plain) = (
            core::mem::MaybeUninit::<VecVal>::uninit(),
            core::mem::MaybeUninit::<VecVal>::uninit(),
        );
        let f = new_string("gzip");
        // SAFETY: all pointers are live; results are dropped below.
        unsafe {
            write_bytes(input.as_mut_ptr(), b"hello hello hello");
            assert_eq!(
                msrt_compress_compress(input.as_ptr(), f, 6, 0, 0, packed.as_mut_ptr()),
                0
            );
            assert_eq!(
                msrt_compress_decompress(packed.as_ptr(), f, 1, 16, plain.as_mut_ptr()),
                ms_std_core::STATUS_LIMIT_EXCEEDED
            );
            assert_eq!(
                msrt_compress_decompress(packed.as_ptr(), f, 0, 0, plain.as_mut_ptr()),
                0
            );
            assert_eq!(bytes_ref(plain.as_ptr()), b"hello hello hello");
            for v in [&mut input, &mut packed, &mut plain] {
                ms_rt::vec::msrt_bytes_drop(v.as_mut_ptr());
            }
            ms_rt::obj::msrt_release(f.cast());
        }
    }
    #[test]
    fn stream_roundtrip() {
        use ms_rt as _;
        let f = new_string("gzip");
        let mut enc = core::mem::MaybeUninit::<*mut EncoderObj>::uninit();
        let mut dec = core::mem::MaybeUninit::<*mut DecoderObj>::uninit();
        let (mut data, mut chunk, mut plain) = (
            core::mem::MaybeUninit::<VecVal>::uninit(),
            core::mem::MaybeUninit::<VecVal>::uninit(),
            core::mem::MaybeUninit::<VecVal>::uninit(),
        );
        // SAFETY: all pointers are live; handles and buffers are released by process exit.
        unsafe {
            write_bytes(data.as_mut_ptr(), b"hello hello hello");
            assert_eq!(
                msrt_compress_encoder_new(f, 10, enc.as_mut_ptr()),
                ms_std_core::STATUS_INVALID_INPUT
            );
            assert_eq!(msrt_compress_encoder_new(f, 6, enc.as_mut_ptr()), 0);
            let enc = enc.assume_init();
            msrt_compress_encoder_feed(enc, data.as_ptr());
            msrt_compress_encoder_finish(enc);
            assert_eq!(msrt_compress_encoder_is_finished(enc), 1);
            msrt_compress_encoder_take(enc, 1 << 20, chunk.as_mut_ptr());
            assert_eq!(msrt_compress_decoder_new(f, 0, 0, dec.as_mut_ptr()), 0);
            let dec = dec.assume_init();
            assert_eq!(
                msrt_compress_decoder_poll(dec, 100, plain.as_mut_ptr()),
                POLL_NEED_INPUT
            );
            msrt_compress_decoder_feed(dec, chunk.as_ptr());
            assert_eq!(msrt_compress_decoder_poll(dec, 100, plain.as_mut_ptr()), 0);
            assert_eq!(bytes_ref(plain.as_ptr()), b"hello hello hello");
            // A gzip stream may continue with another member until the input ends.
            assert_eq!(
                msrt_compress_decoder_poll(dec, 100, plain.as_mut_ptr()),
                POLL_NEED_INPUT
            );
            msrt_compress_decoder_finish_input(dec);
            assert_eq!(
                msrt_compress_decoder_poll(dec, 100, plain.as_mut_ptr()),
                POLL_DONE
            );
        }
    }
}
