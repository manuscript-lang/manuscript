// Parses 5000 rows 200 times, then writes them back 200 times, and prints each best
// run in microseconds, materializing every cell as an owned String like the
// Manuscript side.
use std::time::Instant;

fn rows_of(shape: &str) -> String {
    let mut text = String::new();
    for i in 0..5000 {
        if shape == "quoted" {
            text.push_str(&format!("{i},name {i},\"a,b\",\"quote\"\"d\"\n"));
        } else {
            text.push_str(&format!("{i},name {i},alpha,beta,gamma\n"));
        }
    }
    text
}

fn main() {
    for shape in ["quoted", "plain"] {
        let text = rows_of(shape);
        let mut best = u128::MAX;
        let mut count = 0;
        let mut parsed: Vec<Vec<String>> = Vec::new();
        for _ in 0..200 {
            let started = Instant::now();
            let mut reader = csv::ReaderBuilder::new()
                .has_headers(false)
                .from_reader(text.as_bytes());
            let mut rows: Vec<Vec<String>> = Vec::new();
            for record in reader.records() {
                let record = record.unwrap();
                rows.push(record.iter().map(|cell| cell.to_string()).collect());
            }
            count = rows.len();
            parsed = rows;
            best = best.min(started.elapsed().as_micros());
        }
        println!("rust {shape} rows={count} best_us={best}");

        let mut best_write = u128::MAX;
        let mut written = 0;
        for _ in 0..200 {
            let started = Instant::now();
            let mut writer = csv::Writer::from_writer(Vec::new());
            for row in &parsed {
                writer.write_record(row).unwrap();
            }
            written = writer.into_inner().unwrap().len();
            best_write = best_write.min(started.elapsed().as_micros());
        }
        println!("rust {shape}-write bytes={written} best_us={best_write}");
    }
}
