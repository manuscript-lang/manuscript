use ms_rt::ffi::Fail;
use std::{hint::black_box, time::Instant};

// POSIX lexical rules only; every returned field is owned, as in PathParts.
fn basename(text: &str) -> &str {
    text.trim_end_matches('/').rsplit('/').next().unwrap_or("")
}
fn extension(text: &str) -> &str {
    let base = basename(text);
    if base == "." || base == ".." {
        return "";
    }
    let Some(at) = base.rfind('.') else {
        return "";
    };
    if at == 0 { "" } else { &base[at..] }
}
fn parse_path(text: &str) -> [String; 6] {
    let root = if text.starts_with('/') { "/" } else { "" };
    let trimmed = text.trim_end_matches('/');
    let base = basename(text);
    let directory = if trimmed.is_empty() {
        root
    } else {
        trimmed
            .rfind('/')
            .map_or(root, |at| if at < root.len() { root } else { &text[..at] })
    };
    let ext = extension(text);
    [
        root.into(),
        directory.into(),
        base.into(),
        ext.into(),
        base[..base.len() - ext.len()].into(),
        String::new(),
    ]
}
fn normalize(text: &str) -> String {
    let absolute = text.starts_with('/');
    let mut parts = Vec::new();
    for part in text.split('/') {
        if part.is_empty() || part == "." {
            continue;
        }
        if part == ".." {
            if parts.last().is_some_and(|p| *p != "..") {
                parts.pop();
            } else if !absolute {
                parts.push(part);
            }
        } else {
            parts.push(part);
        }
    }
    let mut out = String::with_capacity(text.len().max(2));
    if absolute {
        out.push('/');
    }
    for part in parts {
        if !out.is_empty() && !out.ends_with('/') {
            out.push('/');
        }
        out.push_str(part);
    }
    if out.is_empty() {
        out.push('.');
    }
    if text.ends_with('/') && !out.ends_with('/') {
        out.push('/');
    }
    out
}
// Worst-case reservation trades unused capacity on mostly-safe strings for no growth.
fn encode(text: &str) -> String {
    const HEX: &[u8; 16] = b"0123456789ABCDEF";
    let mut out = String::with_capacity(text.len().checked_mul(3).expect("capacity overflow"));
    for b in text.bytes() {
        if b.is_ascii_alphanumeric() || b"-._~".contains(&b) {
            out.push(b as char);
        } else {
            out.push('%');
            out.push(HEX[(b >> 4) as usize] as char);
            out.push(HEX[(b & 15) as usize] as char);
        }
    }
    out
}
fn decode(text: &str) -> Result<String, Fail> {
    let Some(first) = text.find('%') else {
        return Ok(text.to_owned());
    };
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(text.len());
    out.extend_from_slice(&bytes[..first]);
    let mut i = first;
    while i < bytes.len() {
        if bytes[i] == b'%' {
            if i + 2 >= bytes.len() {
                return Err(Fail::InvalidData);
            }
            let hi = (bytes[i + 1] as char)
                .to_digit(16)
                .ok_or(Fail::InvalidData)?;
            let lo = (bytes[i + 2] as char)
                .to_digit(16)
                .ok_or(Fail::InvalidData)?;
            out.push((hi * 16 + lo) as u8);
            i += 3;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8(out).map_err(|_| Fail::InvalidData)
}
fn run(kind: &str, op: &str, input: &str, native: bool) -> (bool, [String; 6]) {
    let mut fields: [String; 6] = Default::default();
    if kind == "path" {
        if native {
            let rules = ms_std_path::POSIX;
            match op {
                "extension" => fields[0] = rules.extension(input),
                "normalize" => fields[0] = rules.normalize(input),
                "parse" => {
                    let p = rules.parse(input);
                    fields = [
                        p.root,
                        p.directory,
                        p.base,
                        p.extension,
                        p.name,
                        String::new(),
                    ];
                }
                _ => panic!("unknown path operation"),
            }
        } else {
            match op {
                "extension" => fields[0] = extension(input).to_owned(),
                "normalize" => fields[0] = normalize(input),
                "parse" => fields = parse_path(input),
                _ => panic!("unknown path operation"),
            }
        }
        return (false, fields);
    }
    if op == "parse" {
        // Explicit same-implementation parser control, not an independent URL parser.
        let result = ms_std_url::parse(input);
        if let Err(error) = &result {
            assert_eq!(*error, Fail::InvalidData);
            return (true, fields);
        }
        let p = result.unwrap();
        fields = [
            p.scheme,
            p.host,
            p.port.unwrap_or(-1).to_string(),
            p.path,
            p.query,
            p.fragment,
        ];
        return (false, fields);
    }
    if op == "encode" {
        fields[0] = if native {
            ms_std_url::encode_component(input)
        } else {
            encode(input)
        };
        return (false, fields);
    }
    assert_eq!(op, "decode");
    let result = if native {
        ms_std_url::decode_component(input)
    } else {
        decode(input)
    };
    if let Err(error) = &result {
        assert_eq!(*error, Fail::InvalidData);
        return (true, fields);
    }
    fields[0] = result.unwrap();
    (false, fields)
}
fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mode = &args[0]; // path-rust/path-native/url-rust/url-native
    let (kind, implementation) = mode.split_once('-').unwrap();
    assert!(kind == "path" || kind == "url");
    assert!(implementation == "native" || implementation == "rust");
    let count: usize = args[1].parse().unwrap();
    let expected_error = args[4] == "InvalidData";
    let expected = &args[5..11];
    let mut last: [String; 6] = Default::default();
    let mut checksum = 0usize;
    let mut failed = false;
    let start = Instant::now();
    for _ in 0..count {
        (failed, last) = run(
            kind,
            black_box(&args[2]),
            black_box(&args[3]),
            implementation == "native",
        );
        assert_eq!(failed, expected_error);
        assert_eq!(last.as_slice(), expected);
        checksum += black_box(last.iter().map(String::len).sum::<usize>() + usize::from(failed));
    }
    let ns = start.elapsed().as_nanos();
    let status = if failed { "InvalidData" } else { "OK" };
    println!("{count}\t{ns}\t{checksum}\t{status}\t{}", last.join("\t"));
}
