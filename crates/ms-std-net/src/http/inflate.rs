//! Gzip (RFC 1952) over inflate (RFC 1951) for buffered response bodies.
//!
//! The decoder appends to one output `Vec` that keeps everything decoded so far, so a match is a
//! copy inside that vector and no separate window is kept. Huffman codes decode through flat
//! `u32` tables: one primary lookup, plus a subtable lookup for the rare long codes. The input is
//! resumable at symbol boundaries: when a symbol is cut by the end of the available bytes the
//! decoder rolls back to the start of that symbol and reports how much it consumed, and the caller
//! offers the unconsumed bytes again with the next chunk.

use crc32fast::Hasher;

/// Why decoding stopped for good.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Fail {
    /// The data is not valid gzip.
    Invalid,
    /// The input ended inside a member.
    Truncated,
    /// The output would exceed the limit.
    Limit,
}

/// Why one call stopped: more input is needed, or the stream failed.
enum Stop {
    Need,
    Fail(Fail),
}

impl From<Fail> for Stop {
    fn from(f: Fail) -> Stop {
        Stop::Fail(f)
    }
}

const LIT_BITS: u32 = 10;
const DIST_BITS: u32 = 8;
const MAX_MATCH: usize = 258;

// A table entry packs, from the low bits: the code length (4 bits), the extra-bit count (4 bits;
// for a subtable pointer, the subtable index width), the kind (3 bits), and from bit 16 the value
// (literal byte, length or distance base, subtable offset).
const KIND_SHIFT: u32 = 8;
const KIND_MASK: u32 = 7 << KIND_SHIFT;
const LIT: u32 = 0;
const BASE: u32 = 1 << KIND_SHIFT;
const EOB: u32 = 2 << KIND_SHIFT;
const SUB: u32 = 3 << KIND_SHIFT;
const BAD: u32 = 4 << KIND_SHIFT;

const LEN_BASE: [u16; 29] = [
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131,
    163, 195, 227, 258,
];
const LEN_EXTRA: [u8; 29] = [
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
];
const DIST_BASE: [u16; 30] = [
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537,
    2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
];
const DIST_EXTRA: [u8; 30] = [
    0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13,
    13,
];
/// Order in which code-length code lengths are stored.
const CLEN_ORDER: [usize; 19] = [
    16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
];

fn entry(len: u32, extra: u32, kind: u32, value: u32) -> u32 {
    len | (extra << 4) | kind | (value << 16)
}

/// Table entry for literal/length symbol `sym` whose code has `len` bits.
fn lit_entry(sym: usize, len: u32) -> u32 {
    match sym {
        0..=255 => entry(len, 0, LIT, sym as u32),
        256 => entry(len, 0, EOB, 0),
        257..=285 => entry(
            len,
            LEN_EXTRA[sym - 257] as u32,
            BASE,
            LEN_BASE[sym - 257] as u32,
        ),
        _ => BAD,
    }
}

/// Table entry for distance symbol `sym` whose code has `len` bits.
fn dist_entry(sym: usize, len: u32) -> u32 {
    match sym {
        0..=29 => entry(len, DIST_EXTRA[sym] as u32, BASE, DIST_BASE[sym] as u32),
        _ => BAD,
    }
}

/// Table entry for a code-length symbol.
fn clen_entry(sym: usize, len: u32) -> u32 {
    entry(len, 0, LIT, sym as u32)
}

fn reverse(code: u32, len: u32) -> u32 {
    code.reverse_bits() >> (32 - len)
}

