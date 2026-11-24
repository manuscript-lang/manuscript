import (
	each_cell from "@std/data/csv.ms",
	stdin from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
)

type Total:
	rows: Int
	cents: Int

fn main() Void:
	data := read_all(stdin(), null).get().decode_utf8() or ""
	var regions = Map[String, Total]()
	var products = Map[String, Int]()
	var quoted = 0
	var rows = 0
	var region = ""
	var product = ""
	var qty = 0
	var price = 0

	// Cells arrive as views of `data`; only the two keys are copied out.
	visit := fn(row: Int, col: Int, cell: String) Void:
		if row == 0: return

		if col == 1: region = cell.clone()
		else if col == 2: product = cell.clone()
		else if col == 3: qty = cell.parse_int() or 0
		else if col == 4: price = cell.parse_int() or 0
		else if col == 5:
			cents := qty * price
			old := regions.get_or(region, Total(0, 0))
			regions[region.clone()] = Total(old.rows + 1, old.cents + cents)
			products[product.clone()] = products.get_or(product, 0) + cents
			if cell.contains(","): quoted += 1
			rows += 1

	each_cell(data, visit).get()
	print(f"rows: {rows}")
	print(f"quoted: {quoted}")
	for e in regions.entries().sorted(fn a, b: a.key.compare(b.key)):
		print(f"{e.key} {e.value.rows} {e.value.cents}")
	for e in products.entries().sorted(
		fn a,
		b: if a.value != b.value: b.value - a.value else: a.key.compare(b.key)
	).slice(0, 5).get():
		print(f"{e.key} {e.value}")
