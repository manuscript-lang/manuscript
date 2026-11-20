//! Stream decoding of large chunks.
use ms_rt as _;
use ms_std_archive::compress::{Decoder, Format};

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
