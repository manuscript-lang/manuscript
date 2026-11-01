//! Additional RFC 4648 alphabets use the already-pinned data-encoding implementation.
use alloc::{string::String, vec::Vec};
use data_encoding::{
    BASE32, BASE32_NOPAD, BASE32HEX, BASE32HEX_NOPAD, BASE64_NOPAD, BASE64URL_NOPAD, Encoding,
};
use ms_rt::ffi::Fail;

fn base32(hex_alphabet: bool, padded: bool) -> Encoding {
    match (hex_alphabet, padded) {
        (false, true) => BASE32,
        (false, false) => BASE32_NOPAD,
        (true, true) => BASE32HEX,
        (true, false) => BASE32HEX_NOPAD,
    }
}

fn unpadded_base64(url_safe: bool) -> Encoding {
    if url_safe {
        BASE64URL_NOPAD
    } else {
        BASE64_NOPAD
    }
}

pub fn base64_encode_unpadded(data: &[u8], url_safe: bool) -> String {
    unpadded_base64(url_safe).encode(data)
}

pub fn base64_decode_unpadded(
    text: &str,
    url_safe: bool,
    max_bytes: Option<i64>,
) -> Result<Vec<u8>, Fail> {
    let limit = super::limit(max_bytes)?;
    let encoding = unpadded_base64(url_safe);
    let length = decoded_capacity(&encoding, text.len())?;
    if length > limit {
        return Err(Fail::LimitExceeded);
    }
    encoding
        .decode(text.as_bytes())
        .map_err(|_| Fail::InvalidData)
}

pub fn base32_encode(data: &[u8], hex_alphabet: bool, padded: bool) -> String {
    base32(hex_alphabet, padded).encode(data)
}

pub fn base32_decode(
    text: &str,
    hex_alphabet: bool,
    padded: bool,
    max_bytes: Option<i64>,
) -> Result<Vec<u8>, Fail> {
    let limit = super::limit(max_bytes)?;
    let bytes = text.as_bytes();
    let padding = bytes.iter().rev().take_while(|&&c| c == b'=').count();
    // data-encoding permits concatenated padded blocks. Our whole-text API accepts
    // one encoding, so padding must occur only at its end.
    if bytes[..bytes.len() - padding].contains(&b'=') {
        return Err(Fail::InvalidData);
    }
    let omitted = match padding {
        0 => 0,
        1 if padded => 1,
        3 if padded => 2,
        4 if padded => 3,
        6 if padded => 4,
        _ => return Err(Fail::InvalidData),
    };
    let encoding = base32(hex_alphabet, padded);
    let length = decoded_capacity(&encoding, bytes.len())?
        .checked_sub(omitted)
        .ok_or(Fail::InvalidData)?;
    if length > limit {
        return Err(Fail::LimitExceeded);
    }
    encoding.decode(bytes).map_err(|_| Fail::InvalidData)
}

fn decoded_capacity(encoding: &Encoding, length: usize) -> Result<usize, Fail> {
    // data-encoding's length arithmetic guarantees apply up to this bound.
    if length > usize::MAX / 8 {
        return Err(Fail::LimitExceeded);
    }
    encoding.decode_len(length).map_err(|_| Fail::InvalidData)
}
