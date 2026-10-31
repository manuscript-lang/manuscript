use std::{hint::black_box, time::{Duration, Instant}};
fn ascii_decode(data: &[u8]) -> Result<String, ()> {
    if !data.is_ascii() { return Err(()); }
    Ok(String::from_utf8(data.to_vec()).unwrap())
}
fn main() {
    for n in [0,1,8,585,149797] { run(format!("ascii.valid.{}", n*7), b"Az09 \n\0".repeat(n), false); }
    for n in [0,8,585,149797] {
        for first in [true,false] {
            let good = b"Az09 \n\0".repeat(n);
            let mut data=Vec::with_capacity(good.len()+1);
            if first {data.push(255);}
            data.extend(good);
            if !first {data.push(255);}
            run(format!("ascii.invalid.{}.{}", if first {"first"} else {"last"}, data.len()),data,true);
        }
    }
    for count in [1,2048,524288] {
        for (name, motif) in [("accent","é"),("emoji","🙂")] {
            run(format!("ascii.unicode.{name}.{count}"),motif.repeat(count).into_bytes(),true);
        }
    }
    for count in [8,524288] {
        for first in [true,false] {
            let tail="A".repeat(count);
            let input=if first {format!("é{tail}")} else {format!("{tail}é")};
            run(format!("ascii.unicode.{}.{count}",if first {"first"} else {"last"}),input.into_bytes(),true);
        }
    }
}
fn run(name: String, data: Vec<u8>, invalid: bool) {
    let expected = if invalid { Err(()) } else { Ok(String::from_utf8(data.clone()).unwrap()) };
    assert_eq!(ascii_decode(&data),expected);
    let work=|| {
        let result=ascii_decode(black_box(&data));
        if invalid { assert!(result.is_err()); }
        let _ = black_box(result);
    };
    let batch=|count| {let start=Instant::now(); for _ in 0..count {work();} start.elapsed()};
    let mut count=1u64;
    while batch(count)<Duration::from_millis(100) {count*=2;}
    let mut samples=Vec::new();
    for _ in 0..5 {samples.push(batch(count).as_nanos() as f64/count as f64);}
    println!("{{\"name\":\"{name}\",\"iterations\":{count},\"samples\":{samples:?}}}");
}
