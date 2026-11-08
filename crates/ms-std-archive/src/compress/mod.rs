//! gzip, zlib and raw deflate with the framing, checks and error
//! mapping. The compressed bytes are produced by miniz_oxide.
pub mod ffi;

use alloc::boxed::Box;
use alloc::vec::Vec;
use miniz_oxide::deflate::compress_to_vec;
use miniz_oxide::deflate::core::{
    CompressorOxide, TDEFLFlush, TDEFLStatus, compress as deflate_step,
    create_comp_flags_from_zip_params,
};
use miniz_oxide::inflate::TINFLStatus;
use miniz_oxide::inflate::core::{
    DecompressorOxide, TINFL_LZ_DICT_SIZE, decompress, inflate_flags,
};
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

pub use ms_std_core::checksum::{adler32, adler32_update};

/// CRC-32 (IEEE) of `data`, continuing from `crc`.
pub use ms_std_core::checksum::crc32_update as crc32;

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

/// Decompresses exactly one gzip/zlib/deflate payload (gzip members may be concatenated); trailing
/// bytes are `InvalidData`, and `max_bytes` bounds the cumulative output. This is the streaming
/// `Decoder` run over `data`, so the two calls cannot disagree.
pub fn decompress_bytes(
    data: &[u8],
    format: &str,
    max_bytes: Option<i64>,
) -> Result<Vec<u8>, Fail> {
    if max_bytes.is_some_and(|n| n < 0) {
        return Err(Fail::InvalidInput);
    }
    let mut decoder = Decoder::new(
        Format::from_name(format).ok_or(Fail::Unsupported)?,
        max_bytes,
    );
    let mut out = Vec::new();
    // Chunked so the decoder's input buffer is drained a bounded amount at a time.
    for chunk in data.chunks(1 << 16) {
        out.extend(decoder.push(chunk)?);
    }
    out.extend(decoder.end()?);
    Ok(out)
}

// ---- incremental coding ----
//
// Push codecs behind the `compressed` and `decompressed` stream steps: the caller feeds chunks and receives the
// output each one completes. Malformed data is `InvalidData`, exceeding `max_bytes` is `LimitExceeded`, and an
// out-of-range level is `InvalidInput`.

/// Output room per inflate call, beyond the history window.
const WINDOW_ROOM: usize = 1 << 16;

enum Header {
    Need,
    Bad,
    Len(usize),
}

