//! HPACK (RFC 7541): header compression for HTTP/2.
//!
//! Pure functions over byte slices; no I/O. [`Decoder`] enforces the table-size
//! limit the local endpoint advertised and a caller supplied header-list-size
//! budget; [`Encoder`] indexes into the dynamic table and optionally uses the
//! Huffman code unless it would be longer.

use std::collections::VecDeque;
use std::sync::OnceLock;

/// One header field: `(name, value)` as raw bytes.
pub type Header = (Vec<u8>, Vec<u8>);

/// A malformed or disallowed HPACK block. Always a connection error
/// (`COMPRESSION_ERROR`) in HTTP/2.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HpackError(pub &'static str);

impl std::fmt::Display for HpackError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "hpack: {}", self.0)
    }
}

impl std::error::Error for HpackError {}

/// Default `SETTINGS_HEADER_TABLE_SIZE`.
pub const DEFAULT_TABLE_SIZE: usize = 4096;

/// Per-entry overhead from RFC 7541 section 4.1.
const ENTRY_OVERHEAD: usize = 32;

const STATIC_TABLE: [(&str, &str); 61] = [
    (":authority", ""),
    (":method", "GET"),
    (":method", "POST"),
    (":path", "/"),
    (":path", "/index.html"),
    (":scheme", "http"),
    (":scheme", "https"),
    (":status", "200"),
    (":status", "204"),
    (":status", "206"),
    (":status", "304"),
    (":status", "400"),
    (":status", "404"),
    (":status", "500"),
    ("accept-charset", ""),
    ("accept-encoding", "gzip, deflate"),
    ("accept-language", ""),
    ("accept-ranges", ""),
    ("accept", ""),
    ("access-control-allow-origin", ""),
    ("age", ""),
    ("allow", ""),
    ("authorization", ""),
    ("cache-control", ""),
    ("content-disposition", ""),
    ("content-encoding", ""),
    ("content-language", ""),
    ("content-length", ""),
    ("content-location", ""),
    ("content-range", ""),
    ("content-type", ""),
    ("cookie", ""),
    ("date", ""),
    ("etag", ""),
    ("expect", ""),
    ("expires", ""),
    ("from", ""),
    ("host", ""),
    ("if-match", ""),
    ("if-modified-since", ""),
    ("if-none-match", ""),
    ("if-range", ""),
    ("if-unmodified-since", ""),
    ("last-modified", ""),
    ("link", ""),
    ("location", ""),
    ("max-forwards", ""),
    ("proxy-authenticate", ""),
    ("proxy-authorization", ""),
    ("range", ""),
    ("referer", ""),
    ("refresh", ""),
    ("retry-after", ""),
    ("server", ""),
    ("set-cookie", ""),
    ("strict-transport-security", ""),
    ("transfer-encoding", ""),
    ("user-agent", ""),
    ("vary", ""),
    ("via", ""),
    ("www-authenticate", ""),
];

