//! Standard padded Base64, for WebSocket keys and PEM bodies. Temporary: it goes with this crate, whose
//! callers move to C together with `@std/data/encoding` (`runtime/std/encoding.c`).

const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

pub fn encode(data: &[u8]) -> String {
    let mut out = String::with_capacity(data.len().div_ceil(3) * 4);
    for chunk in data.chunks(3) {
        let word = chunk
            .iter()
            .enumerate()
            .fold(0u32, |word, (i, &b)| word | u32::from(b) << (16 - 8 * i));
        for i in 0..4 {
            if i <= chunk.len() {
                out.push(ALPHABET[(word >> (18 - 6 * i) & 63) as usize] as char);
            } else {
                out.push('=');
            }
        }
    }
    out
}

/// Decodes padded Base64, ignoring unused trailing bits (as PEM and WebSocket keys allow).
pub fn decode_lenient(text: &str) -> Option<Vec<u8>> {
    let text = text.as_bytes();
    let padding = text.iter().rev().take_while(|&&c| c == b'=').count();
    if padding > 2 || !text.len().is_multiple_of(4) {
        return None;
    }
    let mut out = Vec::with_capacity(text.len() / 4 * 3);
    let (mut word, mut held) = (0u32, 0u32);
    for &c in &text[..text.len() - padding] {
        let digit = ALPHABET.iter().position(|&a| a == c)? as u32;
        word = word << 6 | digit;
        held += 6;
        if held >= 8 {
            held -= 8;
            out.push((word >> held) as u8);
            word &= (1 << held) - 1;
        }
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_and_pads() {
        for (raw, text) in [("", ""), ("f", "Zg=="), ("fo", "Zm8="), ("foo", "Zm9v")] {
            assert_eq!(encode(raw.as_bytes()), text);
            assert_eq!(decode_lenient(text).as_deref(), Some(raw.as_bytes()));
        }
        assert_eq!(decode_lenient("Zh=="), Some(b"f".to_vec()));
        assert_eq!(decode_lenient("Zg="), None);
        assert_eq!(decode_lenient("!!!!"), None);
    }
}
