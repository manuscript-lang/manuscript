//! ZIP64 end-record sentinels trigger independently, and stream decoding of large chunks.
use ms_rt as _;
use ms_rt::ffi::Fail;
use ms_std_archive::compress::{Decoder, Format};
use ms_std_archive::{Entry, Limits, pack, unpack};

/// Rewrites a plain one-member archive so the ZIP64 end record carries the real count, size and
/// offset, and the legacy end fields selected by `mask` (1 count, 2 size, 4 offset) hold sentinels.
fn with_zip64_end(mask: u8) -> Vec<u8> {
    let entry = Entry {
        path: "a.txt".into(),
        data: b"zip64 size sentinel".to_vec(),
        directory: false,
    };
    let plain = pack(&[entry], "zip", None).expect("pack");
    let end_at = plain.len() - 22;
    let count = u64::from(u16::from_le_bytes([plain[end_at + 10], plain[end_at + 11]]));
    let size = u64::from(u32::from_le_bytes(
        plain[end_at + 12..end_at + 16].try_into().unwrap(),
    ));
    let offset = u64::from(u32::from_le_bytes(
        plain[end_at + 16..end_at + 20].try_into().unwrap(),
    ));
    let mut out = plain[..end_at].to_vec();
    out.extend_from_slice(&0x0606_4b50u32.to_le_bytes());
    out.extend_from_slice(&44u64.to_le_bytes());
    out.extend_from_slice(&45u16.to_le_bytes());
    out.extend_from_slice(&45u16.to_le_bytes());
    out.extend_from_slice(&[0; 8]);
    for v in [count, count, size, offset] {
        out.extend_from_slice(&v.to_le_bytes());
    }
    out.extend_from_slice(&0x0706_4b50u32.to_le_bytes());
    out.extend_from_slice(&0u32.to_le_bytes());
    out.extend_from_slice(&(end_at as u64).to_le_bytes());
    out.extend_from_slice(&1u32.to_le_bytes());
    let mut end = plain[end_at..].to_vec();
    if mask & 1 != 0 {
        end[8..12].fill(0xff);
    }
    if mask & 2 != 0 {
        end[12..16].fill(0xff);
    }
    if mask & 4 != 0 {
        end[16..20].fill(0xff);
    }
    out.extend_from_slice(&end);
    out
}

#[test]
fn every_sentinel_mask_reads_the_zip64_end_record() {
    for mask in 1..=7u8 {
        let zip = with_zip64_end(mask);
        let files = unpack(&zip, "zip", None).unwrap_or_else(|e| panic!("mask {mask}: {e:?}"));
        assert_eq!(files.len(), 1, "mask {mask}");
        assert_eq!(files[0].data, b"zip64 size sentinel", "mask {mask}");
    }
}

#[test]
fn size_sentinel_still_reaches_the_entry_limit() {
    let zip = with_zip64_end(2);
    let limits = Limits {
        max_entries: None,
        max_entry_bytes: Some(1),
        max_total_bytes: None,
    };
    assert_eq!(
        unpack(&zip, "zip", Some(limits)).err(),
        Some(Fail::LimitExceeded)
    );
}

#[test]
fn large_single_chunk_decodes_like_small_chunks() {
    // Stored deflate blocks of 65,535 bytes: one chunk must not cost a tail copy per output window.
    let payload: Vec<u8> = (0..4_000_000u32).map(|i| (i % 251) as u8).collect();
    let mut stream = Vec::new();
    let blocks: Vec<&[u8]> = payload.chunks(65_535).collect();
    for (i, b) in blocks.iter().enumerate() {
        stream.push(u8::from(i + 1 == blocks.len()));
        stream.extend_from_slice(&(b.len() as u16).to_le_bytes());
        stream.extend_from_slice(&(!(b.len() as u16)).to_le_bytes());
        stream.extend_from_slice(b);
    }
    for chunk in [stream.len(), 64 * 1024, 7_001] {
        let mut d = Decoder::new(Format::Deflate, None);
        let mut out = Vec::new();
        for c in stream.chunks(chunk) {
            out.extend_from_slice(&d.push(c).expect("push"));
        }
        out.extend_from_slice(&d.end().expect("end"));
        assert!(out == payload, "chunk {chunk}");
    }
}
