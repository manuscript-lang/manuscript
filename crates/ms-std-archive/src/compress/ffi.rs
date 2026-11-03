//! C ABI shims for `@std/io/archive.ms` (`msstd_compress_*`). The format is passed by name
//! (`"gzip"`, `"zlib"`, `"deflate"`); `CompressionFormat` methods pass the matching constant.
//! Statuses: `STATUS_INVALID_INPUT`, `STATUS_INVALID_DATA`, `STATUS_LIMIT_EXCEEDED` and
//! `STATUS_UNSUPPORTED` (9); `Failed(message)` is never produced.

use super::Format;
use super::stream::{Decoder, Encoder, Poll};
use alloc::vec::Vec;
use core::cell::RefCell;
use ms_rt::ffi::{Fail, ObjRef, Object, Out, abi_handle, native};

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
    fn msstd_compress_compress(
        data: &[u8],
        format: &str,
        level: i64,
        has_max: bool,
        max: i64,
    ) -> Result<Vec<u8>, Fail> {
        super::compress(data, format, level, has_max.then_some(max))
    }

    fn msstd_compress_decompress(
        data: &[u8],
        format: &str,
        has_max: bool,
        max: i64,
    ) -> Result<Vec<u8>, Fail> {
        super::decompress_bytes(data, format, has_max.then_some(max))
    }

    fn msstd_compress_decoder_new(
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

    // Feeds a chunk and returns the output it completes; empty while the codec needs more input.
    fn msstd_compress_decoder_push(d: ObjRef<DecoderObj>, data: &[u8]) -> Result<Vec<u8>, Fail> {
        let mut codec = d.codec.borrow_mut();
        codec.feed(data);
        drain(&mut codec, false)
    }

    // Ends the input and returns the rest of the output; input that ends inside the format is `InvalidData`.
    fn msstd_compress_decoder_end(d: ObjRef<DecoderObj>) -> Result<Vec<u8>, Fail> {
        let mut codec = d.codec.borrow_mut();
        codec.finish_input();
        drain(&mut codec, true)
    }

    fn msstd_compress_encoder_new(
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

    // Feeds a chunk and returns the compressed bytes it completes, possibly none.
    fn msstd_compress_encoder_push(e: ObjRef<EncoderObj>, data: &[u8]) -> out Vec<u8> {
        let mut codec = e.codec.borrow_mut();
        codec.feed(data);
        codec.take(usize::MAX)
    }

    // Finishes the stream and returns the remaining compressed bytes.
    fn msstd_compress_encoder_end(e: ObjRef<EncoderObj>) -> out Vec<u8> {
        let mut codec = e.codec.borrow_mut();
        codec.finish();
        codec.take(usize::MAX)
    }
}

/// Polls the decoder until it needs input (or, after the input ended, until it is done), joining the output.
fn drain(codec: &mut Decoder, ended: bool) -> Result<Vec<u8>, Fail> {
    let mut out = Vec::new();
    loop {
        match codec.poll(1 << 16)? {
            Poll::Output(b) => out.extend_from_slice(&b),
            Poll::Done => return Ok(out),
            Poll::NeedInput if !ended => return Ok(out),
            Poll::NeedInput => return Err(Fail::InvalidData),
        }
    }
}

#[cfg(test)]
#[allow(unsafe_code)]
mod tests {
    use super::*;
    use core::mem::MaybeUninit;
    use ms_rt::ffi::{ObjCell, VecVal, bytes_ref, new_string, write_bytes};

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
                msstd_compress_compress(&input, &f, 6, 0, 0, packed.as_mut_ptr()),
                0
            );
            assert_eq!(
                msstd_compress_decompress(packed.as_ptr(), &f, 1, 16, plain.as_mut_ptr()),
                ms_rt::ffi::STATUS_LIMIT_EXCEEDED
            );
            assert_eq!(
                msstd_compress_decompress(packed.as_ptr(), &f, 0, 0, plain.as_mut_ptr()),
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
            ms_rt::ffi::str_release(&f);
        }
    }
}
