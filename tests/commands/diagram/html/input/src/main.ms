import parse_total from "./shapes.ms"

fn main() Int {
	total := parse_total(["3", "4", "x"])
	return total - 8
}
