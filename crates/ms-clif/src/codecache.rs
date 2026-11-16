//! Cache of Cranelift output: a function's machine code is a pure function of its Cranelift IR,
//! the target and the compiler, so it is stored under a hash of exactly that.
//!
//! One file per cache key holds a generation of entries: those this build used first, then the
//! older ones that still fit the size bound. A build that compiled anything writes the next
//! generation by atomic rename; a build that only hit writes nothing. A damaged file or entry is
//! a miss, never an error. Nothing here is a security boundary: the hash is a fast in-house
//! mix of two 64-bit lanes against accidental collisions, and the cache directory is as
//! trusted as the project's own build output.

use cranelift_codegen::binemit::Reloc;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// Bytes of one cache file; older generations are dropped past it.
pub const MAX_BYTES: usize = 128 << 20;

const MAGIC: &[u8; 8] = b"MSCLIF01";

/// A 128-bit hash of what a stream of writes contained. It is also a [`std::hash::Hasher`], so
/// a type that derives `Hash` can be hashed without formatting it.
#[derive(Clone)]
pub struct Hasher {
    a: u64,
    b: u64,
    len: u64,
    buf: [u8; 16],
    filled: usize,
}

const K1: u64 = 0x9e37_79b9_7f4a_7c15;
const K2: u64 = 0xd6e8_feb8_6659_fd93;
const K3: u64 = 0xa076_1d64_78bd_642f;

fn fold(a: u64, b: u64) -> u64 {
    let m = u128::from(a) * u128::from(b);
    (m as u64) ^ ((m >> 64) as u64)
}

impl Default for Hasher {
    fn default() -> Self {
        Hasher {
            a: K1,
            b: K2,
            len: 0,
            buf: [0; 16],
            filled: 0,
        }
    }
}

impl Hasher {
    fn block(&mut self, x: u64, y: u64) {
        let t = fold(x ^ K1, y ^ self.a);
        self.a = t;
        self.b = fold(self.b ^ x ^ K2, t ^ y ^ K3);
    }

    fn block_of(&mut self, c: &[u8]) {
        let x = u64::from_le_bytes(c[..8].try_into().expect("8 bytes"));
        let y = u64::from_le_bytes(c[8..16].try_into().expect("8 bytes"));
        self.block(x, y);
    }

    pub fn bytes(&mut self, mut data: &[u8]) {
        self.len += data.len() as u64;
        if self.filled > 0 {
            let take = (16 - self.filled).min(data.len());
            self.buf[self.filled..self.filled + take].copy_from_slice(&data[..take]);
            self.filled += take;
            data = &data[take..];
            if self.filled < 16 {
                return;
            }
            let full = self.buf;
            self.block_of(&full);
            self.filled = 0;
        }
        let (blocks, rest) = data.as_chunks::<16>();
        for c in blocks {
            self.block_of(c);
        }
        self.buf[..rest.len()].copy_from_slice(rest);
        self.filled = rest.len();
    }

    /// Writes a length-prefixed string, so adjacent strings cannot run together.
    pub fn text(&mut self, s: &str) {
        self.number(s.len() as u64);
        self.bytes(s.as_bytes());
    }

    pub fn number(&mut self, n: u64) {
        self.bytes(&n.to_le_bytes());
    }

    pub fn digest(&self) -> u128 {
        let mut tail = self.clone();
        let rest = tail.filled;
        tail.buf[rest..].fill(0);
        let (x, y) = (
            u64::from_le_bytes(tail.buf[..8].try_into().expect("8 bytes")),
            u64::from_le_bytes(tail.buf[8..].try_into().expect("8 bytes")),
        );
        tail.block(x, y ^ (rest as u64) << 56);
        let a = fold(tail.a ^ self.len, K2);
        let b = fold(tail.b ^ K3, a ^ K1);
        (u128::from(a) << 64) | u128::from(b)
    }
}

impl std::hash::Hasher for Hasher {
    fn write(&mut self, bytes: &[u8]) {
        self.bytes(bytes);
    }

    fn finish(&self) -> u64 {
        self.digest() as u64
    }
}

