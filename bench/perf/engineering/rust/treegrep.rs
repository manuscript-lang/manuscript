use std::fs;
use std::path::Path;

fn scan(dir: &Path, files: &mut u64, matches: &mut u64) {
    for entry in fs::read_dir(dir).unwrap() {
        let path = entry.unwrap().path();
        if path.is_dir() {
            scan(&path, files, matches);
            continue;
        }
        *files += 1;
        let text = fs::read_to_string(&path).unwrap();
        for line in text.split('\n') {
            if line.contains(" POST /api/v2/item/17") && line.contains(" 500 ") {
                *matches += 1;
            }
        }
    }
}

fn main() {
    let root = std::env::args().nth(1).unwrap();
    let (mut files, mut matches) = (0, 0);
    scan(Path::new(&root), &mut files, &mut matches);
    println!("files: {files}");
    println!("matches: {matches}");
}