/// Builds the lookup table for canonical codes with lengths `lens` (0 for an unused symbol): a
/// primary table of `1 << primary` entries followed by subtables. An over-subscribed code is
/// invalid; an incomplete one is accepted only as one code of one bit.
fn build(
    lens: &[u8],
    primary: u32,
    entry_of: fn(usize, u32) -> u32,
    table: &mut Vec<u32>,
) -> Result<(), Fail> {
    let mut count = [0u32; 16];
    for &l in lens {
        count[l as usize] += 1;
    }
    count[0] = 0;
    let used: u32 = count.iter().sum();
    let mut left: i64 = 1;
    for &c in &count[1..] {
        left = (left << 1) - c as i64;
        if left < 0 {
            return Err(Fail::Invalid);
        }
    }
    if left > 0 && !(used == 1 && count[1] == 1) && used != 0 {
        return Err(Fail::Invalid);
    }
    let mut next = [0u32; 16];
    let mut code = 0u32;
    for len in 1..16 {
        code = (code + count[len - 1]) << 1;
        next[len] = code;
    }
    // Reversed code of each symbol, in symbol order.
    let mut codes = [0u32; 320];
    for (sym, &l) in lens.iter().enumerate() {
        if l != 0 {
            codes[sym] = reverse(next[l as usize], l as u32);
            next[l as usize] += 1;
        }
    }
    let mask = (1u32 << primary) - 1;
    // Width of the subtable behind each primary slot that holds a long code.
    let mut width = [0u8; 1 << LIT_BITS];
    for (sym, &l) in lens.iter().enumerate() {
        let l = l as u32;
        if l > primary {
            let w = &mut width[(codes[sym] & mask) as usize];
            *w = (*w).max((l - primary) as u8);
        }
    }
    table.clear();
    table.resize(1 << primary, BAD);
    for slot in 0..(1usize << primary) {
        let w = width[slot];
        if w != 0 {
            let at = table.len();
            table[slot] = entry(primary, w as u32, SUB, at as u32);
            table.resize(at + (1usize << w), BAD);
        }
    }
    for (sym, &l) in lens.iter().enumerate() {
        if l == 0 {
            continue;
        }
        let l = l as u32;
        let code = codes[sym];
        let e = entry_of(sym, l);
        if l <= primary {
            let mut i = code as usize;
            while i < (1usize << primary) {
                table[i] = e;
                i += 1usize << l;
            }
        } else {
            let slot = (code & mask) as usize;
            let at = (table[slot] >> 16) as usize;
            let w = (table[slot] >> 4) & 15;
            let mut i = (code >> primary) as usize;
            while i < (1usize << w) {
                table[at + i] = e;
                i += 1usize << (l - primary);
            }
        }
    }
    Ok(())
}

/// The bit reader's state; copied to roll back to the start of a symbol.
#[derive(Clone, Copy)]
struct Bits {
    buf: u64,
    /// Valid bits in `buf`; at most 63.
    cnt: u32,
    /// Next unread byte of the input.
    pos: usize,
}

impl Bits {
    #[inline(always)]
    fn refill(&mut self, input: &[u8]) {
        if let Some(word) = input.get(self.pos..self.pos + 8) {
            let word = u64::from_le_bytes(word.try_into().expect("eight bytes"));
            // Bits above `cnt` are the next stream bits; loading the same bytes later is idempotent.
            self.buf |= word << self.cnt;
            let take = (63 - self.cnt) >> 3;
            self.pos += take as usize;
            self.cnt += take * 8;
        } else {
            while self.cnt < 56 && self.pos < input.len() {
                self.buf |= (input[self.pos] as u64) << self.cnt;
                self.pos += 1;
                self.cnt += 8;
            }
        }
    }

    #[inline(always)]
    fn consume(&mut self, n: u32) {
        self.buf >>= n;
        self.cnt -= n;
    }

    /// Hands the whole bytes still in the buffer back to the input, keeping only the bits of a
    /// partly used byte. Bytes in the buffer were all loaded by the current call, because every
    /// call ends this way, so `pos` has room for them.
    fn return_whole_bytes(&mut self) {
        let whole = self.cnt >> 3;
        self.pos -= whole as usize;
        self.cnt &= 7;
        self.buf &= (1u64 << self.cnt) - 1;
    }

    /// `n` (at most 32) bits, or `Need` when the input has fewer.
    fn take(&mut self, input: &[u8], n: u32) -> Result<u32, Stop> {
        if self.cnt < n {
            self.refill(input);
            if self.cnt < n {
                return Err(Stop::Need);
            }
        }
        let v = (self.buf & ((1u64 << n) - 1)) as u32;
        self.consume(n);
        Ok(v)
    }
}

#[derive(Clone, Copy)]
enum Phase {
    /// At a member boundary, before the gzip header.
    Header,
    /// Before a deflate block header.
    Block,
    /// Inside a stored block with `left` bytes to copy.
    Stored { left: usize, last: bool },
    /// Inside a Huffman block.
    Codes { last: bool },
    /// After the last block, before the 8-byte trailer; the bit buffer is not yet returned.
    Trailer { unloaded: bool },
}

