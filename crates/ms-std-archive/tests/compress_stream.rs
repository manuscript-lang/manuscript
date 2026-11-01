//! Replays `tests/oracle/stream.tsv` (Go `decompress_stream` results for chunked input), and
//! round-trips the streaming encoder.
// Links the msrt_* runtime symbols.
use ms_rt as _;
use ms_rt::ffi::Fail;
use ms_std_archive::compress::compress;
use ms_std_archive::compress::stream::{Decoder, Encoder, Poll};
use ms_std_archive::compress::{Format, crc32, decompress_bytes};
use std::collections::HashMap;

fn bytes(tok: &str) -> Vec<u8> {
    let h = tok.strip_prefix('x').expect("hex token");
    (0..h.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&h[i..i + 2], 16).unwrap())
        .collect()
}

fn decode(
    format: Format,
    max: Option<i64>,
    input: &[u8],
    chunk: usize,
    out_max: usize,
) -> (Vec<u8>, String) {
    let mut d = Decoder::new(format, max);
    let mut rest = input;
    let mut out = Vec::new();
    loop {
        match d.poll(out_max) {
            Ok(Poll::Output(b)) => out.extend_from_slice(&b),
            Ok(Poll::Done) => return (out, "ok".into()),
            Ok(Poll::NeedInput) if rest.is_empty() => d.finish_input(),
            Ok(Poll::NeedInput) => {
                let n = chunk.min(rest.len());
                d.feed(&rest[..n]);
                rest = &rest[n..];
            }
            Err(Fail::LimitExceeded) => return (out, "err LimitExceeded".into()),
            Err(_) => return (out, "err InvalidData".into()),
        }
    }
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
        let (out, status) = decode(
            format,
            max,
            &inputs[f[2]],
            f[4].parse().unwrap(),
            f[5].parse().unwrap(),
        );
        // Output delivered before an error depends on the decoder's internal chunking, so only
        // the error and the limit are compared; complete outputs match exactly.
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
                        e.feed(c);
                        packed.extend(e.take(usize::MAX));
                    }
                    e.finish();
                    while e.has_output() {
                        packed.extend(e.take(100));
                    }
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
fn tiny_output_reads_preserve_dictionary_wraps_and_gzip_members() {
    let data: Vec<u8> = (0..65_539u32).map(|i| (i * 7 % 253) as u8).collect();
    for name in ["gzip", "zlib", "deflate"] {
        let format = Format::from_name(name).unwrap();
        let packed = compress(&data, name, 6, None).unwrap();
        for chunk in [1, 32768] {
            for width in [1, 7, 32768] {
                let (out, status) = decode(format, None, &packed, chunk, width);
                assert_eq!(status, "ok", "{name} {chunk} {width}");
                assert_eq!(out, data, "{name} {chunk} {width}");
            }
        }
    }
    let mut members = compress(&data, "gzip", 6, None).unwrap();
    members.extend(compress(b"next member", "gzip", 6, None).unwrap());
    let (mut out, status) = decode(Format::Gzip, None, &members, 31, 1);
    assert_eq!(status, "ok");
    assert_eq!(out.split_off(data.len()), b"next member");
    assert_eq!(out, data);
}

#[test]
fn tiny_output_limits_and_bad_trailers_remain_terminal() {
    let data: Vec<u8> = (0..65_539u32).map(|i| (i % 251) as u8).collect();
    for name in ["gzip", "zlib", "deflate"] {
        let format = Format::from_name(name).unwrap();
        let packed = compress(&data, name, 6, None).unwrap();
        for limit in [-1, 0, 1, 7, 32768, data.len() as i64 - 1] {
            let mut d = Decoder::new(format, Some(limit));
            d.feed(&packed);
            d.finish_input();
            let mut out = Vec::new();
            loop {
                match d.poll(1) {
                    Ok(Poll::Output(bytes)) => out.extend(bytes),
                    Err(e) => {
                        assert_eq!(e, Fail::LimitExceeded, "{name} {limit}");
                        break;
                    }
                    other => panic!("unexpected {other:?} for {name} {limit}"),
                }
            }
            assert_eq!(out, data[..limit.max(0) as usize], "{name} {limit}");
            for width in [1, 7, 32768] {
                assert_eq!(d.poll(width), Err(Fail::LimitExceeded));
            }
        }
    }
    let mut packed = compress(&data, "gzip", 6, None).unwrap();
    let trailer = packed.len() - 8;
    packed[trailer] ^= 1;
    let mut d = Decoder::new(Format::Gzip, None);
    d.feed(&packed);
    d.finish_input();
    let mut out = Vec::new();
    loop {
        match d.poll(1) {
            Ok(Poll::Output(bytes)) => out.extend(bytes),
            Err(e) => {
                assert_eq!(e, Fail::InvalidData);
                break;
            }
            other => panic!("unexpected {other:?} before a bad gzip trailer"),
        }
    }
    assert_eq!(out, data);
    assert_eq!(d.poll(32768), Err(Fail::InvalidData));
}