/// RFC 7541 appendix B: `(code, bit length)` for symbols 0..=256 (256 is EOS).
const HUFFMAN: [(u32, u8); 257] = [
    (0x1ff8, 13),
    (0x7fffd8, 23),
    (0xfffffe2, 28),
    (0xfffffe3, 28),
    (0xfffffe4, 28),
    (0xfffffe5, 28),
    (0xfffffe6, 28),
    (0xfffffe7, 28),
    (0xfffffe8, 28),
    (0xffffea, 24),
    (0x3ffffffc, 30),
    (0xfffffe9, 28),
    (0xfffffea, 28),
    (0x3ffffffd, 30),
    (0xfffffeb, 28),
    (0xfffffec, 28),
    (0xfffffed, 28),
    (0xfffffee, 28),
    (0xfffffef, 28),
    (0xffffff0, 28),
    (0xffffff1, 28),
    (0xffffff2, 28),
    (0x3ffffffe, 30),
    (0xffffff3, 28),
    (0xffffff4, 28),
    (0xffffff5, 28),
    (0xffffff6, 28),
    (0xffffff7, 28),
    (0xffffff8, 28),
    (0xffffff9, 28),
    (0xffffffa, 28),
    (0xffffffb, 28),
    (0x14, 6),
    (0x3f8, 10),
    (0x3f9, 10),
    (0xffa, 12),
    (0x1ff9, 13),
    (0x15, 6),
    (0xf8, 8),
    (0x7fa, 11),
    (0x3fa, 10),
    (0x3fb, 10),
    (0xf9, 8),
    (0x7fb, 11),
    (0xfa, 8),
    (0x16, 6),
    (0x17, 6),
    (0x18, 6),
    (0x0, 5),
    (0x1, 5),
    (0x2, 5),
    (0x19, 6),
    (0x1a, 6),
    (0x1b, 6),
    (0x1c, 6),
    (0x1d, 6),
    (0x1e, 6),
    (0x1f, 6),
    (0x5c, 7),
    (0xfb, 8),
    (0x7ffc, 15),
    (0x20, 6),
    (0xffb, 12),
    (0x3fc, 10),
    (0x1ffa, 13),
    (0x21, 6),
    (0x5d, 7),
    (0x5e, 7),
    (0x5f, 7),
    (0x60, 7),
    (0x61, 7),
    (0x62, 7),
    (0x63, 7),
    (0x64, 7),
    (0x65, 7),
    (0x66, 7),
    (0x67, 7),
    (0x68, 7),
    (0x69, 7),
    (0x6a, 7),
    (0x6b, 7),
    (0x6c, 7),
    (0x6d, 7),
    (0x6e, 7),
    (0x6f, 7),
    (0x70, 7),
    (0x71, 7),
    (0x72, 7),
    (0xfc, 8),
    (0x73, 7),
    (0xfd, 8),
    (0x1ffb, 13),
    (0x7fff0, 19),
    (0x1ffc, 13),
    (0x3ffc, 14),
    (0x22, 6),
    (0x7ffd, 15),
    (0x3, 5),
    (0x23, 6),
    (0x4, 5),
    (0x24, 6),
    (0x5, 5),
    (0x25, 6),
    (0x26, 6),
    (0x27, 6),
    (0x6, 5),
    (0x74, 7),
    (0x75, 7),
    (0x28, 6),
    (0x29, 6),
    (0x2a, 6),
    (0x7, 5),
    (0x2b, 6),
    (0x76, 7),
    (0x2c, 6),
    (0x8, 5),
    (0x9, 5),
    (0x2d, 6),
    (0x77, 7),
    (0x78, 7),
    (0x79, 7),
    (0x7a, 7),
    (0x7b, 7),
    (0x7ffe, 15),
    (0x7fc, 11),
    (0x3ffd, 14),
    (0x1ffd, 13),
    (0xffffffc, 28),
    (0xfffe6, 20),
    (0x3fffd2, 22),
    (0xfffe7, 20),
    (0xfffe8, 20),
    (0x3fffd3, 22),
    (0x3fffd4, 22),
    (0x3fffd5, 22),
    (0x7fffd9, 23),
    (0x3fffd6, 22),
    (0x7fffda, 23),
    (0x7fffdb, 23),
    (0x7fffdc, 23),
    (0x7fffdd, 23),
    (0x7fffde, 23),
    (0xffffeb, 24),
    (0x7fffdf, 23),
    (0xffffec, 24),
    (0xffffed, 24),
    (0x3fffd7, 22),
    (0x7fffe0, 23),
    (0xffffee, 24),
    (0x7fffe1, 23),
    (0x7fffe2, 23),
    (0x7fffe3, 23),
    (0x7fffe4, 23),
    (0x1fffdc, 21),
    (0x3fffd8, 22),
    (0x7fffe5, 23),
    (0x3fffd9, 22),
    (0x7fffe6, 23),
    (0x7fffe7, 23),
    (0xffffef, 24),
    (0x3fffda, 22),
    (0x1fffdd, 21),
    (0xfffe9, 20),
    (0x3fffdb, 22),
    (0x3fffdc, 22),
    (0x7fffe8, 23),
    (0x7fffe9, 23),
    (0x1fffde, 21),
    (0x7fffea, 23),
    (0x3fffdd, 22),
    (0x3fffde, 22),
    (0xfffff0, 24),
    (0x1fffdf, 21),
    (0x3fffdf, 22),
    (0x7fffeb, 23),
    (0x7fffec, 23),
    (0x1fffe0, 21),
    (0x1fffe1, 21),
    (0x3fffe0, 22),
    (0x1fffe2, 21),
    (0x7fffed, 23),
    (0x3fffe1, 22),
    (0x7fffee, 23),
    (0x7fffef, 23),
    (0xfffea, 20),
    (0x3fffe2, 22),
    (0x3fffe3, 22),
    (0x3fffe4, 22),
    (0x7ffff0, 23),
    (0x3fffe5, 22),
    (0x3fffe6, 22),
    (0x7ffff1, 23),
    (0x3ffffe0, 26),
    (0x3ffffe1, 26),
    (0xfffeb, 20),
    (0x7fff1, 19),
    (0x3fffe7, 22),
    (0x7ffff2, 23),
    (0x3fffe8, 22),
    (0x1ffffec, 25),
    (0x3ffffe2, 26),
    (0x3ffffe3, 26),
    (0x3ffffe4, 26),
    (0x7ffffde, 27),
    (0x7ffffdf, 27),
    (0x3ffffe5, 26),
    (0xfffff1, 24),
    (0x1ffffed, 25),
    (0x7fff2, 19),
    (0x1fffe3, 21),
    (0x3ffffe6, 26),
    (0x7ffffe0, 27),
    (0x7ffffe1, 27),
    (0x3ffffe7, 26),
    (0x7ffffe2, 27),
    (0xfffff2, 24),
    (0x1fffe4, 21),
    (0x1fffe5, 21),
    (0x3ffffe8, 26),
    (0x3ffffe9, 26),
    (0xffffffd, 28),
    (0x7ffffe3, 27),
    (0x7ffffe4, 27),
    (0x7ffffe5, 27),
    (0xfffec, 20),
    (0xfffff3, 24),
    (0xfffed, 20),
    (0x1fffe6, 21),
    (0x3fffe9, 22),
    (0x1fffe7, 21),
    (0x1fffe8, 21),
    (0x7ffff3, 23),
    (0x3fffea, 22),
    (0x3fffeb, 22),
    (0x1ffffee, 25),
    (0x1ffffef, 25),
    (0xfffff4, 24),
    (0xfffff5, 24),
    (0x3ffffea, 26),
    (0x7ffff4, 23),
    (0x3ffffeb, 26),
    (0x7ffffe6, 27),
    (0x3ffffec, 26),
    (0x3ffffed, 26),
    (0x7ffffe7, 27),
    (0x7ffffe8, 27),
    (0x7ffffe9, 27),
    (0x7ffffea, 27),
    (0x7ffffeb, 27),
    (0xffffffe, 28),
    (0x7ffffec, 27),
    (0x7ffffed, 27),
    (0x7ffffee, 27),
    (0x7ffffef, 27),
    (0x7fffff0, 27),
    (0x3ffffee, 26),
    (0x3fffffff, 30),
];