/// A resumable gzip decoder over concatenated members.
pub struct Inflater {
    phase: Phase,
    bits: Bits,
    lit: Vec<u32>,
    dist: Vec<u32>,
    /// Whether the current block has any distance codes.
    has_dist: bool,
    crc: Hasher,
    /// Output length when the current member began; matches may not reach before it.
    member_base: usize,
    /// Output length up to which `crc` has been updated.
    crc_done: usize,
    members: usize,
    more: bool,
}

impl Default for Inflater {
    fn default() -> Self {
        Self::new()
    }
}

impl Inflater {
    pub fn new() -> Inflater {
        Inflater {
            phase: Phase::Header,
            bits: Bits {
                buf: 0,
                cnt: 0,
                pos: 0,
            },
            lit: Vec::new(),
            dist: Vec::new(),
            has_dist: false,
            crc: Hasher::new(),
            member_base: 0,
            crc_done: 0,
            members: 0,
            more: true,
        }
    }

    /// Decodes `input`, appending to `out`, which must only grow between calls. `more` says whether
    /// input will follow. Output past `limit` bytes of `out` fails with `Limit`. Returns the bytes of
    /// `input` consumed (the rest must be offered again first next time) and whether the stream ended
    /// cleanly: `more` is false and every member is complete.
    pub fn push(
        &mut self,
        input: &[u8],
        more: bool,
        out: &mut Vec<u8>,
        limit: usize,
    ) -> Result<(usize, bool), Fail> {
        self.more = more;
        self.bits.pos = 0;
        if self.members == 0 && matches!(self.phase, Phase::Header) {
            self.member_base = out.len();
            self.crc_done = out.len();
        }
        let result = self.run(input, out, limit);
        self.flush_crc(out);
        self.bits.return_whole_bytes();
        match result {
            Ok(done) => Ok((self.bits.pos, done)),
            Err(Stop::Need) if more => Ok((self.bits.pos, false)),
            Err(Stop::Need) => Err(Fail::Truncated),
            Err(Stop::Fail(f)) => Err(f),
        }
    }

    fn flush_crc(&mut self, out: &[u8]) {
        if out.len() > self.crc_done {
            self.crc.update(&out[self.crc_done..]);
            self.crc_done = out.len();
        }
    }

    fn run(&mut self, input: &[u8], out: &mut Vec<u8>, limit: usize) -> Result<bool, Stop> {
        loop {
            match self.phase {
                Phase::Header => {
                    let rest = &input[self.bits.pos..];
                    if rest.is_empty() && !self.more && self.members > 0 {
                        return Ok(true);
                    }
                    let n = gzip_header(rest)?;
                    self.bits.pos += n;
                    self.member_base = out.len();
                    self.crc_done = out.len();
                    self.crc = Hasher::new();
                    self.phase = Phase::Block;
                }
                Phase::Block => {
                    let snap = self.bits;
                    match self.block_header(input) {
                        Ok(phase) => self.phase = phase,
                        Err(e) => {
                            self.bits = snap;
                            return Err(e);
                        }
                    }
                }
                Phase::Stored { left, last } => {
                    let left = self.copy_stored(input, out, left, limit)?;
                    self.phase = match (left, last) {
                        (0, true) => Phase::Trailer { unloaded: false },
                        (0, false) => Phase::Block,
                        (left, last) => Phase::Stored { left, last },
                    };
                    if left > 0 {
                        return Err(Stop::Need);
                    }
                }
                Phase::Codes { last } => {
                    self.codes(input, out, limit)?;
                    self.phase = if last {
                        Phase::Trailer { unloaded: false }
                    } else {
                        Phase::Block
                    };
                }
                Phase::Trailer { unloaded } => {
                    if !unloaded {
                        // Whole bytes still in the bit buffer belong to the trailer; the bits left
                        // of the last block's final byte are padding.
                        self.bits.return_whole_bytes();
                        self.bits.buf = 0;
                        self.bits.cnt = 0;
                        self.phase = Phase::Trailer { unloaded: true };
                    }
                    let rest = &input[self.bits.pos..];
                    if rest.len() < 8 {
                        return Err(Stop::Need);
                    }
                    self.flush_crc(out);
                    let crc = u32::from_le_bytes([rest[0], rest[1], rest[2], rest[3]]);
                    let size = u32::from_le_bytes([rest[4], rest[5], rest[6], rest[7]]);
                    let made = (out.len() - self.member_base) as u32;
                    if crc != self.crc.clone().finalize() || size != made {
                        return Err(Fail::Invalid.into());
                    }
                    self.bits.pos += 8;
                    self.members += 1;
                    self.phase = Phase::Header;
                }
            }
        }
    }

