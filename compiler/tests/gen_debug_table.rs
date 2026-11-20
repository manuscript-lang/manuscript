fn main() {
    let mut ranges: Vec<(u32, u32)> = Vec::new();
    for c in (0u32..0x110000).filter_map(char::from_u32) {
        let s = format!("{c:?}");
        let esc = s.starts_with("'\\u{");
        if esc {
            match ranges.last_mut() {
                Some(r) if r.1 + 1 == c as u32 => r.1 = c as u32,
                _ => ranges.push((c as u32, c as u32)),
            }
        }
    }
    println!("{}", ranges.len());
    let mut line = String::new();
    for (a, b) in &ranges {
        line.push_str(&format!("{{0x{a:X},0x{b:X}}},"));
        if line.len() > 90 { println!("    {line}"); line.clear(); }
    }
    println!("    {line}");
}
