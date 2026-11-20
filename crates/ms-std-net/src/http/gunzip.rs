//! Gzip (RFC 1952) decoding of buffered response bodies over concatenated members, on zlib through the C runtime
//! (`ms_gunzip_*` in `runtime/std/compress.c`). A call reports how many input bytes it consumed, and the caller
//! offers the rest again with the next chunk.

use std::ffi::c_void;

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

const OK: u8 = 0;
const DONE: u8 = 1;
const TRUNCATED: u8 = 3;

unsafe extern "C" {
    fn ms_gunzip_new() -> *mut c_void;
    fn ms_gunzip_free(g: *mut c_void);
    fn ms_gunzip_step(
        g: *mut c_void,
        input: *const u8,
        in_len: usize,
        more: bool,
        out: *mut u8,
        out_cap: usize,
        in_used: *mut usize,
        out_used: *mut usize,
    ) -> u8;
}

/// The room reserved in the output before each step.
const CHUNK: usize = 64 * 1024;

/// A resumable gzip decoder over concatenated members.
pub struct Gunzip {
    handle: *mut c_void,
}

// SAFETY: the handle is owned by this value alone, and the C code keeps no thread-local state.
unsafe impl Send for Gunzip {}

impl Default for Gunzip {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for Gunzip {
    fn drop(&mut self) {
        // SAFETY: `handle` came from `ms_gunzip_new` and is freed once.
        unsafe { ms_gunzip_free(self.handle) }
    }
}

impl Gunzip {
    pub fn new() -> Gunzip {
        // SAFETY: no arguments; null (out of memory in zlib) is checked.
        let handle = unsafe { ms_gunzip_new() };
        assert!(!handle.is_null(), "inflateInit2 failed");
        Gunzip { handle }
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
        loop {
            // One byte past the limit proves it was passed.
            let room = limit.saturating_sub(out.len()).saturating_add(1);
            out.reserve(room.min(CHUNK));
            let spare = out.spare_capacity_mut();
            let cap = spare.len().min(room);
            let (mut used, mut made) = (0usize, 0usize);
            let rest = &input[pos..];
            // SAFETY: `rest` and the first `cap` spare bytes are valid; the step writes at most `cap` bytes
            // and reports how many it initialised.
            let status = unsafe {
                ms_gunzip_step(
                    self.handle,
                    rest.as_ptr(),
                    rest.len(),
                    more,
                    spare.as_mut_ptr().cast(),
                    cap,
                    &mut used,
                    &mut made,
                )
            };
            // SAFETY: the step initialised `made` bytes of the spare capacity.
            unsafe { out.set_len(out.len() + made) };
            pos += used;
            if out.len() > limit {
                return Err(Fail::Limit);
            }
            match status {
                OK if used == 0 && made == 0 => return Ok((pos, false)),
                OK => {}
                DONE => return Ok((pos, true)),
                TRUNCATED => return Err(Fail::Truncated),
                _ => return Err(Fail::Invalid),
            }
        }
    }
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
