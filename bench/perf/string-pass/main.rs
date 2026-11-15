use std::collections::HashMap;
use std::fmt::Write;
use std::time::Instant;
fn lcg(x: i64) -> i64 { (x * 1103515245 + 12345) % 2147483648 }
fn rep(name: &str, t: Instant, s: i64) { println!("{} {} ms {}", name, t.elapsed().as_millis(), s); }
fn main() {
    let n = 1000000usize;
    let mut x = 7i64;
    let mut words: Vec<String> = vec![];
    let mut longs: Vec<String> = vec![];
    for _ in 0..n {
        x = lcg(x);
        words.push(format!("w{}-{}", x % 100000, x / 7 % 977));
        longs.push(format!("/usr/share/lib/module-{}/file-{}.txt", x % 100000, x / 7 % 977));
    }
    let text = words.join(" ");
    let mut t;
    let mut s;
    t = Instant::now();
    let mut freq: HashMap<String, i64> = HashMap::new();
    for w in &words { *freq.entry(w.clone()).or_insert(0) += 1; }
    rep("freq_short", t, freq.len() as i64);
    t = Instant::now();
    let mut freq2: HashMap<String, i64> = HashMap::new();
    for w in &longs { *freq2.entry(w.clone()).or_insert(0) += 1; }
    rep("freq_long", t, freq2.len() as i64);
    t = Instant::now(); s = 0;
    for w in &longs { if freq2.contains_key(w) { s += 1; } }
    rep("lookup_long", t, s);
    t = Instant::now(); s = 0;
    for c in text.chars() { if c >= '0' && c <= '9' { s += 1; } else if c == ' ' { s += 100; } }
    rep("chars_scan", t, s);
    t = Instant::now(); s = 0;
    for &b in text.as_bytes() { if b == 32 { s += 1; } }
    rep("bytes_scan", t, s);
    let utext = text.replace("w", "é");
    t = Instant::now(); s = 0;
    for c in utext.chars() { if c == 'é' { s += 1; } }
    rep("chars_scan_utf8", t, s);
    t = Instant::now();
    s = utext.chars().count() as i64
        + utext.find("é99999").map(|b| utext[..b].chars().count() as i64).unwrap_or(-1)
        + utext.matches("é1").count() as i64;
    rep("utf8_len_index_count", t, s);
    t = Instant::now();
    s = 0;
    let mut offset = 0;
    while offset < utext.len() {
        let c = utext[offset..].chars().next().unwrap();
        s += c as i64;
        offset += c.len_utf8();
    }
    rep("utf8_offset_walk", t, s);
    t = Instant::now();
    s = utext.to_uppercase().chars().count() as i64 + utext.chars().rev().collect::<String>().chars().count() as i64;
    rep("utf8_case_reverse", t, s);
    t = Instant::now(); s = 0;
    for w in &longs { if w.ends_with(".txt") && w.starts_with("/usr") { s += 1; } }
    rep("starts_ends_long", t, s);
    t = Instant::now(); s = 0;
    for w in &longs { if w.contains("file-9") { s += 1; } }
    rep("contains_short", t, s);
    t = Instant::now(); s = 0;
    for w in &longs { s += w.find("module").unwrap_or(0) as i64 + w.rfind('/').unwrap_or(0) as i64; }
    rep("index_of_small", t, s);
    t = Instant::now(); s = 0;
    for w in &longs { s += w.split('/').collect::<Vec<_>>().len() as i64; }
    rep("split_path", t, s);
    t = Instant::now(); s = 0;
    for w in &longs { s += w.replace("file", "f").len() as i64; }
    rep("replace_small", t, s);
    t = Instant::now(); s = 0;
    for w in &longs { s += w.to_lowercase().len() as i64; }
    rep("lower_small", t, s);
    t = Instant::now(); s = 0;
    for w in &longs { s += w.trim().len() as i64; }
    rep("trim_small", t, s);
    t = Instant::now(); s = 0;
    for i in 0..n { s += (words[i].clone() + "/" + &longs[i]).len() as i64; }
    rep("concat3", t, s);
    t = Instant::now(); s = 0;
    for i in 0..n { s += format!("{}={};", words[i], longs[i]).len() as i64; }
    rep("interp_strings", t, s);
    t = Instant::now();
    let mut sb = String::new();
    for i in 0..n { sb.push_str(&words[i]); sb.push(','); write!(sb, "{}", i).unwrap(); sb.push('\n'); }
    rep("builder_mixed", t, sb.len() as i64);
    t = Instant::now();
    let mut acc = String::new();
    for i in 0..n { acc += &words[i]; }
    rep("plus_equals", t, acc.len() as i64);
    t = Instant::now(); s = 0;
    for i in 1..n { if longs[i] == longs[i - 1] { s += 1; } }
    rep("eq_long", t, s);
    t = Instant::now(); s = 0;
    for i in 0..n { s += format!("{:x}", i).len() as i64; }
    rep("int_hex", t, s);
    t = Instant::now(); s = 0;
    for i in 0..n { s += format!("{:.2}", i as f64 / 7.0).len() as i64; }
    rep("float_fixed", t, s);
}
