//! C ABI shims for `@std/archive.ms` (`msrt_compress_*`). The format is passed by name
//! (`"gzip"`, `"zlib"`, `"deflate"`); `CompressionFormat` methods pass the matching constant.
//! Statuses: `STATUS_INVALID_INPUT`, `STATUS_INVALID_DATA`, `STATUS_LIMIT_EXCEEDED` and
//! `STATUS_UNSUPPORTED` (9); `Failed(message)` is never produced.

use crate::Format;
use crate::stream::{Decoder, Encoder, Poll};
use alloc::vec::Vec;
use core::cell::RefCell;
use ms_std_core::{Fail, ObjRef, Object, Out, Status, abi_handle, native};

/// `decoder_poll` status: no output yet, feed more input.
pub const POLL_NEED_INPUT: u8 = 64;
/// `decoder_poll` status: the stream ended cleanly.
pub const POLL_DONE: u8 = 65;

/// Why a poll produced no output.
pub enum Stop {
    NeedInput,
    Done,
    Fail(Fail),
}

impl Status for Stop {
    fn status(self) -> u8 {
        match self {
            Stop::NeedInput => POLL_NEED_INPUT,
            Stop::Done => POLL_DONE,
            Stop::Fail(e) => e.status(),
        }
    }
}

// A stream codec is a refcounted handle. The generated code owns the input `ReadStream` and the
// pull loop: on `POLL_NEED_INPUT` it reads a chunk and calls `feed` (or `finish_input` at the end
// of the input), then polls again. Handles are shared, so the codec sits behind a `RefCell`.
pub struct DecoderObj {
    codec: RefCell<Decoder>,
}
pub struct EncoderObj {
    codec: RefCell<Encoder>,
}
abi_handle!(DecoderObj);
abi_handle!(EncoderObj);

fn format(name: &str) -> Result<Format, Fail> {
    Format::from_name(name).ok_or(Fail::Unsupported)
}

native! {
    fn msrt_compress_compress(
        data: &[u8],
        format: &str,
        level: i64,
        has_max: bool,
        max: i64,
    ) -> Result<Vec<u8>, Fail> {
        crate::compress(data, format, level, has_max.then_some(max))
    }

    fn msrt_compress_decompress(
        data: &[u8],
        format: &str,
        has_max: bool,
        max: i64,
    ) -> Result<Vec<u8>, Fail> {
        crate::decompress_bytes(data, format, has_max.then_some(max))
    }

    fn msrt_compress_decoder_new(
        name: &str,
        has_max: bool,
        max: i64,
        out: Out<Object<DecoderObj>>,
    ) -> Result<(), Fail> {
        let d = Decoder::new(format(name)?, has_max.then_some(max));
        out.write(Object(DecoderObj {
            codec: RefCell::new(d),
        }));
        Ok(())
    }

    fn msrt_compress_decoder_feed(d: ObjRef<DecoderObj>, data: &[u8]) -> () {
        d.codec.borrow_mut().feed(data);
    }

    fn msrt_compress_decoder_finish_input(d: ObjRef<DecoderObj>) -> () {
        d.codec.borrow_mut().finish_input();
    }

    fn msrt_compress_decoder_poll(d: ObjRef<DecoderObj>, max: i64) -> Result<Vec<u8>, Stop> {
        match d.codec.borrow_mut().poll(usize::try_from(max).unwrap_or(1)) {
            Ok(Poll::Output(b)) => Ok(b),
            Ok(Poll::NeedInput) => Err(Stop::NeedInput),
            Ok(Poll::Done) => Err(Stop::Done),
            Err(e) => Err(Stop::Fail(e)),
        }
    }

    fn msrt_compress_encoder_new(
        name: &str,
        level: i64,
        out: Out<Object<EncoderObj>>,
    ) -> Result<(), Fail> {
        let e = Encoder::new(format(name)?, level)?;
        out.write(Object(EncoderObj {
            codec: RefCell::new(e),
        }));
        Ok(())
    }

    fn msrt_compress_encoder_feed(e: ObjRef<EncoderObj>, data: &[u8]) -> () {
        e.codec.borrow_mut().feed(data);
    }

    fn msrt_compress_encoder_finish(e: ObjRef<EncoderObj>) -> () {
        e.codec.borrow_mut().finish();
    }

    fn msrt_compress_encoder_has_output(e: ObjRef<EncoderObj>) -> bool {
        e.codec.borrow().has_output()
    }

    fn msrt_compress_encoder_is_finished(e: ObjRef<EncoderObj>) -> bool {
        e.codec.borrow().is_finished()
    }

    fn msrt_compress_encoder_take(e: ObjRef<EncoderObj>, max: i64) -> out Vec<u8> {
        e.codec.borrow_mut().take(usize::try_from(max).unwrap_or(0))
    }
}