    /// Reads a block header and prepares for its body, or returns `Need` with the bits unchanged
    /// by the caller's rollback.
    fn block_header(&mut self, input: &[u8]) -> Result<Phase, Stop> {
        let head = self.bits.take(input, 3)?;
        let last = head & 1 == 1;
        match head >> 1 {
            0 => {
                // Skip to the next byte, then LEN and its complement.
                let skip = self.bits.cnt & 7;
                self.bits.consume(skip);
                let len = self.bits.take(input, 16)?;
                let nlen = self.bits.take(input, 16)?;
                if len != !nlen & 0xffff {
                    return Err(Fail::Invalid.into());
                }
                Ok(Phase::Stored {
                    left: len as usize,
                    last,
                })
            }
            1 => {
                let mut lens = [0u8; 288];
                lens[..144].fill(8);
                lens[144..256].fill(9);
                lens[256..280].fill(7);
                lens[280..].fill(8);
                build(&lens, LIT_BITS, lit_entry, &mut self.lit)?;
                build(&[5u8; 32], DIST_BITS, dist_entry, &mut self.dist)?;
                self.has_dist = true;
                Ok(Phase::Codes { last })
            }
            2 => {
                self.dynamic_tables(input)?;
                Ok(Phase::Codes { last })
            }
            _ => Err(Fail::Invalid.into()),
        }
    }

    fn dynamic_tables(&mut self, input: &[u8]) -> Result<(), Stop> {
        let hlit = self.bits.take(input, 5)? as usize + 257;
        let hdist = self.bits.take(input, 5)? as usize + 1;
        let hclen = self.bits.take(input, 4)? as usize + 4;
        if hlit > 286 || hdist > 30 {
            return Err(Fail::Invalid.into());
        }
        let mut clens = [0u8; 19];
        for &i in &CLEN_ORDER[..hclen] {
            clens[i] = self.bits.take(input, 3)? as u8;
        }
        let mut clen_table = Vec::new();
        build(&clens, 7, clen_entry, &mut clen_table)?;
        let mut lens = [0u8; 320];
        let total = hlit + hdist;
        let mut at = 0;
        while at < total {
            if self.bits.cnt < 15 {
                self.bits.refill(input);
            }
            let e = clen_table[(self.bits.buf & 127) as usize];
            let n = e & 15;
            if e & KIND_MASK == BAD {
                if self.bits.cnt >= 7 || !self.more {
                    return Err(Fail::Invalid.into());
                }
                return Err(Stop::Need);
            }
            if n > self.bits.cnt {
                return Err(Stop::Need);
            }
            self.bits.consume(n);
            let sym = (e >> 16) as u8;
            let (value, repeat) = match sym {
                0..=15 => (sym, 1),
                16 => {
                    if at == 0 {
                        return Err(Fail::Invalid.into());
                    }
                    (lens[at - 1], 3 + self.bits.take(input, 2)? as usize)
                }
                17 => (0, 3 + self.bits.take(input, 3)? as usize),
                _ => (0, 11 + self.bits.take(input, 7)? as usize),
            };
            if at + repeat > total {
                return Err(Fail::Invalid.into());
            }
            lens[at..at + repeat].fill(value);
            at += repeat;
        }
        if lens[256] == 0 {
            return Err(Fail::Invalid.into());
        }
        build(&lens[..hlit], LIT_BITS, lit_entry, &mut self.lit)?;
        self.has_dist = lens[hlit..total].iter().any(|&l| l != 0);
        build(&lens[hlit..total], DIST_BITS, dist_entry, &mut self.dist)?;
        Ok(())
    }

