use std::collections::BTreeMap;
use std::io::{self, Read, Write};

/// Little-endian base-10 digits of an exact cent count (value 0..=9 per entry).
type Cents = Vec<u8>;

/// Parse an amount (`digits` or `digits.d` or `digits.dd`) into little-endian cents.
/// Returns None if the amount does not match the grammar.
fn parse_amount(s: &[u8]) -> Option<Cents> {
    let (int_part, frac_part): (&[u8], Option<&[u8]>) = match s.iter().position(|&b| b == b'.') {
        Some(p) => (&s[..p], Some(&s[p + 1..])),
        None => (s, None),
    };
    if int_part.is_empty() || !int_part.iter().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let frac_part: &[u8] = match frac_part {
        None => &[],
        // A '.' must be followed by one or two digits.
        Some(f) => {
            if f.is_empty() || f.len() > 2 || !f.iter().all(|b| b.is_ascii_digit()) {
                return None;
            }
            f
        }
    };
    // Build the digit string: integer digits followed by two fractional digits.
    let mut digits: Vec<u8> = Vec::with_capacity(int_part.len() + 2);
    digits.extend(int_part.iter().map(|b| b - b'0'));
    let f0 = frac_part.first().map(|b| b - b'0').unwrap_or(0);
    let f1 = frac_part.get(1).map(|b| b - b'0').unwrap_or(0);
    digits.push(f0);
    digits.push(f1);
    digits.reverse(); // little-endian
    Some(digits)
}

/// Add two little-endian decimal digit vectors in place.
fn add_into(acc: &mut Cents, other: &Cents) {
    let n = acc.len().max(other.len());
    acc.resize(n, 0);
    let mut carry = 0u8;
    for i in 0..n {
        let b = other.get(i).copied().unwrap_or(0);
        let s = acc[i] + b + carry;
        acc[i] = s % 10;
        carry = s / 10;
    }
    if carry > 0 {
        acc.push(carry);
    }
}

/// Format little-endian cents as `<int>.<2 digits>`.
fn format_cents(c: &Cents) -> String {
    // Ensure at least 3 digits so we always have an integer part and two fraction digits.
    let mut big_endian: Vec<u8> = c.iter().rev().copied().collect();
    while big_endian.len() > 3 && big_endian[0] == 0 {
        big_endian.remove(0);
    }
    while big_endian.len() < 3 {
        big_endian.insert(0, 0);
    }
    let split = big_endian.len() - 2;
    let mut out = String::with_capacity(big_endian.len() + 1);
    for (i, d) in big_endian.iter().enumerate() {
        if i == split {
            out.push('.');
        }
        out.push((b'0' + d) as char);
    }
    out
}

/// Parse one non-blank line into (category, amount). None means invalid.
fn parse_line(line: &[u8]) -> Option<(&[u8], &[u8])> {
    if line.first() == Some(&b'"') {
        // Quoted category: runs to the next double quote (no escapes).
        let close = line[1..].iter().position(|&b| b == b'"')? + 1;
        let category = &line[1..close];
        // Must be followed immediately by a comma, then the amount.
        if line.get(close + 1) != Some(&b',') {
            return None;
        }
        let amount = &line[close + 2..];
        if category.is_empty() {
            return None;
        }
        Some((category, amount))
    } else {
        let comma = line.iter().position(|&b| b == b',')?;
        let category = &line[..comma];
        let amount = &line[comma + 1..];
        if category.is_empty() {
            return None;
        }
        Some((category, amount))
    }
}

fn main() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().read_to_end(&mut input)?;

    let mut totals: BTreeMap<Vec<u8>, Cents> = BTreeMap::new();
    let mut skipped: u64 = 0;

    for raw in input.split(|&b| b == b'\n') {
        // Tolerate CRLF line endings.
        let line = match raw.last() {
            Some(b'\r') => &raw[..raw.len() - 1],
            _ => raw,
        };
        if line.iter().all(|&b| b == b' ' || b == b'\t' || b == b'\r') {
            continue; // blank line: ignored
        }
        match parse_line(line) {
            Some((category, amount)) => match parse_amount(amount) {
                Some(cents) => {
                    let entry = totals.entry(category.to_vec()).or_insert_with(|| vec![0]);
                    add_into(entry, &cents);
                }
                None => skipped += 1,
            },
            None => skipped += 1,
        }
    }

    let stdout = io::stdout();
    let mut out = io::BufWriter::new(stdout.lock());
    for (category, total) in &totals {
        out.write_all(category)?;
        out.write_all(b": ")?;
        out.write_all(format_cents(total).as_bytes())?;
        out.write_all(b"\n")?;
    }
    if skipped > 0 {
        writeln!(out, "skipped: {}", skipped)?;
    }
    out.flush()?;
    Ok(())
}
