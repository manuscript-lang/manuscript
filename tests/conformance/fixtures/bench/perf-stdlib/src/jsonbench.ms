import (
	JsonValue, parse, stringify from "@std/data/json.ms",

	bench from "./harness.ms",
)

fn json_doc(count Int) String {
	var sb = ""
	sb += "["

	for i in 0..count {
		if i > 0 { sb += "," }
		sb += f"\{\"id\":{i},\"name\":\"user{i}\",\"tags\":[\"a\",\"b\"],\"score\":{i}.5,\"ok\":true\}"
	}

	sb += "]"
	return sb
}

fn encoded_length(value JsonValue) Int {
	if text := stringify(value) {
		return text.length()
	}
	return 0
}

export fn bench_json() Void {
	doc := json_doc(5000)

	bench(
		"json.parse",
		5000,
		fn() Int {
			if parse(doc).is_ok() {
				return 1
			} return 0
		}
	)

	bench(
		"json.roundtrip",
		5000,
		fn() Int {
			if v := parse(doc) {
				return encoded_length(v)
			} return 0
		}
	)
}
