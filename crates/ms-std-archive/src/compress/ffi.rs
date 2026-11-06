//! C ABI shims for `@std/io/archive.ms` (`msstd_compress_*`). The format is passed by name
//! (`"gzip"`, `"zlib"`, `"deflate"`); `compress` and `decompress` pass the case name.
//! Statuses: `STATUS_INVALID_INPUT`, `STATUS_INVALID_DATA`, `STATUS_LIMIT_EXCEEDED` and
//! `STATUS_UNSUPPORTED` (9); `Failed(message)` is never produced.

use super::Format;
use super::{Decoder, Encoder};
use alloc::vec::Vec;
use core::cell::RefCell;
use ms_rt::ffi::{Fail, Has, ObjRef, Object, Out, abi_handle, native};

// A stream codec is a runtime handle with one owner. The generated code owns the input `ReadStream` and the
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
        has_max: Has,
        max: i64,
    ) -> Result<Vec<u8>, Fail> {
        super::compress(data, format, level, has_max.then_some(max))
    }

    fn msstd_compress_decompress(
        data: &[u8],
        format: &str,
        has_max: Has,
        max: i64,
    ) -> Result<Vec<u8>, Fail> {
        super::decompress_bytes(data, format, has_max.then_some(max))
    }

    fn msstd_compress_decoder_new(
        name: &str,
        has_max: Has,
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
    fn msstd_compress_decoder_push(decoder: ObjRef<DecoderObj>, data: &[u8]) -> Result<Vec<u8>, Fail> {
        decoder.codec.borrow_mut().push(data)
    }

    // Ends the input and returns the rest of the output; input that ends inside the format is `InvalidData`.
    fn msstd_compress_decoder_end(decoder: ObjRef<DecoderObj>) -> Result<Vec<u8>, Fail> {
        decoder.codec.borrow_mut().end()
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
        e.codec.borrow_mut().push(data)
    }

    // Finishes the stream and returns the remaining compressed bytes.
    fn msstd_compress_encoder_end(e: ObjRef<EncoderObj>) -> out Vec<u8> {
        e.codec.borrow_mut().end()
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
                msstd_compress_compress(
                    &input,
                    &f,
                    6,
                    ms_rt::ffi::HasRaw(0),
                    0,
                    packed.as_mut_ptr()
                ),
                0
            );
            assert_eq!(
                msstd_compress_decompress(
                    packed.as_ptr(),
                    &f,
                    ms_rt::ffi::HasRaw(1),
                    16,
                    plain.as_mut_ptr()
                ),
                ms_rt::ffi::STATUS_LIMIT_EXCEEDED
            );
            assert_eq!(
                msstd_compress_decompress(
                    packed.as_ptr(),
                    &f,
                    ms_rt::ffi::HasRaw(0),
                    0,
                    plain.as_mut_ptr()
                ),
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

    #[test]
    fn push_roundtrip() {
        let f = new_string("gzip");
        let mut enc = MaybeUninit::<*mut ObjCell<EncoderObj>>::uninit();
        let mut dec = MaybeUninit::<*mut ObjCell<DecoderObj>>::uninit();
        let (data, mut head, mut tail, mut plain) =
            (bytes(b"hello hello hello"), blank(), blank(), blank());
        // SAFETY: all pointers are live; handles are released at the end.
        unsafe {
            assert_eq!(
                msstd_compress_encoder_new(&f, 10, enc.as_mut_ptr()),
                ms_rt::ffi::STATUS_INVALID_INPUT
            );
            assert_eq!(msstd_compress_encoder_new(&f, 6, enc.as_mut_ptr()), 0);
            let enc = enc.assume_init();
            msstd_compress_encoder_push(enc, &data, head.as_mut_ptr());
            msstd_compress_encoder_end(enc, tail.as_mut_ptr());
            let packed = [bytes_ref(head.as_ptr()), bytes_ref(tail.as_ptr())].concat();
            assert_eq!(
                msstd_compress_decoder_new(&f, ms_rt::ffi::HasRaw(0), 0, dec.as_mut_ptr()),
                0
            );
            let dec = dec.assume_init();
            let chunk = bytes(&packed);
            assert_eq!(
                msstd_compress_decoder_push(dec, &chunk, plain.as_mut_ptr()),
                0
            );
            assert_eq!(bytes_ref(plain.as_ptr()), b"hello hello hello");
            assert_eq!(msstd_compress_decoder_end(dec, plain.as_mut_ptr()), 0);
            ms_rt::obj::msrt_obj_drop(enc.cast());
            ms_rt::obj::msrt_obj_drop(dec.cast());
        }
    }
}
