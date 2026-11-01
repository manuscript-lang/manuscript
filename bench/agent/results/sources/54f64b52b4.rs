use std::io::{self, Read, Write};

/// Result of processing one non-blank command line.
fn process(line: &[u8]) -> Vec<u8> {
    // Split into at most four parts on single spaces. Fewer than three spaces
    // yields fewer than four parts; an empty text is also a bad command.
    let parts: Vec<&[u8]> = line.splitn(4, |&b| b == b' ').collect();
    if parts.len() < 4 || parts[3].is_empty() {
        return b"error: bad command".to_vec();
    }
    let (cipher, mode, key, text) = (parts[0], parts[1], parts[2], parts[3]);

    // Check order from the spec: cipher, then mode, then key.
    if cipher != b"caesar" && cipher != b"vigenere" {
        return b"error: bad cipher".to_vec();
    }
    let encrypt = match mode {
        b"enc" => true,
        b"dec" => false,
        _ => return b"error: bad mode".to_vec(),
    };

    if cipher == b"caesar" {
        match parse_caesar_key(key) {
            Some(k) => caesar(text, if encrypt { k } else { -k }),
            None => b"error: bad key".to_vec(),
        }
    } else {
        if key.is_empty() || !key.iter().all(|b| b.is_ascii_alphabetic()) {
            return b"error: bad key".to_vec();
        }
        let shifts: Vec<i64> = key
            .iter()
            .map(|b| (b.to_ascii_lowercase() - b'a') as i64)
            .collect();
        vigenere(text, &shifts, encrypt)
    }
}

/// Caesar key: optional leading '-', then 1 to 7 ASCII digits.
fn parse_caesar_key(key: &[u8]) -> Option<i64> {
    let digits = match key.first() {
        Some(b'-') => &key[1..],
        _ => key,
    };
    if digits.is_empty() || digits.len() > 7 || !digits.iter().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let mut value: i64 = 0;
    for &d in digits {
        value = value * 10 + (d - b'0') as i64;
    }
    Some(if key.first() == Some(&b'-') { -value } else { value })
}

/// Shift a single ASCII letter by `shift` positions, keeping its case.
fn shift_letter(c: u8, shift: i64) -> u8 {
    let base = if c.is_ascii_uppercase() { b'A' } else { b'a' };
    let idx = (c - base) as i64;
    base + (idx + shift).rem_euclid(26) as u8
}

fn caesar(text: &[u8], shift: i64) -> Vec<u8> {
    text.iter()
        .map(|&c| {
            if c.is_ascii_alphabetic() {
                shift_letter(c, shift)
            } else {
                c
            }
        })
        .collect()
}

fn vigenere(text: &[u8], shifts: &[i64], encrypt: bool) -> Vec<u8> {
    let mut out = Vec::with_capacity(text.len());
    let mut pos = 0usize;
    for &c in text {
        if c.is_ascii_alphabetic() {
            let s = shifts[pos % shifts.len()];
            let s = if encrypt { s } else { -s };
            out.push(shift_letter(c, s));
            pos += 1;
        } else {
            out.push(c);
        }
    }
    out
}

fn main() {
    let mut input = Vec::new();
    io::stdin()
        .read_to_end(&mut input)
        .expect("failed to read stdin");

    let mut out = Vec::with_capacity(input.len() + 64);
    for line in input.split(|&b| b == b'\n') {
        // Blank lines (empty or only spaces) produce no output.
        if line.iter().all(|&b| b == b' ') {
            continue;
        }
        out.extend_from_slice(&process(line));
        out.push(b'\n');
    }

    let stdout = io::stdout();
    let mut lock = stdout.lock();
    lock.write_all(&out).expect("failed to write stdout");
    lock.flush().expect("failed to flush stdout");
}
