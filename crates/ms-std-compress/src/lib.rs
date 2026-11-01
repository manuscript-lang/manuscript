//! `@std/io/archive.ms` natives: gzip, zlib and raw deflate with the framing, checks and error
//! mapping. The compressed bytes are produced by miniz_oxide.
#![no_std]

// Links the msrt_* runtime symbols into this crate's test binaries.
#[cfg(test)]
use ms_rt as _;

extern crate alloc;

pub mod ffi;
pub mod stream;

use alloc::vec::Vec;
use miniz_oxide::deflate::compress_to_vec;
use miniz_oxide::inflate::TINFLStatus;
use miniz_oxide::inflate::core::{DecompressorOxide, decompress, inflate_flags};
use ms_rt::ffi::Fail;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Format {
    Gzip,
    Zlib,
    Deflate,
}

impl Format {
    /// Parses exactly `"gzip"`, `"zlib"` or `"deflate"`.
    pub fn from_name(name: &str) -> Option<Format> {
        match name {
            "gzip" => Some(Format::Gzip),
            "zlib" => Some(Format::Zlib),
            "deflate" => Some(Format::Deflate),
            _ => None,
        }
    }
}

const CRC_TABLE: [u32; 256] = {
    let mut t = [0u32; 256];
    let mut i = 0;
    while i < 256 {
        let mut c = i as u32;
        let mut k = 0;
        while k < 8 {
            c = if c & 1 != 0 {
                0xedb8_8320 ^ (c >> 1)
            } else {
                c >> 1
            };
            k += 1;
        }
        t[i] = c;
        i += 1;
    }
    t
};

/// CRC-32 (IEEE) of `data`, continuing from `crc`.
pub fn crc32(crc: u32, data: &[u8]) -> u32 {
    let mut c = !crc;
    for &b in data {
        c = CRC_TABLE[((c ^ u32::from(b)) & 0xff) as usize] ^ (c >> 8);
    }
    !c
}

/// Adler-32 of `data`.
pub fn adler32(data: &[u8]) -> u32 {
    adler32_update(1, data)
}

/// Adler-32 of `data`, continuing from `adler` (1 for an empty prefix).
pub fn adler32_update(adler: u32, data: &[u8]) -> u32 {
    let (mut a, mut b) = (adler & 0xffff, adler >> 16);
    for chunk in data.chunks(5552) {
        for &d in chunk {
            a += u32::from(d);
            b += a;
        }
        a %= 65521;
        b %= 65521;
    }
    b << 16 | a
}

/// Compresses `data`; `level` is 0..=9 and `max_bytes` bounds the encoded size.
pub fn compress(
    data: &[u8],
    format: &str,
    level: i64,
    max_bytes: Option<i64>,
) -> Result<Vec<u8>, Fail> {
    let max = match max_bytes {
        None => usize::MAX,
        Some(n) if n < 0 => return Err(Fail::InvalidInput),
        Some(n) => n as usize,
    };
    if !(0..=9).contains(&level) {
        return Err(Fail::InvalidInput);
    }
    let format = Format::from_name(format).ok_or(Fail::Unsupported)?;
    let out = encode(data, format, level as u8);
    if out.len() > max {
        return Err(Fail::LimitExceeded);
    }
    Ok(out)
}

/// Encodes with the headers Go writes (gzip: no name or time, OS 255).
pub fn encode(data: &[u8], format: Format, level: u8) -> Vec<u8> {
    let body = compress_to_vec(data, level);
    match format {
        Format::Deflate => body,
        Format::Zlib => {
            let flevel: u16 = match level {
                0 | 1 => 0,
                2..=5 => 1,
                6 => 2,
                _ => 3,
            };
            let mut h: u16 = 0x7800 | flevel << 6;
            h += 31 - h % 31;
            let mut out = Vec::with_capacity(body.len() + 6);
            out.extend_from_slice(&h.to_be_bytes());
            out.extend_from_slice(&body);
            out.extend_from_slice(&adler32(data).to_be_bytes());
            out
        }
        Format::Gzip => {
            let xfl = match level {
                9 => 2,
                1 => 4,
                _ => 0,
            };
            let mut out = Vec::with_capacity(body.len() + 18);
            out.extend_from_slice(&[0x1f, 0x8b, 8, 0, 0, 0, 0, 0, xfl, 255]);
            out.extend_from_slice(&body);
            out.extend_from_slice(&crc32(0, data).to_le_bytes());
            out.extend_from_slice(&(data.len() as u32).to_le_bytes());
            out
        }
    }
}