/// The relocations the cache can hold: Cranelift's relocation kinds, by position in this list.
const KINDS: [Reloc; 31] = [
    Reloc::Abs4,
    Reloc::Abs8,
    Reloc::X86PCRel4,
    Reloc::X86CallPCRel4,
    Reloc::X86CallPLTRel4,
    Reloc::X86GOTPCRel4,
    Reloc::X86SecRel,
    Reloc::Arm32Call,
    Reloc::Arm64Call,
    Reloc::S390xPCRel32Dbl,
    Reloc::S390xPLTRel32Dbl,
    Reloc::ElfX86_64TlsGd,
    Reloc::MachOX86_64Tlv,
    Reloc::MachOAarch64TlsAdrPage21,
    Reloc::MachOAarch64TlsAdrPageOff12,
    Reloc::Aarch64TlsDescAdrPage21,
    Reloc::Aarch64TlsDescLd64Lo12,
    Reloc::Aarch64TlsDescAddLo12,
    Reloc::Aarch64TlsDescCall,
    Reloc::Aarch64AdrGotPage21,
    Reloc::Aarch64AdrPrelPgHi21,
    Reloc::Aarch64AddAbsLo12Nc,
    Reloc::Aarch64Ld64GotLo12Nc,
    Reloc::RiscvCallPlt,
    Reloc::RiscvTlsGdHi20,
    Reloc::RiscvPCRelLo12I,
    Reloc::RiscvGotHi20,
    Reloc::RiscvPCRelHi20,
    Reloc::S390xTlsGd64,
    Reloc::S390xTlsGdCall,
    Reloc::PulleyPcRel,
];

/// The position of `kind` in [`KINDS`], or `None` for a kind the cache does not know.
pub fn kind_code(kind: Reloc) -> Option<u8> {
    KINDS.iter().position(|k| *k == kind).map(|i| i as u8)
}

/// What a relocation points at: the function's own list of user names (by position) or a
/// library function by its name.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Target {
    User(u32),
    LibCall(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CachedReloc {
    pub offset: u32,
    pub kind: Reloc,
    pub target: Target,
    pub addend: i64,
}

/// One source row of the code: `[start, end)` belongs to `file:line` in `scope`, where `scope`
/// is 0 for the function itself and otherwise relative to the function's own scopes.
pub type Row = (u32, u32, u32, u32, u32);

/// Where a value label lives over a range of code, by DWARF register (`Some`) or by frame offset.
pub type LabelRange = (u32, u32, Option<u16>, i64);

/// The code ranges of the value labels a function's named values use, by label.
pub type Labels = Vec<(u32, Vec<LabelRange>)>;

/// What compiling one function produced that later stages read.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Cached {
    pub alignment: u32,
    pub code: Vec<u8>,
    pub relocs: Vec<CachedReloc>,
    pub rows: Vec<Row>,
    pub labels: Labels,
}

fn put(out: &mut Vec<u8>, n: u32) {
    out.extend_from_slice(&n.to_le_bytes());
}

impl Cached {
    pub fn encode(&self) -> Vec<u8> {
        let mut o = Vec::with_capacity(self.code.len() + 64 + self.relocs.len() * 20);
        put(&mut o, self.alignment);
        put(&mut o, self.code.len() as u32);
        o.extend_from_slice(&self.code);
        put(&mut o, self.relocs.len() as u32);
        for r in &self.relocs {
            put(&mut o, r.offset);
            o.push(kind_code(r.kind).expect("encodable kind"));
            match &r.target {
                Target::User(i) => {
                    o.push(0);
                    put(&mut o, *i);
                }
                Target::LibCall(name) => {
                    o.push(1);
                    o.push(name.len() as u8);
                    o.extend_from_slice(name.as_bytes());
                }
            }
            o.extend_from_slice(&r.addend.to_le_bytes());
        }
        put(&mut o, self.rows.len() as u32);
        for r in &self.rows {
            for n in [r.0, r.1, r.2, r.3, r.4] {
                put(&mut o, n);
            }
        }
        put(&mut o, self.labels.len() as u32);
        for (label, ranges) in &self.labels {
            put(&mut o, *label);
            put(&mut o, ranges.len() as u32);
            for &(start, end, reg, offset) in ranges {
                put(&mut o, start);
                put(&mut o, end);
                match reg {
                    Some(r) => {
                        o.push(1);
                        o.extend_from_slice(&r.to_le_bytes());
                    }
                    None => o.push(0),
                }
                o.extend_from_slice(&offset.to_le_bytes());
            }
        }
        o
    }

