import (
	JsonValue, parse, stringify from "@std/data/json.ms",
	StringBuilder from "@std/string.ms",
	keep, measure from "@std/test/bench.ms",
)

fn json_doc(count: Int) String:
	var sb = StringBuilder()
	sb.append("[")

	for i in 0..count:
		if i > 0: sb.append(",")
		sb.append(
			"\{\"id\":{i},\"name\":\"user{i}\",\"tags\":[\"a\",\"b\"],\"score\":{i}.5,\"ok\":true\}"
		)

	sb.append("]")
	return sb.build()

fn encoded_length(value: JsonValue) Int:
	if text := stringify(value): return text.length()
	return 0

// Reads three nested fields of one row in place, without copying any subtree.
fn row_weight(tree: JsonValue, index: Int) Int:
	if row := tree.at(index):
		var weight = 0
		if id := row.get("id"):
			weight += id.as_int().get(0)
		if tags := row.get("tags"):
			if last := tags.at(-1):
				if tag := last.as_string():
					weight += tag.length()
		return weight

	return 0

bench "json.parse":
	doc := json_doc(5000)

	fn work() Result[Unit, Error]:
		if parse(doc).is_ok(): return keep(1)
		return keep(0)

	measure(5000, work)?

bench "json.roundtrip":
	doc := json_doc(5000)

	fn work() Result[Unit, Error]:
		if v := parse(doc): return keep(encoded_length(v))
		return keep(0)

	measure(5000, work)?

bench "json.navigate":
	doc := json_doc(5000)

	if tree := parse(doc):
		fn work() Result[Unit, Error]:
			var total = 0
			for i in 0..100000:
				total += row_weight(tree, i % 5000)
			return keep(total)

		measure(100000, work)?
