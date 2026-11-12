use std::collections::HashMap;
use std::io::Read;

// RFC 4180 records; a field with quotes is unescaped into an owned string.
fn parse(data: &str) -> Vec<Vec<String>> {
    let b = data.as_bytes();
    let (mut rows, mut row, mut field) = (Vec::new(), Vec::new(), Vec::new());
    let (mut i, mut in_quotes) = (0, false);
    while i < b.len() {
        let c = b[i];
        if in_quotes {
            if c == b'"' {
                if i + 1 < b.len() && b[i + 1] == b'"' {
                    field.push(b'"');
                    i += 1;
                } else {
                    in_quotes = false;
                }
            } else {
                field.push(c);
            }
        } else if c == b'"' && field.is_empty() {
            in_quotes = true;
        } else if c == b',' {
            row.push(String::from_utf8(std::mem::take(&mut field)).unwrap());
        } else if c == b'\n' {
            row.push(String::from_utf8(std::mem::take(&mut field)).unwrap());
            rows.push(std::mem::take(&mut row));
        } else {
            field.push(c);
        }
        i += 1;
    }
    rows
}

fn main() {
    let mut data = String::new();
    std::io::stdin().read_to_string(&mut data).unwrap();
    let rows = parse(&data);
    let mut regions: HashMap<&str, (u64, u64)> = HashMap::new();
    let mut products: HashMap<&str, u64> = HashMap::new();
    let mut quoted = 0;
    for r in &rows[1..] {
        let cents = r[3].parse::<u64>().unwrap_or(0) * r[4].parse::<u64>().unwrap_or(0);
        let e = regions.entry(&r[1]).or_insert((0, 0));
        e.0 += 1;
        e.1 += cents;
        *products.entry(&r[2]).or_insert(0) += cents;
        if r[5].contains(',') {
            quoted += 1;
        }
    }
    println!("rows: {}", rows.len() - 1);
    println!("quoted: {quoted}");
    let mut rs: Vec<_> = regions.into_iter().collect();
    rs.sort();
    for (k, (n, c)) in rs {
        println!("{k} {n} {c}");
    }
    let mut ps: Vec<_> = products.into_iter().collect();
    ps.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
    for (k, v) in ps.iter().take(5) {
        println!("{k} {v}");
    }
}