/// Inflates one raw deflate stream from the start of `input`, producing at most `room` bytes.
/// Returns the output and the number of input bytes the stream occupied.
pub fn inflate(input: &[u8], room: usize) -> Result<(Vec<u8>, usize), Fail> {
    let limit = room.saturating_add(1);
    let mut out: Vec<u8> =
        alloc::vec![0; input.len().saturating_mul(4).clamp(1024, 1 << 20).min(limit)];
    let mut state = DecompressorOxide::new();
    let (mut in_pos, mut out_pos) = (0usize, 0usize);
    loop {
        let (status, used, made) = decompress(
            &mut state,
            &input[in_pos..],
            &mut out,
            out_pos,
            inflate_flags::TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF,
        );
        in_pos += used;
        out_pos += made;
        match status {
            TINFLStatus::Done => {
                if out_pos > room {
                    return Err(Fail::LimitExceeded);
                }
                out.truncate(out_pos);
                return Ok((out, in_pos));
            }
            TINFLStatus::HasMoreOutput => {
                if out.len() >= limit {
                    return Err(Fail::LimitExceeded);
                }
                let grown = out.len().saturating_mul(2).min(limit);
                out.resize(grown, 0);
            }
            _ => return Err(Fail::InvalidData),
        }
    }
}

fn gzip_header_len(data: &[u8]) -> Result<usize, Fail> {
    if data.len() < 10 || data[0] != 0x1f || data[1] != 0x8b || data[2] != 8 {
        return Err(Fail::InvalidData);
    }
    let flg = data[3];
    let mut pos = 10;
    let take = |pos: &mut usize, n: usize| -> Result<(), Fail> {
        if data.len() < *pos + n {
            return Err(Fail::InvalidData);
        }
        *pos += n;
        Ok(())
    };
    if flg & 4 != 0 {
        if data.len() < pos + 2 {
            return Err(Fail::InvalidData);
        }
        let n = usize::from(u16::from_le_bytes([data[pos], data[pos + 1]]));
        take(&mut pos, 2 + n)?;
    }
    for bit in [8u8, 16] {
        if flg & bit != 0 {
            // A zero-terminated string of at most 512 bytes including the terminator.
            let rest = &data[pos..];
            match rest.iter().take(512).position(|&b| b == 0) {
                Some(i) => pos += i + 1,
                None => return Err(Fail::InvalidData),
            }
        }
    }
    if flg & 2 != 0 {
        if data.len() < pos + 2 {
            return Err(Fail::InvalidData);
        }
        if u16::from_le_bytes([data[pos], data[pos + 1]]) != crc32(0, &data[..pos]) as u16 {
            return Err(Fail::InvalidData);
        }
        pos += 2;
    }
    Ok(pos)
}

