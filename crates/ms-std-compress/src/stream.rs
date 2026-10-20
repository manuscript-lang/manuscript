//! Incremental gzip/zlib/deflate coding behind `compress_stream` and `decompress_stream`.
//!
//! The generated code owns the input `ReadStream`: it pulls chunks and calls [`Decoder::feed`] /
//! [`Decoder::finish_input`] (or [`Encoder::feed`] / [`Encoder::finish`]) and drains the codec
//! with `poll` / `take`. Framing, checks and error mapping are: malformed data is `InvalidData`, exceeding `max_bytes` is
//! `LimitExceeded`, and an out-of-range level is `InvalidInput`.
use crate::{Format, adler32_update, crc32};
use alloc::boxed::Box;
use alloc::vec::Vec;
use miniz_oxide::deflate::core::{
    CompressorOxide, TDEFLFlush, TDEFLStatus, compress, create_comp_flags_from_zip_params,
};
use miniz_oxide::inflate::TINFLStatus;
use miniz_oxide::inflate::core::{
    DecompressorOxide, TINFL_LZ_DICT_SIZE, decompress, inflate_flags,
};
use ms_std_core::Fail;

const _: () = assert!(TINFL_LZ_DICT_SIZE.is_power_of_two());

// ---- decoding ----

/// What a [`Decoder::poll`] produced.
#[derive(Debug, PartialEq, Eq)]
pub enum Poll {
    /// Decoded bytes, at most the requested number.
    Output(Vec<u8>),
    /// The decoder needs more input; call [`Decoder::feed`] or [`Decoder::finish_input`].
    NeedInput,
    /// The stream ended cleanly.
    Done,
}

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
    dict: Box<[u8; TINFL_LZ_DICT_SIZE]>,
    dict_pos: usize,
    /// Running check of the current payload: CRC-32 (gzip) or Adler-32 (zlib).
    check: u32,
    size: u32,
    /// Decoded bytes not yet handed out.
    pending: Vec<u8>,
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
            dict: Box::new([0; TINFL_LZ_DICT_SIZE]),
            dict_pos: 0,
            check: 0,
            size: 0,
            pending: Vec::new(),
            failed: None,
        }
    }

    pub fn feed(&mut self, data: &[u8]) {
        self.input.extend_from_slice(data);
    }

    /// The input stream ended.
    pub fn finish_input(&mut self) {
        self.eof = true;
    }

    /// Returns at most `max` decoded bytes (`max` > 0), or what the decoder needs next. After an
    /// error every later call repeats it.
    pub fn poll(&mut self, max: usize) -> Result<Poll, Fail> {
        if let Some(e) = self.failed {
            return Err(e);
        }
        let r = self.step(max.max(1));
        if let Err(e) = r {
            self.failed = Some(e);
        }
        r
    }

    fn take_pending(&mut self, max: usize) -> Result<Poll, Fail> {
        let n = max.min(self.pending.len());
        let out: Vec<u8> = self.pending.drain(..n).collect();
        self.total = self.total.saturating_add(out.len() as i64);
        if self.total > self.max {
            return Err(Fail::LimitExceeded);
        }
        Ok(Poll::Output(out))
    }

    fn step(&mut self, max: usize) -> Result<Poll, Fail> {
        loop {
            if !self.pending.is_empty() {
                return self.take_pending(max);
            }
            match self.phase {
                Phase::Done => return Ok(Poll::Done),
                Phase::Header => {
                    if self.format == Format::Zlib {
                        if self.input.len() < 2 {
                            if self.eof {
                                return Err(Fail::InvalidData);
                            }
                            return Ok(Poll::NeedInput);
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
                            Header::Need if self.eof => return Err(Fail::InvalidData),
                            Header::Need => return Ok(Poll::NeedInput),
                            Header::Bad => return Err(Fail::InvalidData),
                            Header::Len(n) => {
                                self.input.drain(..n);
                                self.check = 0;
                            }
                        }
                    }
                    self.size = 0;
                    *self.inflate = DecompressorOxide::new();
                    self.dict_pos = 0;
                    self.phase = Phase::Body;
                }
                Phase::Body => {
                    let mut flags = 0;
                    if !self.eof {
                        flags |= inflate_flags::TINFL_FLAG_HAS_MORE_INPUT;
                    }
                    let (status, used, made) = decompress(
                        &mut self.inflate,
                        &self.input,
                        &mut self.dict[..],
                        self.dict_pos,
                        flags,
                    );
                    self.input.drain(..used);
                    let produced = &self.dict[self.dict_pos..self.dict_pos + made];
                    match self.format {
                        Format::Gzip => self.check = crc32(self.check, produced),
                        Format::Zlib => self.check = adler32_update(self.check, produced),
                        Format::Deflate => {}
                    }
                    self.size = self.size.wrapping_add(made as u32);
                    self.pending.extend_from_slice(produced);
                    self.dict_pos = (self.dict_pos + made) & (TINFL_LZ_DICT_SIZE - 1);
                    match status {
                        TINFLStatus::Done => {
                            self.phase = if self.format == Format::Deflate {
                                Phase::Done
                            } else {
                                Phase::Trailer
                            };
                        }
                        TINFLStatus::NeedsMoreInput => {
                            if made == 0 {
                                return Ok(Poll::NeedInput);
                            }
                        }
                        TINFLStatus::HasMoreOutput => {}
                        _ => return Err(Fail::InvalidData),
                    }
                }
                Phase::Trailer => {
                    let n = if self.format == Format::Gzip { 8 } else { 4 };
                    if self.input.len() < n {
                        if self.eof {
                            return Err(Fail::InvalidData);
                        }
                        return Ok(Poll::NeedInput);
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
}

// ---- encoding ----

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
            let (status, used, made) = compress(&mut self.comp, data, &mut buf, flush);
            data = &data[used..];
            self.out.extend_from_slice(&buf[..made]);
            let more =
                matches!(status, TDEFLStatus::Okay) && (!data.is_empty() || made == buf.len());
            if !more {
                return;
            }
        }
    }

    /// Compresses `data`; output accumulates until [`Encoder::take`].
    pub fn feed(&mut self, data: &[u8]) {
        if self.finished {
            return;
        }
        self.header();
        match self.format {
            Format::Gzip => self.check = crc32(self.check, data),
            Format::Zlib => self.check = adler32_update(self.check, data),
            Format::Deflate => {}
        }
        self.size = self.size.wrapping_add(data.len() as u32);
        self.run(data, TDEFLFlush::None);
    }

    /// The input ended: flushes the compressor and writes the trailer.
    pub fn finish(&mut self) {
        if self.finished {
            return;
        }
        self.header();
        self.finished = true;
        let mut buf = [0u8; 16 * 1024];
        loop {
            let (status, _, made) = compress(&mut self.comp, &[], &mut buf, TDEFLFlush::Finish);
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
    }

    /// Whether [`Encoder::finish`] has been called.
    pub fn is_finished(&self) -> bool {
        self.finished
    }

    /// Whether output bytes are waiting.
    pub fn has_output(&self) -> bool {
        !self.out.is_empty()
    }

    /// Removes and returns at most `max` buffered output bytes.
    pub fn take(&mut self, max: usize) -> Vec<u8> {
        let n = max.min(self.out.len());
        self.out.drain(..n).collect()
    }
}
