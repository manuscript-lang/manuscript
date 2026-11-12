//! Differential check against flate2 (miniz_oxide) on random, compressed and corrupted streams.

use flate2::Compression;
use flate2::read::DeflateDecoder;
use flate2::write::DeflateEncoder;
use ms_inflate::{Fail, Inflater};
use std::io::{Read, Write};

fn rng(x: &mut u64) -> u64 {
    *x ^= *x << 13;
    *x ^= *x >> 7;
    *x ^= *x << 17;
    *x
}

/// Our verdict and output on `z` in `chunk`-byte pieces.
fn ours(z: &[u8], chunk: usize) -> Result<Vec<u8>, Fail> {
    let mut inf = Inflater::new(0);
    let mut out = Vec::new();
    let mut pending = Vec::new();
    let mut chunks = z.chunks(chunk);
    loop {
        let next = chunks.next();
        pending.extend_from_slice(next.unwrap_or(&[]));
        let more = next.is_some();
        let (used, done) = inf.push(&pending, more, &mut out, usize::MAX)?;
        pending.drain(..used);
        if done {
            return Ok(out);
        }
    }
}

fn reference(z: &[u8]) -> Option<Vec<u8>> {
    let mut out = Vec::new();
    DeflateDecoder::new(z).read_to_end(&mut out).ok()?;
    Some(out)
}

fn sample(x: &mut u64, n: usize) -> Vec<u8> {
    let alphabet = [2u64, 4, 16, 256][(rng(x) % 4) as usize];
    let mut data = Vec::with_capacity(n);
    while data.len() < n {
        match rng(x) % 3 {
            0 => data.push((rng(x) % alphabet) as u8),
            1 if !data.is_empty() => {
                let from = (rng(x) as usize) % data.len();
                let len = (rng(x) % 300) as usize;
                for i in 0..len {
                    data.push(data[from + i % (data.len() - from)]);
                }
            }
            _ => data.extend(vec![(rng(x) % alphabet) as u8; (rng(x) % 50) as usize]),
        }
    }
    data.truncate(n);
    data
}

/// A valid stream decodes to its input at any chunking; a corrupted one either fails or agrees
/// with flate2 on the bytes.
#[test]
fn agrees_with_flate2_on_random_and_corrupted_streams() {
    let mut x = 0x9e37_79b9_7f4a_7c15u64;
    let rounds = std::env::var("ROUNDS")
        .ok()
        .and_then(|r| r.parse().ok())
        .unwrap_or(3000);
    for round in 0..rounds {
        let n = (rng(&mut x) % 40_000) as usize;
        let data = sample(&mut x, n);
        let level = (rng(&mut x) % 10) as u32;
        let mut e = DeflateEncoder::new(Vec::new(), Compression::new(level));
        e.write_all(&data).unwrap();
        let mut z = e.finish().unwrap();
        let corrupt = round % 3 != 0 && !z.is_empty();
        if corrupt {
            for _ in 0..1 + rng(&mut x) % 3 {
                let at = (rng(&mut x) as usize) % z.len();
                z[at] ^= 1 << (rng(&mut x) % 8);
            }
        }
        let chunk = [1usize, 5, 64, 1000, usize::MAX][(rng(&mut x) % 5) as usize];
        let got = ours(&z, chunk.min(z.len().max(1)));
        match (reference(&z), got) {
            (want, Ok(got)) => {
                // We accept: flate2 must agree on the bytes (it may also reject what we accept).
                if let Some(want) = want {
                    assert!(want == got, "round {round}: output differs");
                }
                if !corrupt {
                    assert!(got == data, "round {round}: lost data");
                }
            }
            // miniz accepts back-references before the start of the output; zlib and we do not.
            (_, Err(e)) => assert!(corrupt, "round {round}: valid stream failed with {e:?}"),
        }
    }
}