const EOS: usize = 256;

// ---------------------------------------------------------------------------
// Huffman
// ---------------------------------------------------------------------------

/// Binary decoding tree. Node 0 is the root; a child value `> 0` is a node
/// index and `< 0` is the leaf for symbol `-(v + 1)`.
fn huffman_tree() -> &'static [[i32; 2]] {
    static TREE: OnceLock<Vec<[i32; 2]>> = OnceLock::new();
    TREE.get_or_init(|| {
        let mut nodes: Vec<[i32; 2]> = vec![[0, 0]];
        for (sym, &(code, bits)) in HUFFMAN.iter().enumerate() {
            let mut cur = 0usize;
            for i in (0..bits).rev() {
                let bit = ((code >> i) & 1) as usize;
                if i == 0 {
                    nodes[cur][bit] = -(sym as i32) - 1;
                    break;
                }
                if nodes[cur][bit] == 0 {
                    nodes.push([0, 0]);
                    nodes[cur][bit] = (nodes.len() - 1) as i32;
                }
                cur = nodes[cur][bit] as usize;
            }
        }
        nodes
    })
}

/// Number of bytes `s` occupies when Huffman coded.
pub fn huffman_encoded_len(s: &[u8]) -> usize {
    let bits: usize = s.iter().map(|&b| HUFFMAN[b as usize].1 as usize).sum();
    bits.div_ceil(8)
}

/// Huffman-encode `s`, padding the final byte with EOS prefix bits.
pub fn huffman_encode(s: &[u8], out: &mut Vec<u8>) {
    let mut acc: u64 = 0;
    let mut nbits: u32 = 0;
    for &b in s {
        let (code, bits) = HUFFMAN[b as usize];
        acc = (acc << bits) | code as u64;
        nbits += bits as u32;
        while nbits >= 8 {
            nbits -= 8;
            out.push((acc >> nbits) as u8);
        }
        acc &= (1u64 << nbits) - 1;
    }
    if nbits > 0 {
        let pad = 8 - nbits;
        out.push(((acc << pad) | ((1u64 << pad) - 1)) as u8);
    }
}

