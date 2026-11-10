//! Replays `tests/oracle/stream.tsv` (Go `decompress_stream` results for chunked input), and
//! round-trips the streaming encoder.
// Links the msrt_* runtime symbols.
use ms_rt as _;
use ms_rt::ffi::Fail;
use ms_std_archive::compress::compress;
use ms_std_archive::compress::{Decoder, Encoder, Format, crc32, decompress_bytes};
use std::collections::HashMap;

fn bytes(tok: &str) -> Vec<u8> {
    let h = tok.strip_prefix('x').expect("hex token");
    (0..h.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&h[i..i + 2], 16).unwrap())
        .collect()
}

fn decode(format: Format, max: Option<i64>, input: &[u8], chunk: usize) -> (Vec<u8>, String) {
    let mut d = Decoder::new(format, max);
    let mut out = Vec::new();
    for c in input.chunks(chunk) {
        match d.push(c) {
            Ok(b) => out.extend_from_slice(&b),
            Err(Fail::LimitExceeded) => return (out, "err LimitExceeded".into()),
            Err(_) => return (out, "err InvalidData".into()),
        }
    }
    match d.end() {
        Ok(b) => out.extend_from_slice(&b),
        Err(Fail::LimitExceeded) => return (out, "err LimitExceeded".into()),
        Err(_) => return (out, "err InvalidData".into()),
    }
    (out, "ok".into())
}

#[test]
fn decode_matches_oracle() {
    let data = include_str!("oracle/stream.tsv");
    let mut inputs: HashMap<String, Vec<u8>> = HashMap::new();
    let mut n = 0;
    for line in data.lines().filter(|l| !l.starts_with('#')) {
        let f: Vec<&str> = line.split('\t').collect();
        if f[0] == "in" {
            inputs.insert(f[1].into(), bytes(f[2]));
            continue;
        }
        let format = Format::from_name(f[1]).unwrap();
        let max = (f[3] != "-").then(|| f[3].parse().unwrap());
        let (out, status) = decode(format, max, &inputs[f[2]], f[4].parse().unwrap());
        // Output delivered before an error depends on the input chunking, so only the error and
        // the limit are compared; complete outputs match exactly.
        if status == "ok" {
            let got = format!("{}\t{:x}\t{}", out.len(), crc32(0, &out), status);
            assert_eq!(got, f[7..].join("\t"), "{line}");
        } else {
            assert_eq!(status, f[9], "{line}");
            if let Some(max) = max {
                assert!(i64::try_from(out.len()).unwrap() <= max.max(0), "{line}");
            }
        }
        n += 1;
    }
    assert!(n > 1000, "only {n} cases");
}

#[test]
fn encoder_roundtrips() {
    let big: Vec<u8> = (0..300_000u32).map(|i| (i * 7 % 253) as u8).collect();
    for format in [Format::Gzip, Format::Zlib, Format::Deflate] {
        for level in [0, 1, 6, 9] {
            for data in [&b""[..], b"hello hello hello", &big] {
                for chunk in [1usize, 777, 40_000] {
                    let mut e = Encoder::new(format, level).unwrap();
                    let mut packed = Vec::new();
                    for c in data.chunks(chunk) {
                        packed.extend(e.push(c));
                    }
                    packed.extend(e.end());
                    let name = match format {
                        Format::Gzip => "gzip",
                        Format::Zlib => "zlib",
                        Format::Deflate => "deflate",
                    };
                    assert_eq!(
                        decompress_bytes(&packed, name, None).unwrap(),
                        data,
                        "{name} {level} {chunk}"
                    );
                }
            }
        }
    }
    assert!(Encoder::new(Format::Gzip, 10).is_err());
    assert!(Encoder::new(Format::Gzip, -1).is_err());
}

#[test]
fn small_chunks_preserve_dictionary_wraps_and_gzip_members() {
    let data: Vec<u8> = (0..65_539u32).map(|i| (i * 7 % 253) as u8).collect();
    for name in ["gzip", "zlib", "deflate"] {
        let format = Format::from_name(name).unwrap();
        let packed = compress(&data, name, 6, None).unwrap();
        for chunk in [1, 32768] {
            let (out, status) = decode(format, None, &packed, chunk);
            assert_eq!(status, "ok", "{name} {chunk}");
            assert_eq!(out, data, "{name} {chunk}");
        }
    }
    let mut members = compress(&data, "gzip", 6, None).unwrap();
    members.extend(compress(b"next member", "gzip", 6, None).unwrap());
    let (mut out, status) = decode(Format::Gzip, None, &members, 31);
    assert_eq!(status, "ok");
    assert_eq!(out.split_off(data.len()), b"next member");
    assert_eq!(out, data);
}

#[test]
fn limits_and_bad_trailers_remain_terminal() {
    let data: Vec<u8> = (0..65_539u32).map(|i| (i % 251) as u8).collect();
    for name in ["gzip", "zlib", "deflate"] {
        let format = Format::from_name(name).unwrap();
        let packed = compress(&data, name, 6, None).unwrap();
        for limit in [-1, 0, 1, 7, 32768, data.len() as i64 - 1] {
            let mut d = Decoder::new(format, Some(limit));
            assert_eq!(d.push(&packed), Err(Fail::LimitExceeded), "{name} {limit}");
            assert_eq!(d.push(b""), Err(Fail::LimitExceeded));
            assert_eq!(d.end(), Err(Fail::LimitExceeded));
        }
    }
    let mut packed = compress(&data, "gzip", 6, None).unwrap();
    let trailer = packed.len() - 8;
    packed[trailer] ^= 1;
    let mut d = Decoder::new(Format::Gzip, None);
    assert_eq!(d.push(&packed), Err(Fail::InvalidData));
    assert_eq!(d.end(), Err(Fail::InvalidData));
}

