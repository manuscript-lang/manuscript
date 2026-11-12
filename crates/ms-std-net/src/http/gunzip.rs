//! Gzip (RFC 1952) framing for buffered response bodies over the shared inflater: the header, the
//! CRC-32 and length trailer, and concatenated members. A call reports how many input bytes it
//! consumed, and the caller offers the rest again with the next chunk.

use crc32fast::Hasher;
use ms_inflate::Inflater;

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

impl From<ms_inflate::Fail> for Fail {
    fn from(f: ms_inflate::Fail) -> Fail {
        match f {
            ms_inflate::Fail::Invalid => Fail::Invalid,
            ms_inflate::Fail::Truncated => Fail::Truncated,
            ms_inflate::Fail::Limit => Fail::Limit,
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Phase {
    /// At a member boundary, before the gzip header.
    Header,
    /// Inside a member's deflate stream.
    Body,
    /// After the deflate stream, before the 8-byte trailer.
    Trailer,
}

/// A resumable gzip decoder over concatenated members.
pub struct Gunzip {
    phase: Phase,
    inflater: Inflater,
    crc: Hasher,
    /// Output length when the current member began.
    base: usize,
    /// Output length up to which `crc` has been updated.
    crc_done: usize,
    members: usize,
}

impl Default for Gunzip {
    fn default() -> Self {
        Self::new()
    }
}

impl Gunzip {
    pub fn new() -> Gunzip {
        Gunzip {
            phase: Phase::Header,
            inflater: Inflater::new(0),
            crc: Hasher::new(),
            base: 0,
            crc_done: 0,
            members: 0,
        }
    }

    /// Decodes `input`, appending to `out`, which must only grow between calls. `more` says whether
    /// input will follow. Output past `limit` bytes of `out` fails with `Limit`. Returns the bytes of
    /// `input` consumed and whether the stream ended cleanly: `more` is false and every member is
    /// complete.
    pub fn push(
        &mut self,
        input: &[u8],
        more: bool,
        out: &mut Vec<u8>,
        limit: usize,
    ) -> Result<(usize, bool), Fail> {
        let mut pos = 0;
        // Input ran out at `pos`: wait for more, or fail when none can come.
        let need = |pos: usize| {
            if more {
                Ok((pos, false))
            } else {
                Err(Fail::Truncated)
            }
        };
        loop {
            match self.phase {
                Phase::Header => {
                    let rest = &input[pos..];
                    if rest.is_empty() && !more && self.members > 0 {
                        return Ok((pos, true));
                    }
                    match gzip_header(rest)? {
                        None => return need(pos),
                        Some(n) => pos += n,
                    }
                    self.base = out.len();
                    self.crc_done = out.len();
                    self.crc = Hasher::new();
                    self.inflater = Inflater::new(out.len());
                    self.phase = Phase::Body;
                }
                Phase::Body => {
                    let result = self.inflater.push(&input[pos..], more, out, limit);
                    let (used, done) = result?;
                    pos += used;
                    self.flush_crc(out);
                    if !done {
                        return Ok((pos, false));
                    }
                    self.phase = Phase::Trailer;
                }
                Phase::Trailer => {
                    let rest = &input[pos..];
                    if rest.len() < 8 {
                        return need(pos);
                    }
                    let crc = u32::from_le_bytes([rest[0], rest[1], rest[2], rest[3]]);
                    let size = u32::from_le_bytes([rest[4], rest[5], rest[6], rest[7]]);
                    let made = (out.len() - self.base) as u32;
                    if crc != self.crc.clone().finalize() || size != made {
                        return Err(Fail::Invalid);
                    }
                    pos += 8;
                    self.members += 1;
                    self.phase = Phase::Header;
                }
            }
        }
    }

    fn flush_crc(&mut self, out: &[u8]) {
        if out.len() > self.crc_done {
            self.crc.update(&out[self.crc_done..]);
            self.crc_done = out.len();
        }
    }
}

/// Length of the gzip header at the start of `rest`, or `Need` when it is cut short.
fn gzip_header(rest: &[u8]) -> Result<Option<usize>, Fail> {
    if rest.len() < 10 {
        // Even a short prefix must look like a header.
        let magic = [0x1f, 0x8b, 8];
        if rest.iter().zip(magic).any(|(a, b)| *a != b) {
            return Err(Fail::Invalid);
        }
        return Ok(None);
    }
    if rest[0] != 0x1f || rest[1] != 0x8b || rest[2] != 8 || rest[3] & 0xe0 != 0 {
        return Err(Fail::Invalid);
    }
    let flags = rest[3];
    let mut at = 10;
    if flags & 4 != 0 {
        let Some(len) = rest.get(at..at + 2) else {
            return Ok(None);
        };
        at += 2 + u16::from_le_bytes([len[0], len[1]]) as usize;
    }
    for flag in [8u8, 16] {
        if flags & flag != 0 {
            let Some(end) = rest.get(at..).and_then(|r| r.iter().position(|&b| b == 0)) else {
                return Ok(None);
            };
            at += end + 1;
        }
    }
    if flags & 2 != 0 {
        at += 2;
    }
    if rest.len() < at {
        return Ok(None);
    }
    Ok(Some(at))
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
        let mut inflater = Gunzip::new();
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
        let mut inflater = Gunzip::new();
        let mut out = Vec::new();
        assert_eq!(
            inflater.push(&z, false, &mut out, 99_999).map(|_| ()),
            Err(Fail::Limit)
        );
        let mut inflater = Gunzip::new();
        let mut out = Vec::new();
        assert!(inflater.push(&z, false, &mut out, 100_000).unwrap().1);
        assert_eq!(out.len(), 100_000);
        let stored = gzip(&vec![7u8; 5000], 0);
        let mut inflater = Gunzip::new();
        let mut out = Vec::new();
        assert_eq!(
            inflater.push(&stored, false, &mut out, 4999).map(|_| ()),
            Err(Fail::Limit)
        );
    }

    #[test]
    fn appends_after_existing_output() {
        let z = gzip(b"payload payload payload", 6);
        let mut inflater = Gunzip::new();
        let mut out = b"prefix:".to_vec();
        let (_, done) = inflater.push(&z, false, &mut out, usize::MAX).unwrap();
        assert!(done);
        assert_eq!(out, b"prefix:payload payload payload");
    }
}