/// Decode a Huffman string. Rejects EOS in the data, padding longer than seven
/// bits and padding that is not a prefix of EOS (all ones).
pub fn huffman_decode(s: &[u8]) -> Result<Vec<u8>, HpackError> {
    let tree = huffman_tree();
    let mut out = Vec::with_capacity(s.len() * 8 / 5 + 1);
    let mut cur = 0usize;
    let mut pad_bits = 0u32;
    let mut all_ones = true;
    for &byte in s {
        for i in (0..8).rev() {
            let bit = ((byte >> i) & 1) as usize;
            let next = tree[cur][bit];
            if next == 0 {
                return Err(HpackError("invalid huffman code"));
            }
            if next > 0 {
                cur = next as usize;
                pad_bits += 1;
                all_ones &= bit == 1;
                continue;
            }
            let sym = (-next - 1) as usize;
            if sym == EOS {
                return Err(HpackError("EOS in huffman string"));
            }
            out.push(sym as u8);
            cur = 0;
            pad_bits = 0;
            all_ones = true;
        }
    }
    if cur != 0 && (pad_bits > 7 || !all_ones) {
        return Err(HpackError("invalid huffman padding"));
    }
    Ok(out)
}

// ---------------------------------------------------------------------------
// Integers and strings
// ---------------------------------------------------------------------------

/// Append an HPACK integer with an `prefix`-bit prefix; `flags` are the high
/// bits of the first octet.
fn write_int(out: &mut Vec<u8>, prefix: u32, flags: u8, mut value: usize) {
    let max = (1usize << prefix) - 1;
    if value < max {
        out.push(flags | value as u8);
        return;
    }
    out.push(flags | max as u8);
    value -= max;
    while value >= 128 {
        out.push((value & 0x7f) as u8 | 0x80);
        value >>= 7;
    }
    out.push(value as u8);
}

fn read_int(buf: &[u8], pos: &mut usize, prefix: u32) -> Result<usize, HpackError> {
    let first = *buf.get(*pos).ok_or(HpackError("truncated integer"))?;
    *pos += 1;
    let max = (1usize << prefix) - 1;
    let mut value = (first as usize) & max;
    if value < max {
        return Ok(value);
    }
    let mut shift = 0u32;
    loop {
        let b = *buf.get(*pos).ok_or(HpackError("truncated integer"))?;
        *pos += 1;
        value += ((b & 0x7f) as usize) << shift;
        if value > u32::MAX as usize {
            return Err(HpackError("integer overflow"));
        }
        if b & 0x80 == 0 {
            return Ok(value);
        }
        shift += 7;
        if shift > 28 {
            return Err(HpackError("integer overflow"));
        }
    }
}

fn read_string(buf: &[u8], pos: &mut usize) -> Result<Vec<u8>, HpackError> {
    let huffman = buf.get(*pos).ok_or(HpackError("truncated string"))? & 0x80 != 0;
    let len = read_int(buf, pos, 7)?;
    let end = pos
        .checked_add(len)
        .filter(|&e| e <= buf.len())
        .ok_or(HpackError("truncated string"))?;
    let raw = &buf[*pos..end];
    *pos = end;
    if huffman {
        huffman_decode(raw)
    } else {
        Ok(raw.to_vec())
    }
}

fn write_string(out: &mut Vec<u8>, s: &[u8], huffman: bool) {
    if huffman {
        let hl = huffman_encoded_len(s);
        if hl <= s.len() {
            write_int(out, 7, 0x80, hl);
            huffman_encode(s, out);
            return;
        }
    }
    write_int(out, 7, 0, s.len());
    out.extend_from_slice(s);
}

// ---------------------------------------------------------------------------
// Dynamic table
// ---------------------------------------------------------------------------

#[derive(Debug)]
struct DynTable {
    entries: VecDeque<Header>,
    size: usize,
    max: usize,
}

impl DynTable {
    fn new(max: usize) -> Self {
        DynTable {
            entries: VecDeque::new(),
            size: 0,
            max,
        }
    }

    fn evict(&mut self) {
        while self.size > self.max {
            let Some((n, v)) = self.entries.pop_back() else {
                self.size = 0;
                return;
            };
            self.size -= n.len() + v.len() + ENTRY_OVERHEAD;
        }
    }