/// Decompresses exactly one gzip/zlib/deflate payload (gzip members may be concatenated); trailing
/// bytes are `InvalidData`, and `max_bytes` bounds the cumulative output.
pub fn decompress_bytes(
    data: &[u8],
    format: &str,
    max_bytes: Option<i64>,
) -> Result<Vec<u8>, Fail> {
    let max = match max_bytes {
        None => usize::MAX,
        Some(n) if n < 0 => return Err(Fail::InvalidInput),
        Some(n) => n as usize,
    };
    match Format::from_name(format).ok_or(Fail::Unsupported)? {
        Format::Deflate => {
            let (out, used) = inflate(data, max)?;
            if used != data.len() {
                return Err(Fail::InvalidData);
            }
            Ok(out)
        }
        Format::Zlib => {
            if data.len() < 2 {
                return Err(Fail::InvalidData);
            }
            let h = u16::from_be_bytes([data[0], data[1]]);
            if data[0] & 0x0f != 8
                || data[0] >> 4 > 7
                || !h.is_multiple_of(31)
                || data[1] & 0x20 != 0
            {
                return Err(Fail::InvalidData);
            }
            let (out, used) = inflate(&data[2..], max)?;
            let tail = &data[2 + used..];
            if tail.len() != 4
                || u32::from_be_bytes([tail[0], tail[1], tail[2], tail[3]]) != adler32(&out)
            {
                return Err(Fail::InvalidData);
            }
            Ok(out)
        }
        Format::Gzip => {
            let mut out: Vec<u8> = Vec::new();
            let mut pos = 0;
            loop {
                pos += gzip_header_len(&data[pos..])?;
                let (member, used) = inflate(&data[pos..], max - out.len())?;
                pos += used;
                let foot = data.get(pos..pos + 8).ok_or(Fail::InvalidData)?;
                let crc = u32::from_le_bytes([foot[0], foot[1], foot[2], foot[3]]);
                let size = u32::from_le_bytes([foot[4], foot[5], foot[6], foot[7]]);
                if crc != crc32(0, &member) || size != member.len() as u32 {
                    return Err(Fail::InvalidData);
                }
                pos += 8;
                out.extend_from_slice(&member);
                if pos == data.len() {
                    return Ok(out);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    extern crate std;
    use super::*;
    use alloc::string::ToString;

    const TEXT: &[u8] = b"hello hello hello";

    #[test]
    fn roundtrips() {
        for f in ["gzip", "zlib", "deflate"] {
            for level in 0..=9 {
                let packed = compress(TEXT, f, level, None).unwrap();
                assert_eq!(
                    decompress_bytes(&packed, f, None).unwrap(),
                    TEXT,
                    "{f} {level}"
                );
            }
            let packed = compress(&[], f, 6, None).unwrap();
            assert!(decompress_bytes(&packed, f, None).unwrap().is_empty());
            let big: Vec<u8> = (0..200_000u32).map(|i| (i % 251) as u8).collect();
            let packed = compress(&big, f, 6, None).unwrap();
            assert_eq!(decompress_bytes(&packed, f, None).unwrap(), big);
        }
    }

    #[test]
    fn limits_and_errors() {
        for f in ["gzip", "zlib", "deflate"] {
            let packed = compress(TEXT, f, 6, None).unwrap();
            assert_eq!(decompress_bytes(&packed, f, Some(17)).unwrap(), TEXT);
            assert_eq!(
                decompress_bytes(&packed, f, Some(16)),
                Err(Fail::LimitExceeded)
            );
            assert_eq!(
                decompress_bytes(&packed, f, Some(-1)),
                Err(Fail::InvalidInput)
            );
            assert_eq!(
                compress(TEXT, f, 6, Some(packed.len() as i64 - 1)),
                Err(Fail::LimitExceeded)
            );
            assert!(compress(TEXT, f, 6, Some(packed.len() as i64)).is_ok());
            assert_eq!(compress(TEXT, f, 10, None), Err(Fail::InvalidInput));
            assert_eq!(compress(TEXT, f, -1, None), Err(Fail::InvalidInput));
            let mut trailing = packed.clone();
            trailing.push(0);
            assert_eq!(decompress_bytes(&trailing, f, None), Err(Fail::InvalidData));
            assert_eq!(
                decompress_bytes(&packed[..packed.len() - 1], f, None),
                Err(Fail::InvalidData)
            );
            assert_eq!(decompress_bytes(b"", f, None), Err(Fail::InvalidData));
        }
        assert_eq!(compress(TEXT, "bz2", 6, None), Err(Fail::Unsupported));
        assert_eq!(decompress_bytes(TEXT, "gzip", None), Err(Fail::InvalidData));
        assert_eq!(decompress_bytes(TEXT, "bz2", None), Err(Fail::Unsupported));
    }

    #[test]
    fn gzip_header_and_multistream() {
        let a = compress(b"abc", "gzip", 6, None).unwrap();
        assert_eq!(&a[..4], &[0x1f, 0x8b, 8, 0]);
        assert_eq!(a[9], 255);
        let b = compress(b"def", "gzip", 6, None).unwrap();
        let both = [a.clone(), b].concat();
        assert_eq!(decompress_bytes(&both, "gzip", None).unwrap(), b"abcdef");
        assert_eq!(
            decompress_bytes(&both, "gzip", Some(5)),
            Err(Fail::LimitExceeded)
        );
        let mut bad = a.clone();
        let n = bad.len();
        bad[n - 5] ^= 1;
        assert_eq!(decompress_bytes(&bad, "gzip", None), Err(Fail::InvalidData));
        let z = compress(b"abc", "zlib", 6, None).unwrap();
        assert_eq!(&z[..2], &[0x78, 0x9c]);
        assert_eq!(adler32(b"Wikipedia"), 0x11E6_0398);
        assert_eq!(crc32(0, b"123456789"), 0xCBF4_3926);
        let _ = "".to_string();
    }
}