    /// Copies up to `left` stored bytes; returns how many remain.
    fn copy_stored(
        &mut self,
        input: &[u8],
        out: &mut Vec<u8>,
        mut left: usize,
        limit: usize,
    ) -> Result<usize, Stop> {
        if out.len() + left > limit {
            return Err(Fail::Limit.into());
        }
        while left > 0 && self.bits.cnt >= 8 {
            out.push(self.bits.buf as u8);
            self.bits.consume(8);
            left -= 1;
        }
        // Bits above `cnt` are lookahead of bytes about to be copied; drop them.
        self.bits.buf &= (1u64 << self.bits.cnt) - 1;
        let take = left.min(input.len() - self.bits.pos);
        out.extend_from_slice(&input[self.bits.pos..self.bits.pos + take]);
        self.bits.pos += take;
        Ok(left - take)
    }

    /// The bulk of a block, with the bit buffer in locals and the output written by index into a
    /// zero-extended window of `out`, so a literal is one store and no step checks capacity. While
    /// 16 input bytes remain, one refill leaves at least 56 bits, enough for a whole
    /// length/distance pair (48 bits at most), so no step can run out of input and none needs a
    /// rollback. Returns `true` at the end of the block, `false` when the careful loop must finish
    /// (input nearly spent or the limit passed).
    #[inline(never)]
    fn codes_fast(&mut self, input: &[u8], out: &mut Vec<u8>, limit: usize) -> Result<bool, Stop> {
        const LIT_MASK: u64 = (1 << LIT_BITS) - 1;
        const DIST_MASK: u64 = (1 << DIST_BITS) - 1;
        const WINDOW: usize = 1 << 17;
        let Bits {
            mut buf,
            mut cnt,
            mut pos,
        } = self.bits;
        let base = self.member_base;
        let (lit, dist_table) = (self.lit.as_slice(), self.dist.as_slice());
        // Lets the primary-table lookups below skip their bounds checks.
        assert!(lit.len() >= 1 << LIT_BITS && dist_table.len() >= 1 << DIST_BITS);
        let mut result = Ok(false);
        'window: while pos + 16 <= input.len() && out.len() <= limit {
            let start = out.len();
            out.resize(start + WINDOW + MAX_MATCH + 16, 0);
            let dst = out.as_mut_slice();
            let end = start + WINDOW;
            let mut w = start;
            while w < end {
                if pos + 16 > input.len() || w > limit {
                    break;
                }
                let word = u64::from_le_bytes(input[pos..pos + 8].try_into().expect("eight bytes"));
                buf |= word << cnt;
                let take = (63 - cnt) >> 3;
                pos += take as usize;
                cnt += take * 8;
                let mut e = lit[(buf & LIT_MASK) as usize];
                if e & KIND_MASK == SUB {
                    e = lit[(e >> 16) as usize
                        + ((buf >> LIT_BITS) as usize & ((1usize << ((e >> 4) & 15)) - 1))];
                }
                let kind = e & KIND_MASK;
                if kind == BAD {
                    result = Err(Fail::Invalid.into());
                    out.truncate(w);
                    break 'window;
                }
                buf >>= e & 15;
                cnt -= e & 15;
                if kind == LIT {
                    dst[w] = (e >> 16) as u8;
                    w += 1;
                    for _ in 0..5 {
                        let mut e = lit[(buf & LIT_MASK) as usize];
                        if e & KIND_MASK == SUB {
                            e = lit[(e >> 16) as usize
                                + ((buf >> LIT_BITS) as usize & ((1usize << ((e >> 4) & 15)) - 1))];
                        }
                        if e & KIND_MASK != LIT || cnt < 15 {
                            break;
                        }
                        buf >>= e & 15;
                        cnt -= e & 15;
                        dst[w] = (e >> 16) as u8;
                        w += 1;
                    }
                    continue;
                }
                if kind == EOB {
                    out.truncate(w);
                    result = Ok(true);
                    break 'window;
                }
                let extra = (e >> 4) & 15;
                let length = (e >> 16) as usize + (buf & ((1u64 << extra) - 1)) as usize;
                buf >>= extra;
                cnt -= extra;
                let mut d = dist_table[(buf & DIST_MASK) as usize];
                if d & KIND_MASK == SUB {
                    d = dist_table[(d >> 16) as usize
                        + ((buf >> DIST_BITS) as usize & ((1usize << ((d >> 4) & 15)) - 1))];
                }
                if d & KIND_MASK == BAD || !self.has_dist {
                    result = Err(Fail::Invalid.into());
                    out.truncate(w);
                    break 'window;
                }
                buf >>= d & 15;
                cnt -= d & 15;
                let dextra = (d >> 4) & 15;
                let dist = (d >> 16) as usize + (buf & ((1u64 << dextra) - 1)) as usize;
                buf >>= dextra;
                cnt -= dextra;
                if dist > w - base {
                    result = Err(Fail::Invalid.into());
                    out.truncate(w);
                    break 'window;
                }
                let from = w - dist;
                if dist >= 16 && length <= 16 {
                    // The slack past `w` absorbs the over-copy; the source is entirely behind `w`.
                    dst.copy_within(from..from + 16, w);
                } else if dist >= length {
                    dst.copy_within(from..from + length, w);
                } else if dist == 1 {
                    let b = dst[from];
                    dst[w..w + length].fill(b);
                } else {
                    for i in 0..length {
                        dst[w + i] = dst[from + i];
                    }
                }
                w += length;
            }
            out.truncate(w);
        }
        self.bits = Bits { buf, cnt, pos };
        result
    }

    /// Decodes one Huffman block through its end-of-block code.
    fn codes(&mut self, input: &[u8], out: &mut Vec<u8>, limit: usize) -> Result<(), Stop> {
        let lit_mask = (1u64 << LIT_BITS) - 1;
        let dist_mask = (1u64 << DIST_BITS) - 1;
        loop {
            if self.codes_fast(input, out, limit)? {
                return Ok(());
            }
            if out.len() > limit {
                return Err(Fail::Limit.into());
            }
            let snap = self.bits;
            self.bits.refill(input);
            let mut e = self.lit[(self.bits.buf & lit_mask) as usize];
            if e & KIND_MASK == SUB {
                e = self.lit[(e >> 16) as usize
                    + ((self.bits.buf >> LIT_BITS) as usize & ((1usize << ((e >> 4) & 15)) - 1))];
            }
            let n = e & 15;
            let kind = e & KIND_MASK;
            if kind == BAD || n > self.bits.cnt {
                if kind == BAD && (self.bits.cnt >= 15 || !self.more) {
                    return Err(Fail::Invalid.into());
                }
                self.bits = snap;
                return Err(Stop::Need);
            }
            self.bits.consume(n);
            if kind == LIT {
                out.push((e >> 16) as u8);
                // Up to two more literals from the same refill, while a whole code is buffered.
                for _ in 0..5 {
                    if self.bits.cnt < 15 {
                        break;
                    }
                    let mut e = self.lit[(self.bits.buf & lit_mask) as usize];
                    if e & KIND_MASK == SUB {
                        e = self.lit[(e >> 16) as usize
                            + ((self.bits.buf >> LIT_BITS) as usize
                                & ((1usize << ((e >> 4) & 15)) - 1))];
                    }
                    if e & KIND_MASK != LIT {
                        break;
                    }
                    self.bits.consume(e & 15);
                    out.push((e >> 16) as u8);
                }
                continue;
            }
            if kind == EOB {
                return Ok(());
            }
            let extra = (e >> 4) & 15;
            let mut length = (e >> 16) as usize;
            if self.bits.cnt < extra {
                self.bits = snap;
                return Err(Stop::Need);
            }
            length += (self.bits.buf & ((1u64 << extra) - 1)) as usize;
            self.bits.consume(extra);
            if !self.has_dist {
                return Err(Fail::Invalid.into());
            }
            let mut d = self.dist[(self.bits.buf & dist_mask) as usize];
            if d & KIND_MASK == SUB {
                d = self.dist[(d >> 16) as usize
                    + ((self.bits.buf >> DIST_BITS) as usize & ((1usize << ((d >> 4) & 15)) - 1))];
            }
            let dn = d & 15;
            let dkind = d & KIND_MASK;
            if dkind == BAD || dn > self.bits.cnt {
                if dkind == BAD && (self.bits.cnt >= 15 || !self.more) {
                    return Err(Fail::Invalid.into());
                }
                self.bits = snap;
                return Err(Stop::Need);
            }
            self.bits.consume(dn);
            let dextra = (d >> 4) & 15;
            if self.bits.cnt < dextra {
                self.bits = snap;
                return Err(Stop::Need);
            }
            let dist = (d >> 16) as usize + (self.bits.buf & ((1u64 << dextra) - 1)) as usize;
            self.bits.consume(dextra);
            if dist > out.len() - self.member_base {
                return Err(Fail::Invalid.into());
            }
            copy_match(out, dist, length);
        }
    }
}