    /// `None` when the bytes are not a well-formed entry.
    pub fn decode(bytes: &[u8]) -> Option<Cached> {
        let mut c = Cursor { bytes, at: 0 };
        let alignment = c.u32()?;
        let n = c.u32()? as usize;
        let code = c.take(n)?.to_vec();
        let n = c.u32()? as usize;
        let mut relocs = Vec::with_capacity(n.min(1 << 16));
        for _ in 0..n {
            let offset = c.u32()?;
            let kind = *KINDS.get(usize::from(c.u8()?))?;
            let target = match c.u8()? {
                0 => Target::User(c.u32()?),
                1 => {
                    let len = usize::from(c.u8()?);
                    Target::LibCall(String::from_utf8(c.take(len)?.to_vec()).ok()?)
                }
                _ => return None,
            };
            let addend = c.i64()?;
            relocs.push(CachedReloc {
                offset,
                kind,
                target,
                addend,
            });
        }
        let n = c.u32()? as usize;
        let mut rows = Vec::with_capacity(n.min(1 << 16));
        for _ in 0..n {
            rows.push((c.u32()?, c.u32()?, c.u32()?, c.u32()?, c.u32()?));
        }
        let n = c.u32()? as usize;
        let mut labels = Vec::with_capacity(n.min(1 << 12));
        for _ in 0..n {
            let label = c.u32()?;
            let m = c.u32()? as usize;
            let mut ranges = Vec::with_capacity(m.min(1 << 12));
            for _ in 0..m {
                let (start, end) = (c.u32()?, c.u32()?);
                let reg = match c.u8()? {
                    0 => None,
                    1 => Some(u16::from_le_bytes(c.take(2)?.try_into().ok()?)),
                    _ => return None,
                };
                ranges.push((start, end, reg, c.i64()?));
            }
            labels.push((label, ranges));
        }
        (c.at == bytes.len()).then_some(Cached {
            alignment,
            code,
            relocs,
            rows,
            labels,
        })
    }
}

struct Cursor<'a> {
    bytes: &'a [u8],
    at: usize,
}

impl Cursor<'_> {
    fn take(&mut self, n: usize) -> Option<&[u8]> {
        let end = self.at.checked_add(n)?;
        let s = self.bytes.get(self.at..end)?;
        self.at = end;
        Some(s)
    }
    fn u8(&mut self) -> Option<u8> {
        Some(self.take(1)?[0])
    }
    fn u32(&mut self) -> Option<u32> {
        Some(u32::from_le_bytes(self.take(4)?.try_into().ok()?))
    }
    fn i64(&mut self) -> Option<i64> {
        Some(i64::from_le_bytes(self.take(8)?.try_into().ok()?))
    }
}

/// The entries of the cache file as of the start of a build, and what this build adds.
pub struct Store {
    path: PathBuf,
    old: Vec<u8>,
    /// Entry key to the byte range of its encoding in `old`.
    index: HashMap<u128, (usize, usize)>,
    /// Keys in the order this build used them.
    used: Vec<u128>,
    fresh: Vec<(u128, Vec<u8>)>,
    pub hits: usize,
    pub misses: usize,
}

impl Store {
    /// Opens the cache file named `name` in `dir`. A missing, unreadable or damaged file is an
    /// empty cache; a directory that cannot be created turns the cache off (`None`).
    pub fn open(dir: &Path, name: &str) -> Option<Store> {
        std::fs::create_dir_all(dir).ok()?;
        let path = dir.join(format!("code-{name}.bin"));
        let old = std::fs::read(&path).unwrap_or_default();
        let index = parse_index(&old).unwrap_or_default();
        Some(Store {
            path,
            old,
            index,
            used: Vec::new(),
            fresh: Vec::new(),
            hits: 0,
            misses: 0,
        })
    }

    pub fn get(&mut self, key: u128) -> Option<Cached> {
        let found = self
            .index
            .get(&key)
            .and_then(|&(at, len)| Cached::decode(&self.old[at..at + len]));
        if found.is_some() {
            self.hits += 1;
            self.used.push(key);
        } else {
            self.misses += 1;
        }
        found
    }

    pub fn insert(&mut self, key: u128, entry: &Cached) {
        self.fresh.push((key, entry.encode()));
    }

