// Guard: `each_cell` hands out views of the input, so reading a CSV by cell allocates
// nothing per cell.
import each_cell from "@std/data/csv.ms"

fn main() Void {
	var out = ""
	for i in 0..20000 {
		out += f"{i},region{i % 7},\"item, {i % 13}\",{i % 100},{i % 9}\n"
	}

	var cells = 0
	var total = 0
	count := fn(row, col Int, cell String) Void {
		if col == 3 {
			total += cell.parse_int() or 0
		} else {
			cells += cell.length()
		}
	}
	each_cell(out, count).get()
	print(f"{cells} {total}")
}
