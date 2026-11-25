// conform: tags=diagnostics
// conform: phase=check
import (
	SetBuilder from "@std/collections/collections.ms",
	CsvOptions from "@std/data/csv.ms",
)

fn example() Void {
	SetBuilder[String]()
	CsvOptions(delimiter: ",", line_ending: "\n")
}
