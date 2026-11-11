// conform: tags=diagnostics
// conform: phase=check
import CsvOptions from "@std/data/csv.ms"
fn example(CsvOptions: fn() Unit) Unit:
    CsvOptions()
