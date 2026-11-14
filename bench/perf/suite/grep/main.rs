use std::io::Read;

fn main() {
    let mut data = String::new();
    std::io::stdin().read_to_string(&mut data).unwrap();
    let hits = data
        .split('\n')
        .filter(|l| l.contains(" POST /api/v2/item/17") && l.contains(" 500 "))
        .count();
    println!("hits: {hits}");
}