#[cfg(test)]
#[allow(unsafe_code)]
mod tests {
    use super::*;
    use core::mem::MaybeUninit;
    use ms_std_core::{ObjCell, VecVal, bytes_ref, new_string, write_bytes};

    fn bytes(b: &[u8]) -> VecVal {
        let mut v = MaybeUninit::<VecVal>::uninit();
        // SAFETY: `write_bytes` initializes the whole slot.
        unsafe {
            write_bytes(v.as_mut_ptr(), b);
            v.assume_init()
        }
    }

    fn blank() -> MaybeUninit<VecVal> {
        MaybeUninit::uninit()
    }

    #[test]
    fn abi_roundtrip() {
        let (input, mut packed, mut plain) = (bytes(b"hello hello hello"), blank(), blank());
        let f = new_string("gzip");
        // SAFETY: all pointers are live; results are released below.
        unsafe {
            assert_eq!(
                msrt_compress_compress(&input, &f, 6, 0, 0, packed.as_mut_ptr()),
                0
            );
            assert_eq!(
                msrt_compress_decompress(packed.as_ptr(), &f, 1, 16, plain.as_mut_ptr()),
                ms_std_core::STATUS_LIMIT_EXCEEDED
            );
            assert_eq!(
                msrt_compress_decompress(packed.as_ptr(), &f, 0, 0, plain.as_mut_ptr()),
                0
            );
            assert_eq!(bytes_ref(plain.as_ptr()), b"hello hello hello");
            let mut input = input;
            for v in [
                &mut input,
                packed.as_mut_ptr().as_mut().unwrap(),
                plain.as_mut_ptr().as_mut().unwrap(),
            ] {
                ms_rt::vec::msrt_bytes_drop(v);
            }
            ms_std_core::str_release(&f);
        }
    }

    #[test]
    fn stream_roundtrip() {
        let f = new_string("gzip");
        let mut enc = MaybeUninit::<*mut ObjCell<EncoderObj>>::uninit();
        let mut dec = MaybeUninit::<*mut ObjCell<DecoderObj>>::uninit();
        let (data, mut chunk, mut plain) = (bytes(b"hello hello hello"), blank(), blank());
        // SAFETY: all pointers are live; handles are released at the end.
        unsafe {
            assert_eq!(
                msrt_compress_encoder_new(&f, 10, enc.as_mut_ptr()),
                ms_std_core::STATUS_INVALID_INPUT
            );
            assert_eq!(msrt_compress_encoder_new(&f, 6, enc.as_mut_ptr()), 0);
            let enc = enc.assume_init();
            msrt_compress_encoder_feed(enc, &data);
            msrt_compress_encoder_finish(enc);
            assert_eq!(msrt_compress_encoder_is_finished(enc), 1);
            msrt_compress_encoder_take(enc, 1 << 20, chunk.as_mut_ptr());
            assert_eq!(msrt_compress_decoder_new(&f, 0, 0, dec.as_mut_ptr()), 0);
            let dec = dec.assume_init();
            assert_eq!(
                msrt_compress_decoder_poll(dec, 100, plain.as_mut_ptr()),
                POLL_NEED_INPUT
            );
            msrt_compress_decoder_feed(dec, chunk.as_ptr());
            assert_eq!(msrt_compress_decoder_poll(dec, 100, plain.as_mut_ptr()), 0);
            assert_eq!(bytes_ref(plain.as_ptr()), b"hello hello hello");
            assert_eq!(
                msrt_compress_decoder_poll(dec, 100, plain.as_mut_ptr()),
                POLL_NEED_INPUT
            );
            msrt_compress_decoder_finish_input(dec);
            assert_eq!(
                msrt_compress_decoder_poll(dec, 100, plain.as_mut_ptr()),
                POLL_DONE
            );
            ms_rt::obj::msrt_release(enc.cast());
            ms_rt::obj::msrt_release(dec.cast());
        }
    }
}
