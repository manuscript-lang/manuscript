// conform: tags=diagnostics
// conform: phase=check
import SetBuilder from "@std/collections/collections.ms"
import CsvOptions from "@std/data/csv.ms"
fn example() Unit:
    SetBuilder[String]()
    CsvOptions(delimiter: ",", line_ending: "\n")