/// Reads a gzip member header from the start of `d`.
fn gzip_header(d: &[u8]) -> Header {
    if d.len() < 10 {
        return Header::Need;
    }
    if d[0] != 0x1f || d[1] != 0x8b || d[2] != 8 {
        return Header::Bad;
    }
    let flg = d[3];
    let mut pos = 10;
    if flg & 4 != 0 {
        let Some(len) = d.get(pos..pos + 2) else {
            return Header::Need;
        };
        pos += 2 + usize::from(u16::from_le_bytes([len[0], len[1]]));
        if d.len() < pos {
            return Header::Need;
        }
    }
    for bit in [8u8, 16] {
        if flg & bit != 0 {
            // A zero-terminated string of at most 512 bytes including the terminator.
            let rest = &d[pos..];
            match rest.iter().take(512).position(|&b| b == 0) {
                Some(i) => pos += i + 1,
                None if rest.len() < 512 => return Header::Need,
                None => return Header::Bad,
            }
        }
    }
    if flg & 2 != 0 {
        let Some(sum) = d.get(pos..pos + 2) else {
            return Header::Need;
        };
        if u16::from_le_bytes([sum[0], sum[1]]) != crc32(0, &d[..pos]) as u16 {
            return Header::Bad;
        }
        pos += 2;
    }
    Header::Len(pos)
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Phase {
    Header,
    Body,
    Trailer,
    Done,
}

pub struct Decoder {
    format: Format,
    max: i64,
    total: i64,
    input: Vec<u8>,
    eof: bool,
    phase: Phase,
    /// Gzip members completed so far.
    members: usize,
    inflate: Box<DecompressorOxide>,
    /// The last `hist` output bytes followed by room for the next call's output. Inflating into a
    /// non-wrapping buffer makes a distance that reaches before the start of the output an error.
    window: Vec<u8>,
    hist: usize,
    /// Running check of the current payload: CRC-32 (gzip) or Adler-32 (zlib).
    check: u32,
    size: u32,
    failed: Option<Fail>,
}

impl Decoder {
    /// `max_bytes` bounds the total output; a negative bound fails on the first output byte.
    pub fn new(format: Format, max_bytes: Option<i64>) -> Decoder {
        Decoder {
            format,
            max: max_bytes.unwrap_or(i64::MAX),
            total: 0,
            input: Vec::new(),
            eof: false,
            phase: if format == Format::Deflate {
                Phase::Body
            } else {
                Phase::Header
            },
            members: 0,
            inflate: Box::new(DecompressorOxide::new()),
            window: alloc::vec![0; TINFL_LZ_DICT_SIZE + WINDOW_ROOM],
            hist: 0,
            check: 0,
            size: 0,
            failed: None,
        }
    }

    /// Feeds a chunk and returns the output it completes, empty while more input is needed.
    pub fn push(&mut self, data: &[u8]) -> Result<Vec<u8>, Fail> {
        self.input.extend_from_slice(data);
        self.run()
    }

    /// Ends the input and returns the rest of the output; input that ends inside the format is `InvalidData`.
    pub fn end(&mut self) -> Result<Vec<u8>, Fail> {
        self.eof = true;
        self.run()
    }

    /// Decodes as far as the buffered input allows. After an error every later call repeats it.
    fn run(&mut self) -> Result<Vec<u8>, Fail> {
        if let Some(e) = self.failed {
            return Err(e);
        }
        let mut out = Vec::new();
        let r = self.step(&mut out);
        if let Err(e) = r {
            self.failed = Some(e);
            return Err(e);
        }
        Ok(out)
    }

    /// Stops when the decoder needs input the caller has not given (an error once the input ended) or is done.
    fn step(&mut self, out: &mut Vec<u8>) -> Result<(), Fail> {
        loop {
            match self.phase {
                // Nothing may follow the payload, whether it arrived with it or in a later chunk.
                Phase::Done if self.input.is_empty() => return Ok(()),
                Phase::Done => return Err(Fail::InvalidData),
                Phase::Header => {
                    if self.format == Format::Zlib {
                        if self.input.len() < 2 {
                            return self.need_input();
                        }
                        let (b0, b1) = (self.input[0], self.input[1]);
                        let h = u16::from_be_bytes([b0, b1]);
                        if b0 & 0x0f != 8 || b0 >> 4 > 7 || !h.is_multiple_of(31) || b1 & 0x20 != 0
                        {
                            return Err(Fail::InvalidData);
                        }
                        self.input.drain(..2);
                        self.check = 1;
                    } else {
                        // A clean end of input between members finishes a gzip stream.
                        if self.members > 0 && self.input.is_empty() && self.eof {
                            self.phase = Phase::Done;
                            continue;
                        }
                        match gzip_header(&self.input) {
                            Header::Need => return self.need_input(),
                            Header::Bad => return Err(Fail::InvalidData),
                            Header::Len(n) => {
                                self.input.drain(..n);
                                self.check = 0;
                            }
                        }
                    }
                    self.size = 0;
                    *self.inflate = DecompressorOxide::new();
                    self.hist = 0;
                    self.phase = Phase::Body;
                }
                Phase::Body => {
                    let mut flags = inflate_flags::TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF;
                    if !self.eof {
                        flags |= inflate_flags::TINFL_FLAG_HAS_MORE_INPUT;
                    }
                    let (status, used, made) = decompress(
                        &mut self.inflate,
                        &self.input,
                        &mut self.window[..],
                        self.hist,
                        flags,
                    );
                    self.input.drain(..used);
                    let produced = &self.window[self.hist..self.hist + made];
                    match self.format {
                        Format::Gzip => self.check = crc32(self.check, produced),
                        Format::Zlib => self.check = adler32_update(self.check, produced),
                        Format::Deflate => {}
                    }
                    self.size = self.size.wrapping_add(made as u32);
                    self.total = self.total.saturating_add(made as i64);
                    if made > 0 && self.total > self.max {
                        return Err(Fail::LimitExceeded);
                    }
                    out.extend_from_slice(produced);
                    let end = self.hist + made;
                    if end > TINFL_LZ_DICT_SIZE {
                        self.window.copy_within(end - TINFL_LZ_DICT_SIZE..end, 0);
                        self.hist = TINFL_LZ_DICT_SIZE;
                    } else {
                        self.hist = end;
                    }
                    match status {
                        TINFLStatus::Done => {
                            self.phase = if self.format == Format::Deflate {
                                Phase::Done
                            } else {
                                Phase::Trailer
                            };
                        }
                        TINFLStatus::NeedsMoreInput if made == 0 => return self.need_input(),
                        TINFLStatus::NeedsMoreInput | TINFLStatus::HasMoreOutput => {}
                        _ => return Err(Fail::InvalidData),
                    }
                }
                Phase::Trailer => {
                    let n = if self.format == Format::Gzip { 8 } else { 4 };
                    if self.input.len() < n {
                        return self.need_input();
                    }
                    let t = &self.input[..n];
                    let ok = if self.format == Format::Gzip {
                        u32::from_le_bytes([t[0], t[1], t[2], t[3]]) == self.check
                            && u32::from_le_bytes([t[4], t[5], t[6], t[7]]) == self.size
                    } else {
                        u32::from_be_bytes([t[0], t[1], t[2], t[3]]) == self.check
                    };
                    if !ok {
                        return Err(Fail::InvalidData);
                    }
                    self.input.drain(..n);
                    if self.format == Format::Gzip {
                        self.members += 1;
                        self.phase = Phase::Header;
                    } else {
                        self.phase = Phase::Done;
                    }
                }
            }
        }
    }

    /// The decoder cannot go on without input: wait for the next chunk, or fail when none can come.
    fn need_input(&self) -> Result<(), Fail> {
        if self.eof {
            Err(Fail::InvalidData)
        } else {
            Ok(())
        }
    }
}

pub struct Encoder {
    format: Format,
    comp: Box<CompressorOxide>,
    out: Vec<u8>,
    check: u32,
    size: u32,
    started: bool,
    finished: bool,
    level: u8,
}

impl Encoder {
    /// `level` is 0 through 9, otherwise `InvalidInput`.
    pub fn new(format: Format, level: i64) -> Result<Encoder, Fail> {
        if !(0..=9).contains(&level) {
            return Err(Fail::InvalidInput);
        }
        let flags = create_comp_flags_from_zip_params(level as i32, -15, 0);
        Ok(Encoder {
            format,
            comp: Box::new(CompressorOxide::new(flags)),
            out: Vec::new(),
            check: if format == Format::Zlib { 1 } else { 0 },
            size: 0,
            started: false,
            finished: false,
            level: level as u8,
        })
    }

    fn header(&mut self) {
        if self.started {
            return;
        }
        self.started = true;
        match self.format {
            Format::Deflate => {}
            Format::Zlib => {
                let flevel: u16 = match self.level {
                    0 | 1 => 0,
                    2..=5 => 1,
                    6 => 2,
                    _ => 3,
                };
                let mut h: u16 = 0x7800 | flevel << 6;
                h += 31 - h % 31;
                self.out.extend_from_slice(&h.to_be_bytes());
            }
            Format::Gzip => {
                let xfl = match self.level {
                    9 => 2,
                    1 => 4,
                    _ => 0,
                };
                self.out
                    .extend_from_slice(&[0x1f, 0x8b, 8, 0, 0, 0, 0, 0, xfl, 255]);
            }
        }
    }

    fn run(&mut self, mut data: &[u8], flush: TDEFLFlush) {
        let mut buf = [0u8; 16 * 1024];
        loop {
            let (status, used, made) = deflate_step(&mut self.comp, data, &mut buf, flush);
            data = &data[used..];
            self.out.extend_from_slice(&buf[..made]);
            let more =
                matches!(status, TDEFLStatus::Okay) && (!data.is_empty() || made == buf.len());
            if !more {
                return;
            }
        }
    }

    /// Compresses a chunk and returns the bytes it completes, possibly none.
    pub fn push(&mut self, data: &[u8]) -> Vec<u8> {
        if self.finished {
            return Vec::new();
        }
        self.header();
        match self.format {
            Format::Gzip => self.check = crc32(self.check, data),
            Format::Zlib => self.check = adler32_update(self.check, data),
            Format::Deflate => {}
        }
        self.size = self.size.wrapping_add(data.len() as u32);
        self.run(data, TDEFLFlush::None);
        core::mem::take(&mut self.out)
    }

    /// The input ended: flushes the compressor, writes the trailer and returns the remaining bytes.
    pub fn end(&mut self) -> Vec<u8> {
        if self.finished {
            return Vec::new();
        }
        self.header();
        self.finished = true;
        let mut buf = [0u8; 16 * 1024];
        loop {
            let (status, _, made) = deflate_step(&mut self.comp, &[], &mut buf, TDEFLFlush::Finish);
            self.out.extend_from_slice(&buf[..made]);
            if status != TDEFLStatus::Okay {
                break;
            }
        }
        match self.format {
            Format::Deflate => {}
            Format::Zlib => self.out.extend_from_slice(&self.check.to_be_bytes()),
            Format::Gzip => {
                self.out.extend_from_slice(&self.check.to_le_bytes());
                self.out.extend_from_slice(&self.size.to_le_bytes());
            }
        }
        core::mem::take(&mut self.out)
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
    fn stream_decoder_rejects_bytes_after_the_payload() {
        for f in [Format::Zlib, Format::Deflate, Format::Gzip] {
            let name = match f {
                Format::Zlib => "zlib",
                Format::Deflate => "deflate",
                Format::Gzip => "gzip",
            };
            let packed = compress(TEXT, name, 6, None).unwrap();
            let mut with_tail = packed.clone();
            with_tail.extend_from_slice(b"tail");

            let mut d = Decoder::new(f, None);
            let r = d.push(&with_tail).and_then(|_| d.end());
            assert_eq!(r, Err(Fail::InvalidData), "{name} joined");

            let mut d = Decoder::new(f, None);
            let mut r = d.push(&packed);
            if r.is_ok() {
                r = d.push(b"x");
            }
            if r.is_ok() {
                r = d.end();
            }
            assert_eq!(r, Err(Fail::InvalidData), "{name} later chunk");

            let mut d = Decoder::new(f, None);
            let mut got = d.push(&packed).unwrap();
            got.extend(d.end().unwrap());
            assert_eq!(got, TEXT, "{name} clean");
        }
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
