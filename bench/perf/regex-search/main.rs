use regex::Regex;
fn main() {
    let data = String::from_utf8(std::fs::read("/tmp/regex-search-input.txt").unwrap()).unwrap();
    let re = Regex::new(r"func\s+\w+\(").unwrap();
    let all: Vec<String> = re.find_iter(&data).map(|m| m.as_str().to_string()).collect();
    let spans: Vec<(usize, usize)> = re.find_iter(&data).map(|m| (m.start(), m.end())).collect();
    let rep = re.replace_all(&data, "fn(");
    let word = Regex::new(r"[A-Za-z_]+[0-9]+").unwrap();
    let w: Vec<String> = word.find_iter(&data).map(|m| m.as_str().to_string()).collect();
    println!("{} {} {} {}", all.len(), spans.len(), rep.len(), w.len());
}