/// Adds all optional fields selected by `flags`, including a valid header CRC when requested.
fn gzip_with_flags(flags: u8) -> Vec<u8> {
    let packed = compress(b"gzip flags", "gzip", 6, None).unwrap();
    let mut header = packed[..10].to_vec();
    header[3] = flags;
    if flags & 4 != 0 {
        header.extend_from_slice(&[3, 0, 0, 0xff, 0x42]);
    }
    if flags & 8 != 0 {
        header.extend_from_slice(b"name.txt\0");
    }
    if flags & 16 != 0 {
        header.extend_from_slice(b"comment\0");
    }
    if flags & 2 != 0 {
        header.extend_from_slice(&(crc32(0, &header) as u16).to_le_bytes());
    }
    header.extend_from_slice(&packed[10..]);
    header
}

#[test]
fn gzip_rejects_reserved_flags_in_every_member() {
    let first = compress(b"first", "gzip", 6, None).unwrap();
    for flags in [0x20, 0x40, 0x80, 0xe0, 0xff] {
        let bad = gzip_with_flags(flags);
        for input in [bad.clone(), [first.clone(), bad].concat()] {
            assert_eq!(
                decompress_bytes(&input, "gzip", None),
                Err(Fail::InvalidData),
                "flags {flags:#04x}"
            );
            for chunk in [1, 9, input.len()] {
                assert_eq!(
                    decode(Format::Gzip, None, &input, chunk).1,
                    "err InvalidData",
                    "flags {flags:#04x}, chunk {chunk}"
                );
            }
            let mut decoder = Decoder::new(Format::Gzip, None);
            assert_eq!(decoder.push(&input), Err(Fail::InvalidData));
            assert_eq!(decoder.push(&[]), Err(Fail::InvalidData));
            assert_eq!(decoder.end(), Err(Fail::InvalidData));
        }
    }
}

#[test]
fn gzip_accepts_every_legal_flag_combination() {
    for flags in 0..=0x1f {
        let input = gzip_with_flags(flags);
        assert_eq!(
            decompress_bytes(&input, "gzip", None).unwrap(),
            b"gzip flags"
        );
        for chunk in [1, 9, input.len()] {
            let (output, status) = decode(Format::Gzip, None, &input, chunk);
            assert_eq!(status, "ok", "flags {flags:#04x}, chunk {chunk}");
            assert_eq!(output, b"gzip flags");
        }
    }
}

/// Deterministic xorshift for reproducible random chunk splits.
fn next(state: &mut u64) -> u64 {
    *state ^= *state << 13;
    *state ^= *state >> 7;
    *state ^= *state << 17;
    *state
}

fn decode_split(
    format: Format,
    max: Option<i64>,
    input: &[u8],
    rng: &mut u64,
) -> Result<Vec<u8>, Fail> {
    let mut d = Decoder::new(format, max);
    let mut out = Vec::new();
    let mut rest = input;
    while !rest.is_empty() {
        let n = (next(rng) % 40 + 1).min(rest.len() as u64) as usize;
        out.extend(d.push(&rest[..n])?);
        rest = &rest[n..];
    }
    out.extend(d.end()?);
    Ok(out)
}

/// The one-shot call and the stream decoder agree on every input, whatever the chunk split:
/// valid, truncated, with a tail, and with a flipped byte.
#[test]
fn one_shot_and_random_chunk_splits_agree() {
    let text: Vec<u8> = b"differential zlib gzip deflate ".repeat(60);
    let mut rng = 0x9e37_79b9_7f4a_7c15u64;
    for name in ["gzip", "zlib", "deflate"] {
        let format = Format::from_name(name).unwrap();
        let packed = compress(&text, name, 6, None).unwrap();
        let mut cases: Vec<Vec<u8>> = vec![
            packed.clone(),
            packed[..packed.len() - 1].to_vec(),
            Vec::new(),
        ];
        let mut tail = packed.clone();
        tail.extend_from_slice(b"junk");
        cases.push(tail);
        for i in 0..packed.len() {
            let mut flipped = packed.clone();
            flipped[i] ^= 1 << (next(&mut rng) % 8);
            cases.push(flipped);
        }
        for max in [
            None,
            Some(0),
            Some(text.len() as i64 - 1),
            Some(text.len() as i64),
        ] {
            for case in &cases {
                let whole = decompress_bytes(case, name, max);
                for _ in 0..4 {
                    assert_eq!(
                        decode_split(format, max, case, &mut rng),
                        whole,
                        "{name} {max:?}"
                    );
                }
            }
        }
    }
}

/// A back-reference that reaches before the start of the output is `InvalidData` in the stream
/// decoder and the one-shot call alike (the wrapping dictionary alone would read stale bytes).
#[test]
fn reference_before_output_start_is_invalid() {
    let h = "2ac94855283ccd4cce56482aca2fcf5348cbaf5018151b15a3540c100000ffff";
    let input: Vec<u8> = (0..h.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&h[i..i + 2], 16).unwrap())
        .collect();
    assert_eq!(
        decompress_bytes(&input, "deflate", None),
        Err(Fail::InvalidData)
    );
    assert_eq!(
        decode(Format::Deflate, None, &input, 5).1,
        "err InvalidData"
    );
}