    fn set_max(&mut self, max: usize) {
        self.max = max;
        self.evict();
    }

    fn insert(&mut self, name: Vec<u8>, value: Vec<u8>) {
        let size = name.len() + value.len() + ENTRY_OVERHEAD;
        if size > self.max {
            self.entries.clear();
            self.size = 0;
            return;
        }
        self.size += size;
        self.entries.push_front((name, value));
        self.evict();
    }

    /// 1-based HPACK index across the static then dynamic table.
    fn get(&self, index: usize) -> Option<(&[u8], &[u8])> {
        if index == 0 {
            return None;
        }
        if index <= STATIC_TABLE.len() {
            let (n, v) = STATIC_TABLE[index - 1];
            return Some((n.as_bytes(), v.as_bytes()));
        }
        let (n, v) = self.entries.get(index - STATIC_TABLE.len() - 1)?;
        Some((n.as_slice(), v.as_slice()))
    }

    /// `(full match, name-only match)` indices.
    fn find(&self, name: &[u8], value: &[u8]) -> (Option<usize>, Option<usize>) {
        let mut name_idx = None;
        for (i, (n, v)) in STATIC_TABLE.iter().enumerate() {
            if n.as_bytes() != name {
                continue;
            }
            if v.as_bytes() == value {
                return (Some(i + 1), Some(i + 1));
            }
            name_idx.get_or_insert(i + 1);
        }
        for (i, (n, v)) in self.entries.iter().enumerate() {
            if n.as_slice() != name {
                continue;
            }
            let idx = STATIC_TABLE.len() + 1 + i;
            if v.as_slice() == value {
                return (Some(idx), Some(idx));
            }
            name_idx.get_or_insert(idx);
        }
        (None, name_idx)
    }
}

// ---------------------------------------------------------------------------
// Decoder
// ---------------------------------------------------------------------------

/// HPACK decoder with its own dynamic table.
#[derive(Debug)]
pub struct Decoder {
    table: DynTable,
    /// Largest table size the peer may select (our advertised setting).
    limit: usize,
}

impl Decoder {
    /// `limit` is the `SETTINGS_HEADER_TABLE_SIZE` the local endpoint advertised.
    pub fn new(limit: usize) -> Self {
        Decoder {
            table: DynTable::new(limit),
            limit,
        }
    }

    /// Decode one complete header block. The whole block is always consumed so
    /// the dynamic table stays in sync even when the list is too large; headers
    /// are collected only while the running size (RFC 7540 section 6.5.2: name +
    /// value + 32 per field) stays within `max_list`. Returns the headers and the
    /// total list size, which the caller compares against its limit.
    pub fn decode(
        &mut self,
        block: &[u8],
        max_list: usize,
    ) -> Result<(Vec<Header>, usize), HpackError> {
        let mut headers = Vec::new();
        let mut list_size = 0usize;
        let mut pos = 0usize;
        let mut seen_field = false;
        while pos < block.len() {
            let b = block[pos];
            if b & 0x80 != 0 {
                let idx = read_int(block, &mut pos, 7)?;
                let (n, v) = self.table.get(idx).ok_or(HpackError("bad index"))?;
                let field = (n.to_vec(), v.to_vec());
                seen_field = true;
                Self::collect(&mut headers, &mut list_size, max_list, field);
                continue;
            }
            if b & 0xe0 == 0x20 {
                if seen_field {
                    return Err(HpackError("table size update after field"));
                }
                let size = read_int(block, &mut pos, 5)?;
                if size > self.limit {
                    return Err(HpackError("table size update above limit"));
                }
                self.table.set_max(size);
                continue;
            }
            let (prefix, indexed) = if b & 0x40 != 0 { (6, true) } else { (4, false) };
            let idx = read_int(block, &mut pos, prefix)?;
            let name = if idx == 0 {
                read_string(block, &mut pos)?
            } else {
                let (n, _) = self.table.get(idx).ok_or(HpackError("bad index"))?;
                n.to_vec()
            };
            let value = read_string(block, &mut pos)?;
            if indexed {
                self.table.insert(name.clone(), value.clone());
            }
            seen_field = true;
            Self::collect(&mut headers, &mut list_size, max_list, (name, value));
        }
        Ok((headers, list_size))
    }

    fn collect(headers: &mut Vec<Header>, size: &mut usize, max: usize, field: Header) {
        *size = size.saturating_add(field.0.len() + field.1.len() + ENTRY_OVERHEAD);
        if *size <= max {
            headers.push(field);
        }
    }

