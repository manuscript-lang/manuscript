fn main() {
    let mut a = String::new();
    for i in 0..50000 { a += &i.to_string(); }
    let mut b = String::new();
    for i in 0..50000 { b += &format!("item-{i},"); }
    let mut c = String::new();
    for _ in 0..50000 { c += "item,"; }
    let parts: Vec<String> = (0..50000).map(|i| format!("p{i}")).collect();
    let d = parts.join(",");
    println!("{} {} {} {}", a.len(), b.len(), c.len(), d.len());
}
