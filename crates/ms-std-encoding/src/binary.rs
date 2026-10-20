//! Natives for `@std/binary.ms`: fixed-width integers and binary64 floats in either byte order.
//! Symbols are `msrt_binary_<function>`; fallible ones return a status byte and write the ok value
//! through `out` only on success.

use alloc::vec::Vec;
use ms_std_core::{Out, STATUS_INVALID_INPUT, STATUS_OUT_OF_RANGE, StatusCode, native};

/// The `width` bytes at `offset`, when they exist.
fn chunk(data: &[u8], offset: i64, width: usize) -> Option<&[u8]> {
    let start = usize::try_from(offset).ok()?;
    data.get(start..start.checked_add(width)?)
}

native! {
    /// `binary.read_integer`: `width` is 1, 2, 4 or 8; the value must fit an `Int`.
    fn msrt_binary_read_integer(
        data: &[u8],
        offset: i64,
        width: i64,
        signed: bool,
        little: bool,
        out: Out<i64>,
    ) -> Result<(), StatusCode> {
        if !matches!(width, 1 | 2 | 4 | 8) {
            return Err(StatusCode(STATUS_INVALID_INPUT));
        }
        let width = width as usize;
        let Some(chunk) = chunk(data, offset, width) else {
            return Err(StatusCode(STATUS_OUT_OF_RANGE));
        };
        let mut n = 0u64;
        if little {
            for b in chunk.iter().rev() {
                n = n << 8 | u64::from(*b);
            }
        } else {
            for b in chunk {
                n = n << 8 | u64::from(*b);
            }
        }
        if signed {
            if width < 8 && n & (1 << (width * 8 - 1)) != 0 {
                n |= u64::MAX << (width * 8);
            }
        } else if n > i64::MAX as u64 {
            return Err(StatusCode(STATUS_OUT_OF_RANGE));
        }
        out.write(n as i64);
        Ok(())
    }

    /// `binary.read_float`: binary64 at `offset`.
    fn msrt_binary_read_float(
        data: &[u8],
        offset: i64,
        little: bool,
        out: Out<f64>,
    ) -> Result<(), StatusCode> {
        let Some(chunk) = chunk(data, offset, 8) else {
            return Err(StatusCode(STATUS_OUT_OF_RANGE));
        };
        let raw: [u8; 8] = chunk.try_into().expect("eight bytes");
        let bits = if little {
            u64::from_le_bytes(raw)
        } else {
            u64::from_be_bytes(raw)
        };
        out.write(f64::from_bits(bits));
        Ok(())
    }

    /// `binary.write_integer`: the low `width` bytes, an error when the value does not fit.
    fn msrt_binary_write_integer(
        value: i64,
        width: i64,
        signed: bool,
        little: bool,
        out: Out<Vec<u8>>,
    ) -> Result<(), StatusCode> {
        if !matches!(width, 1 | 2 | 4 | 8) {
            return Err(StatusCode(STATUS_INVALID_INPUT));
        }
        let width = width as usize;
        let fits = if !signed && value < 0 {
            false
        } else if width == 8 {
            true
        } else if signed {
            let limit = 1i64 << (width * 8 - 1);
            (-limit..limit).contains(&value)
        } else {
            (value as u64) < (1u64 << (width * 8))
        };
        if !fits {
            return Err(StatusCode(STATUS_OUT_OF_RANGE));
        }
        let le = (value as u64).to_le_bytes();
        let mut bytes = [0u8; 8];
        for i in 0..width {
            bytes[if little { i } else { width - 1 - i }] = le[i];
        }
        out.write(bytes[..width].to_vec());
        Ok(())
    }

    /// `binary.write_float`: binary64 as eight bytes.
    fn msrt_binary_write_float(value: f64, little: bool, out: Out<Vec<u8>>) -> () {
        let bits = if little {
            value.to_bits().to_le_bytes()
        } else {
            value.to_bits().to_be_bytes()
        };
        out.write(bits.to_vec());
    }
}
