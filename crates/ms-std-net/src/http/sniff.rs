//! `http.DetectContentType`: the content type net/http assigns to a response
//! body when the handler sets none.

const WS: &[u8] = b"\t\n\x0c\r ";

fn skip_ws(data: &[u8]) -> &[u8] {
    let n = data.iter().take_while(|b| WS.contains(b)).count();
    &data[n..]
}

fn html(data: &[u8], tag: &str) -> bool {
    let data = skip_ws(data);
    data.len() > tag.len()
        && data[..tag.len()].eq_ignore_ascii_case(tag.as_bytes())
        && matches!(data[tag.len()], b' ' | b'>')
}

fn masked(data: &[u8], pattern: &[u8], mask: &[u8], skip: bool) -> bool {
    let data = if skip { skip_ws(data) } else { data };
    if data.len() < pattern.len() {
        return false;
    }
    pattern
        .iter()
        .zip(mask)
        .zip(data)
        .all(|((p, m), d)| d & m == *p)
}

fn exact(data: &[u8], sig: &[u8]) -> bool {
    data.starts_with(sig)
}

fn mp4(data: &[u8]) -> bool {
    if data.len() < 12 {
        return false;
    }
    let size = u32::from_be_bytes([data[0], data[1], data[2], data[3]]) as usize;
    if data.len() < size || !size.is_multiple_of(4) {
        return false;
    }
    if &data[4..8] != b"ftyp" {
        return false;
    }
    let mut st = 8;
    while st < size {
        if st == 12 {
            st += 4;
            continue;
        }
        if st + 3 > data.len() {
            break;
        }
        if &data[st..st + 3] == b"mp4" {
            return true;
        }
        st += 4;
    }
    false
}

fn is_text(data: &[u8]) -> bool {
    !data
        .iter()
        .any(|&b| matches!(b, 0x00..=0x08 | 0x0b | 0x0e..=0x1a | 0x1c..=0x1f))
}

/// The detected media type of `data` (at most its first 512 bytes matter).
pub fn detect(data: &[u8]) -> &'static str {
    let data = &data[..data.len().min(512)];
    const HTML: &[&str] = &[
        "<!DOCTYPE HTML",
        "<HTML",
        "<HEAD",
        "<SCRIPT",
        "<IFRAME",
        "<H1",
        "<DIV",
        "<FONT",
        "<TABLE",
        "<A",
        "<STYLE",
        "<TITLE",
        "<B",
        "<BODY",
        "<BR",
        "<P",
        "<!--",
    ];
    if HTML.iter().any(|t| html(data, t)) {
        return "text/html; charset=utf-8";
    }
    if masked(data, b"<?xml", b"\xff\xff\xff\xff\xff", true) {
        return "text/xml; charset=utf-8";
    }
    if exact(data, b"%PDF-") {
        return "application/pdf";
    }
    if exact(data, b"%!PS-Adobe-") {
        return "application/postscript";
    }
    if masked(data, b"\xfe\xff\x00\x00", b"\xff\xff\x00\x00", false) {
        return "text/plain; charset=utf-16be";
    }
    if masked(data, b"\xff\xfe\x00\x00", b"\xff\xff\x00\x00", false) {
        return "text/plain; charset=utf-16le";
    }
    if masked(data, b"\xef\xbb\xbf\x00", b"\xff\xff\xff\x00", false) {
        return "text/plain; charset=utf-8";
    }
    if exact(data, b"GIF87a") || exact(data, b"GIF89a") {
        return "image/gif";
    }
    if exact(data, b"\x89PNG\x0d\x0a\x1a\x0a") {
        return "image/png";
    }
    if exact(data, b"\xff\xd8\xff") {
        return "image/jpeg";
    }
    if exact(data, b"BM") {
        return "image/bmp";
    }
    if masked(
        data,
        b"RIFF\x00\x00\x00\x00WEBPVP",
        b"\xff\xff\xff\xff\x00\x00\x00\x00\xff\xff\xff\xff\xff\xff",
        false,
    ) {
        return "image/webp";
    }
    if exact(data, b"\x00\x00\x01\x00") {
        return "image/x-icon";
    }
    if exact(data, b"\x00\x00\x02\x00") {
        return "image/x-icon";
    }
    if masked(
        data,
        b"FORM\x00\x00\x00\x00AIFF",
        b"\xff\xff\xff\xff\x00\x00\x00\x00\xff\xff\xff\xff",
        false,
    ) {
        return "audio/aiff";
    }
    if exact(data, b"ID3") {
        return "audio/mpeg";
    }
    if exact(data, b"OggS\x00") {
        return "application/ogg";
    }
    if exact(data, b"MThd\x00\x00\x00\x06") {
        return "audio/midi";
    }
    if masked(
        data,
        b"RIFF\x00\x00\x00\x00AVI ",
        b"\xff\xff\xff\xff\x00\x00\x00\x00\xff\xff\xff\xff",
        false,
    ) {
        return "video/avi";
    }
    if masked(
        data,
        b"RIFF\x00\x00\x00\x00WAVE",
        b"\xff\xff\xff\xff\x00\x00\x00\x00\xff\xff\xff\xff",
        false,
    ) {
        return "audio/wave";
    }
    if mp4(data) {
        return "video/mp4";
    }
    if exact(data, b"\x1a\x45\xdf\xa3") {
        return "video/webm";
    }
    if masked(
        data,
        b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00LP",
        b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xff",
        false,
    ) {
        return "application/vnd.ms-fontobject";
    }
    if exact(data, b"\x00\x01\x00\x00") {
        return "font/ttf";
    }
    if exact(data, b"OTTO") {
        return "font/otf";
    }
    if exact(data, b"ttcf") {
        return "font/collection";
    }
    if exact(data, b"wOFF") {
        return "font/woff";
    }
    if exact(data, b"wOF2") {
        return "font/woff2";
    }
    if exact(data, b"\x1f\x8b\x08") {
        return "application/x-gzip";
    }
    if exact(data, b"PK\x03\x04") {
        return "application/zip";
    }
    if exact(data, b"Rar!\x1a\x07\x00") || exact(data, b"Rar!\x1a\x07\x01\x00") {
        return "application/x-rar-compressed";
    }
    if exact(data, b"\x00asm") {
        return "application/wasm";
    }
    if is_text(data) {
        return "text/plain; charset=utf-8";
    }
    "application/octet-stream"
}