/// Appends `len` bytes starting `dist` bytes back; a distance shorter than the length repeats the
/// bytes it covers.
#[inline(always)]
fn copy_match(out: &mut Vec<u8>, dist: usize, len: usize) {
    debug_assert!(len <= MAX_MATCH);
    let start = out.len() - dist;
    if dist >= len {
        out.extend_from_within(start..start + len);
    } else if dist == 1 {
        let b = out[start];
        out.resize(out.len() + len, b);
    } else {
        let target = out.len() + len;
        while out.len() < target {
            let take = (out.len() - start).min(target - out.len());
            out.extend_from_within(start..start + take);
        }
    }
}

/// Length of the gzip header at the start of `rest`, or `Need` when it is cut short.
fn gzip_header(rest: &[u8]) -> Result<usize, Stop> {
    if rest.len() < 10 {
        // Even a short prefix must look like a header.
        let magic = [0x1f, 0x8b, 8];
        if rest.iter().zip(magic).any(|(a, b)| *a != b) {
            return Err(Fail::Invalid.into());
        }
        return Err(Stop::Need);
    }
    if rest[0] != 0x1f || rest[1] != 0x8b || rest[2] != 8 || rest[3] & 0xe0 != 0 {
        return Err(Fail::Invalid.into());
    }
    let flags = rest[3];
    let mut at = 10;
    if flags & 4 != 0 {
        let Some(len) = rest.get(at..at + 2) else {
            return Err(Stop::Need);
        };
        at += 2 + u16::from_le_bytes([len[0], len[1]]) as usize;
    }
    for flag in [8u8, 16] {
        if flags & flag != 0 {
            let Some(end) = rest.get(at..).and_then(|r| r.iter().position(|&b| b == 0)) else {
                return Err(Stop::Need);
            };
            at += end + 1;
        }
    }
    if flags & 2 != 0 {
        at += 2;
    }
    if rest.len() < at {
        return Err(Stop::Need);
    }
    Ok(at)
}