    /// Current dynamic table size in bytes (for tests and diagnostics).
    pub fn table_size(&self) -> usize {
        self.table.size
    }
}

// ---------------------------------------------------------------------------
// Encoder
// ---------------------------------------------------------------------------

/// HPACK encoder with its own dynamic table.
#[derive(Debug)]
pub struct Encoder {
    table: DynTable,
    huffman: bool,
    /// Smallest size selected since the last block; announced before the next.
    pending_min: Option<usize>,
}

impl Encoder {
    /// `max_table` is the peer's `SETTINGS_HEADER_TABLE_SIZE` (capped by the
    /// caller). With `huffman`, strings use the Huffman code when it is no longer than the raw string.
    pub fn new(max_table: usize, huffman: bool) -> Self {
        Encoder {
            table: DynTable::new(max_table),
            huffman,
            pending_min: None,
        }
    }

    /// Change the table size; a size update is emitted before the next block.
    pub fn set_max_table_size(&mut self, size: usize) {
        if size == self.table.max {
            return;
        }
        self.pending_min = Some(self.pending_min.map_or(size, |m| m.min(size)));
        self.table.set_max(size);
    }

    /// Append the encoding of `headers` to `out`.
    pub fn encode(&mut self, headers: &[Header], out: &mut Vec<u8>) {
        if let Some(min) = self.pending_min.take() {
            if min < self.table.max {
                write_int(out, 5, 0x20, min);
            }
            write_int(out, 5, 0x20, self.table.max);
        }
        for (name, value) in headers {
            self.encode_field(name, value, out);
        }
    }

    fn encode_field(&mut self, name: &[u8], value: &[u8], out: &mut Vec<u8>) {
        let sensitive = name == b"authorization" || name == b"proxy-authorization";
        let (full, name_idx) = self.table.find(name, value);
        if let (Some(idx), false) = (full, sensitive) {
            write_int(out, 7, 0x80, idx);
            return;
        }
        let (prefix, flags) = if sensitive { (4, 0x10) } else { (6, 0x40) };
        match name_idx {
            Some(idx) => write_int(out, prefix, flags, idx),
            None => {
                write_int(out, prefix, flags, 0);
                write_string(out, name, self.huffman);
            }
        }
        write_string(out, value, self.huffman);
        if !sensitive {
            self.table.insert(name.to_vec(), value.to_vec());
        }
    }