#[cfg(test)]
mod tests {
    use super::detect;

    /// Vectors recorded from Go's `http.DetectContentType`.
    #[test]
    fn matches_go() {
        let cases: &[(&[u8], &str)] = &[
            (b"<html><body>", "text/html; charset=utf-8"),
            (b"  <!doctype html>", "text/html; charset=utf-8"),
            (b"<!-- c -->", "text/html; charset=utf-8"),
            (b"<p>x", "text/html; charset=utf-8"),
            (b"<pre>", "text/plain; charset=utf-8"),
            (b"<?xml version", "text/xml; charset=utf-8"),
            (b"%PDF-1.4", "application/pdf"),
            (b"GIF89a....", "image/gif"),
            (b"\x89PNG\r\n\x1a\n", "image/png"),
            (b"\xff\xd8\xff\xe0", "image/jpeg"),
            (b"plain text", "text/plain; charset=utf-8"),
            (b"{\"a\":1}", "text/plain; charset=utf-8"),
            (b"bin\x00ary", "application/octet-stream"),
            (b"\xef\xbb\xbfhi", "text/plain; charset=utf-8"),
            (b"\xfe\xff\x00a", "text/plain; charset=utf-16be"),
            (b"PK\x03\x04zz", "application/zip"),
            (b"<a href", "text/html; charset=utf-8"),
            (b"<A>x", "text/html; charset=utf-8"),
            (b"<br/>", "text/plain; charset=utf-8"),
            (b"<div ", "text/html; charset=utf-8"),
            (b"\x1f\x8b\x08xx", "application/x-gzip"),
            (b"RIFF\x00\x00\x00\x00WEBPVP8 ", "image/webp"),
            (b"\x00asm\x01", "application/wasm"),
            (b"BMxx", "image/bmp"),
            (b"ID3\x03", "audio/mpeg"),
            (b"", "text/plain; charset=utf-8"),
            (b"<scripts", "text/plain; charset=utf-8"),
            (b"<b>", "text/html; charset=utf-8"),
            (b"wOF2xx", "font/woff2"),
        ];
        for (data, want) in cases {
            assert_eq!(detect(data), *want, "{data:?}");
        }
        let mut long = vec![b'a'; 600];
        long.push(0);
        assert_eq!(detect(&long), "text/plain; charset=utf-8");
    }
}