#[cfg(test)]
mod tests {
    use super::*;
    use flate2::Compression;
    use flate2::write::GzEncoder;
    use std::io::Write;

    fn gzip(data: &[u8], level: u32) -> Vec<u8> {
        let mut e = GzEncoder::new(Vec::new(), Compression::new(level));
        e.write_all(data).unwrap();
        e.finish().unwrap()
    }

    /// Decodes `z` in `chunk`-byte pieces, offering unconsumed bytes again each time.
    fn decode(z: &[u8], chunk: usize) -> Result<Vec<u8>, Fail> {
        let mut inflater = Inflater::new();
        let mut out = Vec::new();
        let mut pending: Vec<u8> = Vec::new();
        let mut chunks = z.chunks(chunk);
        loop {
            let next = chunks.next();
            pending.extend_from_slice(next.unwrap_or(&[]));
            let more = next.is_some();
            let (used, done) = inflater.push(&pending, more, &mut out, usize::MAX)?;
            pending.drain(..used);
            if done {
                assert!(pending.is_empty());
                return Ok(out);
            }
            assert!(more, "a finished input must report done");
        }
    }

    fn sample(n: usize, seed: u64) -> Vec<u8> {
        // Mixed: runs, repeated phrases, noise.
        let mut x = seed | 1;
        let mut next = move || {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            x
        };
        let mut v = Vec::with_capacity(n);
        while v.len() < n {
            match next() % 4 {
                0 => v.extend(std::iter::repeat_n(
                    (next() % 256) as u8,
                    (next() % 600) as usize,
                )),
                1 => v.extend_from_slice(b"the quick brown fox jumps over the lazy dog. "),
                2 => v.extend((0..(next() % 200)).map(|_| next() as u8)),
                _ => {
                    let from = (next() as usize) % (v.len() + 1);
                    let to = (from + (next() % 400) as usize).min(v.len());
                    let piece = v[from..to].to_vec();
                    v.extend(piece);
                }
            }
        }
        v.truncate(n);
        v
    }