    /// Writes the next generation when this build compiled anything.
    pub fn save(self) {
        if self.fresh.is_empty() {
            return;
        }
        let mut out = Vec::with_capacity(self.old.len().min(MAX_BYTES));
        out.extend_from_slice(MAGIC);
        let mut written = std::collections::HashSet::new();
        let mut entry = |out: &mut Vec<u8>, key: u128, bytes: &[u8]| {
            if out.len() + bytes.len() + 20 > MAX_BYTES || !written.insert(key) {
                return;
            }
            out.extend_from_slice(&key.to_le_bytes());
            put(out, bytes.len() as u32);
            out.extend_from_slice(bytes);
        };
        for (key, bytes) in &self.fresh {
            entry(&mut out, *key, bytes);
        }
        for key in &self.used {
            let (at, len) = self.index[key];
            entry(&mut out, *key, &self.old[at..at + len]);
        }
        // Older entries keep their order, so the ones nothing has used lately fall off the end.
        for (key, at, len) in parse_entries(&self.old).unwrap_or_default() {
            entry(&mut out, key, &self.old[at..at + len]);
        }
        let temp = self
            .path
            .with_extension(format!("tmp{}", std::process::id()));
        if std::fs::write(&temp, &out).is_err() || std::fs::rename(&temp, &self.path).is_err() {
            let _ = std::fs::remove_file(&temp);
        }
    }
}

fn parse_entries(bytes: &[u8]) -> Option<Vec<(u128, usize, usize)>> {
    if bytes.get(..8)? != MAGIC {
        return None;
    }
    let mut at = 8;
    let mut out = Vec::new();
    while at < bytes.len() {
        let key = u128::from_le_bytes(bytes.get(at..at + 16)?.try_into().ok()?);
        let len = u32::from_le_bytes(bytes.get(at + 16..at + 20)?.try_into().ok()?) as usize;
        at += 20;
        bytes.get(at..at.checked_add(len)?)?;
        out.push((key, at, len));
        at += len;
    }
    Some(out)
}

fn parse_index(bytes: &[u8]) -> Option<HashMap<u128, (usize, usize)>> {
    Some(
        parse_entries(bytes)?
            .into_iter()
            .map(|(k, at, len)| (k, (at, len)))
            .collect(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Cached {
        Cached {
            alignment: 16,
            code: vec![1, 2, 3, 4, 5],
            relocs: vec![
                CachedReloc {
                    offset: 4,
                    kind: Reloc::X86CallPLTRel4,
                    target: Target::User(2),
                    addend: -4,
                },
                CachedReloc {
                    offset: 9,
                    kind: Reloc::Abs8,
                    target: Target::LibCall("Memcpy".into()),
                    addend: 0,
                },
            ],
            rows: vec![(0, 3, 1, 10, 0), (3, 5, 1, 11, 2)],
            labels: vec![(7, vec![(0, 5, Some(3), 0), (5, 9, None, -16)])],
        }
    }

    #[test]
    fn entries_round_trip_and_reject_damage() {
        let entry = sample();
        let bytes = entry.encode();
        assert_eq!(Cached::decode(&bytes), Some(entry));
        assert_eq!(Cached::decode(&bytes[..bytes.len() - 1]), None);
        let mut longer = bytes.clone();
        longer.push(0);
        assert_eq!(Cached::decode(&longer), None);
    }

    #[test]
    fn hash_separates_inputs() {
        let h = |texts: &[&str]| {
            let mut h = Hasher::default();
            for t in texts {
                h.text(t);
            }
            h.digest()
        };
        assert_eq!(h(&["ab", "c"]), h(&["ab", "c"]));
        assert_ne!(h(&["ab", "c"]), h(&["a", "bc"]));
        assert_ne!(h(&["abcdefghijklmnopq"]), h(&["abcdefghijklmnopr"]));
    }

    #[test]
    fn generations_keep_used_entries_and_drop_past_the_bound() {
        let dir = std::env::temp_dir().join(format!("ms-codecache-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let mut s = Store::open(&dir, "t").unwrap();
        assert!(s.get(1).is_none());
        s.insert(1, &sample());
        s.insert(2, &sample());
        s.save();
        let mut s = Store::open(&dir, "t").unwrap();
        assert_eq!(s.get(1), Some(sample()));
        s.insert(3, &sample());
        s.save();
        let mut s = Store::open(&dir, "t").unwrap();
        assert!(s.get(1).is_some() && s.get(2).is_some() && s.get(3).is_some());
        // A damaged file is an empty cache.
        std::fs::write(dir.join("code-t.bin"), b"garbage").unwrap();
        let mut s = Store::open(&dir, "t").unwrap();
        assert!(s.get(1).is_none());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