    /// Current dynamic table size in bytes (for tests and diagnostics).
    pub fn table_size(&self) -> usize {
        self.table.size
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(s: &str) -> Vec<u8> {
        let s: String = s.split_whitespace().collect();
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
            .collect()
    }

    fn h(n: &str, v: &str) -> Header {
        (n.as_bytes().to_vec(), v.as_bytes().to_vec())
    }

    fn decode_all(d: &mut Decoder, block: &str) -> Vec<Header> {
        d.decode(&hex(block), usize::MAX).unwrap().0
    }

    #[test]
    fn integer_examples_c1() {
        // C.1.1: 10 with a 5-bit prefix.
        let mut out = Vec::new();
        write_int(&mut out, 5, 0, 10);
        assert_eq!(out, [0x0a]);
        // C.1.2: 1337 with a 5-bit prefix.
        out.clear();
        write_int(&mut out, 5, 0, 1337);
        assert_eq!(out, [0x1f, 0x9a, 0x0a]);
        let mut pos = 0;
        assert_eq!(read_int(&out, &mut pos, 5).unwrap(), 1337);
        // C.1.3: 42 at an octet boundary.
        out.clear();
        write_int(&mut out, 8, 0, 42);
        assert_eq!(out, [0x2a]);
    }

    #[test]
    fn integer_overflow_rejected() {
        let mut pos = 0;
        let buf = [0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01];
        assert!(read_int(&buf, &mut pos, 7).is_err());
    }

    #[test]
    fn literal_examples_c2() {
        let mut d = Decoder::new(4096);
        let got = decode_all(
            &mut d,
            "400a 6375 7374 6f6d 2d6b 6579 0d63 7573 746f 6d2d 6865 6164 6572",
        );
        assert_eq!(got, [h("custom-key", "custom-header")]);
        assert_eq!(d.table_size(), 55);

        let mut d = Decoder::new(4096);
        let got = decode_all(&mut d, "040c 2f73 616d 706c 652f 7061 7468");
        assert_eq!(got, [h(":path", "/sample/path")]);
        assert_eq!(d.table_size(), 0);

        let mut d = Decoder::new(4096);
        let got = decode_all(&mut d, "1008 7061 7373 776f 7264 0673 6563 7265 74");
        assert_eq!(got, [h("password", "secret")]);
        assert_eq!(d.table_size(), 0);

        let mut d = Decoder::new(4096);
        assert_eq!(decode_all(&mut d, "82"), [h(":method", "GET")]);
    }

    fn request_blocks(huffman: bool) -> [&'static str; 3] {
        if huffman {
            [
                "8286 8441 8cf1 e3c2 e5f2 3a6b a0ab 90f4 ff",
                "8286 84be 5886 a8eb 1064 9cbf",
                "8287 85bf 4088 25a8 49e9 5ba9 7d7f 8925 a849 e95b b8e8 b4bf",
            ]
        } else {
            [
                "8286 8441 0f77 7777 2e65 7861 6d70 6c65 2e63 6f6d",
                "8286 84be 5808 6e6f 2d63 6163 6865",
                "8287 85bf 400a 6375 7374 6f6d 2d6b 6579 0c63 7573 746f 6d2d 7661 6c75 65",
            ]
        }
    }

    fn requests() -> [Vec<Header>; 3] {
        let base = vec![
            h(":method", "GET"),
            h(":scheme", "http"),
            h(":path", "/"),
            h(":authority", "www.example.com"),
        ];
        let mut second = base.clone();
        second.push(h("cache-control", "no-cache"));
        let third = vec![
            h(":method", "GET"),
            h(":scheme", "https"),
            h(":path", "/index.html"),
            h(":authority", "www.example.com"),
            h("custom-key", "custom-value"),
        ];
        [base, second, third]
    }

    #[test]
    fn requests_c3_c4_decode_and_encode() {
        for huffman in [false, true] {
            let mut d = Decoder::new(4096);
            let mut e = Encoder::new(4096, huffman);
            let sizes = [57, 110, 164];
            for (i, (block, want)) in request_blocks(huffman).iter().zip(requests()).enumerate() {
                assert_eq!(
                    decode_all(&mut d, block),
                    want,
                    "decode huffman={huffman} #{i}"
                );
                assert_eq!(d.table_size(), sizes[i]);
                let mut out = Vec::new();
                e.encode(&want, &mut out);
                assert_eq!(out, hex(block), "encode huffman={huffman} #{i}");
                assert_eq!(e.table_size(), sizes[i]);
            }
        }
    }

    fn response_blocks(huffman: bool) -> [&'static str; 3] {
        if huffman {
            [
                "4882 6402 5885 aec3 771a 4b61 96d0 7abe 9410 54d4 44a8 2005 9504 0b81 66e0 82a6 \
                 2d1b ff6e 919d 29ad 1718 63c7 8f0b 97c8 e9ae 82ae 43d3",
                "4883 640e ffc1 c0bf",
                "88c1 6196 d07a be94 1054 d444 a820 0595 040b 8166 e084 a62d 1bff c05a 839b d9ab \
                 77ad 94e7 821d d7f2 e6c7 b335 dfdf cd5b 3960 d5af 2708 7f36 72c1 ab27 0fb5 291f \
                 9587 3160 65c0 03ed 4ee5 b106 3d50 07",
            ]
        } else {
            [
                "4803 3330 3258 0770 7269 7661 7465 611d 4d6f 6e2c 2032 3120 4f63 7420 3230 3133 \
                 2032 303a 3133 3a32 3120 474d 546e 1768 7474 7073 3a2f 2f77 7777 2e65 7861 6d70 \
                 6c65 2e63 6f6d",
                "4803 3330 37c1 c0bf",
                "88c1 611d 4d6f 6e2c 2032 3120 4f63 7420 3230 3133 2032 303a 3133 3a32 3220 474d \
                 54c0 5a04 677a 6970 7738 666f 6f3d 4153 444a 4b48 514b 425a 584f 5157 454f 5049 \
                 5541 5851 5745 4f49 553b 206d 6178 2d61 6765 3d33 3630 303b 2076 6572 7369 6f6e \
                 3d31",
            ]
        }
    }

    fn responses() -> [Vec<Header>; 3] {
        let loc = "https://www.example.com";
        let first = vec![
            h(":status", "302"),
            h("cache-control", "private"),
            h("date", "Mon, 21 Oct 2013 20:13:21 GMT"),
            h("location", loc),
        ];
        let second = vec![
            h(":status", "307"),
            h("cache-control", "private"),
            h("date", "Mon, 21 Oct 2013 20:13:21 GMT"),
            h("location", loc),
        ];
        let third = vec![
            h(":status", "200"),
            h("cache-control", "private"),
            h("date", "Mon, 21 Oct 2013 20:13:22 GMT"),
            h("location", loc),
            h("content-encoding", "gzip"),
            h(
                "set-cookie",
                "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1",
            ),
        ];
        [first, second, third]
    }

    #[test]
    fn responses_c5_c6_decode_and_encode_with_eviction() {
        for huffman in [false, true] {
            let mut d = Decoder::new(256);
            let mut e = Encoder::new(256, huffman);
            let sizes = [222, 222, 215];
            for (i, (block, want)) in response_blocks(huffman).iter().zip(responses()).enumerate() {
                assert_eq!(
                    decode_all(&mut d, block),
                    want,
                    "decode huffman={huffman} #{i}"
                );
                assert_eq!(d.table_size(), sizes[i]);
                let mut out = Vec::new();
                e.encode(&want, &mut out);
                assert_eq!(out, hex(block), "encode huffman={huffman} #{i}");
            }
        }
    }

    #[test]
    fn huffman_roundtrip_all_bytes() {
        let data: Vec<u8> = (0..=255u8).collect();
        let mut enc = Vec::new();
        huffman_encode(&data, &mut enc);
        assert_eq!(enc.len(), huffman_encoded_len(&data));
        assert_eq!(huffman_decode(&enc).unwrap(), data);
    }

    #[test]
    fn huffman_rejects_bad_padding_and_eos() {
        // 'a' is 00011 (5 bits); pad with zeros instead of ones.
        assert!(huffman_decode(&[0b0001_1000]).is_err());
        assert_eq!(huffman_decode(&[0b0001_1111]).unwrap(), b"a");
        // A full byte of padding (8 bits of ones) is too long.
        assert!(huffman_decode(&[0b0001_1111, 0xff]).is_err());
        // EOS (30 ones) inside the data.
        assert!(huffman_decode(&[0xff, 0xff, 0xff, 0xff]).is_err());
    }

    #[test]
    fn table_size_update_rules() {
        let mut d = Decoder::new(100);
        // Update above the advertised limit.
        assert!(d.decode(&hex("3fe1 1f"), usize::MAX).is_err());
        // Update after a field is invalid.
        assert!(d.decode(&hex("82 20"), usize::MAX).is_err());
        // Update before fields is fine.
        assert!(d.decode(&hex("20 82"), usize::MAX).is_ok());
    }

    #[test]
    fn bad_index_and_truncation() {
        let mut d = Decoder::new(4096);
        assert!(d.decode(&hex("80"), usize::MAX).is_err());
        assert!(d.decode(&hex("ff 7f"), usize::MAX).is_err());
        assert!(d.decode(&hex("40 05 61"), usize::MAX).is_err());
    }

    #[test]
    fn list_budget_keeps_table_in_sync() {
        let mut d = Decoder::new(4096);
        let block = hex("400a 6375 7374 6f6d 2d6b 6579 0d63 7573 746f 6d2d 6865 6164 6572 82");
        let (headers, size) = d.decode(&block, 60).unwrap();
        assert_eq!(headers, [h("custom-key", "custom-header")]);
        assert_eq!(size, 55 + 42);
        // The entry was inserted despite the budget.
        assert_eq!(d.table_size(), 55);
    }

    #[test]
    fn encoder_announces_size_changes() {
        let mut e = Encoder::new(4096, false);
        e.set_max_table_size(0);
        e.set_max_table_size(256);
        let mut out = Vec::new();
        e.encode(&[], &mut out);
        // Smallest (0) then final (256).
        assert_eq!(out, [0x20, 0x3f, 0xe1, 0x01]);
        let mut d = Decoder::new(4096);
        d.decode(&out, usize::MAX).unwrap();
    }

    #[test]
    fn sensitive_headers_never_indexed() {
        let mut e = Encoder::new(4096, false);
        let mut out = Vec::new();
        e.encode(&[h("authorization", "secret")], &mut out);
        assert_eq!(out[0] & 0xf0, 0x10);
        assert_eq!(e.table_size(), 0);
    }
}