    #[test]
    fn matches_flate2_across_levels_and_chunk_sizes() {
        for (i, n) in [0usize, 1, 5, 300, 70_000, 400_000].into_iter().enumerate() {
            let data = sample(n, 7 + i as u64);
            for level in [0, 1, 6, 9] {
                let z = gzip(&data, level);
                for chunk in [1usize, 3, 7, 4096, usize::MAX] {
                    if chunk == 1 && z.len() > 100_000 {
                        continue;
                    }
                    let got = decode(&z, chunk.min(z.len().max(1)))
                        .unwrap_or_else(|e| panic!("n={n} level={level} chunk={chunk}: {e:?}"));
                    assert!(got == data, "n={n} level={level} chunk={chunk}");
                }
            }
        }
    }

    #[test]
    fn decodes_concatenated_members_and_empty_members() {
        let z = [gzip(b"hello ", 6), gzip(b"", 6), gzip(b"world", 1)].concat();
        for chunk in [1usize, 5, 4096] {
            assert_eq!(decode(&z, chunk).unwrap(), b"hello world");
        }
    }

    #[test]
    fn members_keep_their_own_history() {
        let first = gzip(&[b'a'; 100], 6);
        let mut second = gzip(&[b'b'; 40], 6);
        let z = {
            let mut v = first.clone();
            v.append(&mut second);
            v
        };
        assert_eq!(decode(&z, 16).unwrap().len(), 140);
    }

    #[test]
    fn rejects_corrupt_truncated_and_trailing_input() {
        let data = sample(50_000, 3);
        let z = gzip(&data, 6);
        let mut bad_crc = z.clone();
        let at = bad_crc.len() - 8;
        bad_crc[at] ^= 1;
        assert_eq!(decode(&bad_crc, 4096), Err(Fail::Invalid));
        let mut bad_size = z.clone();
        let at = bad_size.len() - 1;
        bad_size[at] ^= 1;
        assert_eq!(decode(&bad_size, 4096), Err(Fail::Invalid));
        assert_eq!(decode(&z[..z.len() - 3], 4096), Err(Fail::Truncated));
        assert_eq!(decode(&z[..20], 4096), Err(Fail::Truncated));
        let mut trailing = z.clone();
        trailing.extend_from_slice(b"junk");
        assert_eq!(decode(&trailing, 4096), Err(Fail::Invalid));
        assert_eq!(decode(b"not gzip at all", 4096), Err(Fail::Invalid));
    }

    #[test]
    fn corrupted_streams_fail_without_panicking() {
        let data = sample(20_000, 11);
        for level in [0, 1, 6] {
            let z = gzip(&data, level);
            let mut x = 99u64;
            for _ in 0..300 {
                x ^= x << 13;
                x ^= x >> 7;
                x ^= x << 17;
                let mut bad = z.clone();
                let at = (x as usize) % bad.len();
                bad[at] ^= 1 << (x % 8);
                let chunk = [1usize, 7, 4096][(x % 3) as usize];
                if let Ok(out) = decode(&bad, chunk) {
                    // A flip the format cannot see (a header flag bit, say) still yields the data.
                    assert!(out == data);
                }
            }
        }
    }

    #[test]
    fn enforces_the_output_limit() {
        let z = gzip(&vec![b'a'; 100_000], 6);
        let mut inflater = Inflater::new();
        let mut out = Vec::new();
        assert_eq!(
            inflater.push(&z, false, &mut out, 99_999).map(|_| ()),
            Err(Fail::Limit)
        );
        let mut inflater = Inflater::new();
        let mut out = Vec::new();
        assert!(inflater.push(&z, false, &mut out, 100_000).unwrap().1);
        assert_eq!(out.len(), 100_000);
        let stored = gzip(&vec![7u8; 5000], 0);
        let mut inflater = Inflater::new();
        let mut out = Vec::new();
        assert_eq!(
            inflater.push(&stored, false, &mut out, 4999).map(|_| ()),
            Err(Fail::Limit)
        );
    }

    #[test]
    fn appends_after_existing_output() {
        let z = gzip(b"payload payload payload", 6);
        let mut inflater = Inflater::new();
        let mut out = b"prefix:".to_vec();
        let (_, done) = inflater.push(&z, false, &mut out, usize::MAX).unwrap();
        assert!(done);
        assert_eq!(out, b"prefix:payload payload payload");
    }
}
