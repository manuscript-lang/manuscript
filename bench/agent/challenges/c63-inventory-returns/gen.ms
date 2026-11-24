// Generator for c63-inventory-returns. The expected outputs come from the Go oracle in
// oracle/*.ref (built with the local Go toolchain). The hidden cases are the inputs of
// c13-inventory-orders (the behavior that must survive the edit) plus the new return
// scenarios. Deterministic; run: ms run bench/agent/gen.ms -- c63
import (
	JsonValue, parse from "@std/data/json.ms",

	root from "../../core/model.ms",
	Cases, build_oracle, write_cases from "../../lib/gen.ms",
	read_text from "../../lib/text.ms",
)

fn add(var cs Cases, name, script String) Void {
	cs.push(name, script)
}

// The `stdin` of every hidden case of c13-inventory-orders, by case name.
fn c13_inputs() List[JsonValue] {
	doc := parse(
		read_text(f"{root()}/challenges/c13-inventory-orders/hidden/cases.json")
	).get_or(JsonValue.Null)
	return doc.as_list() or []
}

export fn gen_c63() Void {
	var cs = Cases(build_oracle("c63-inventory-returns"))

	for entry in c13_inputs() {
		name := (entry.get("name") or JsonValue.Null).as_string() or ""
		stdin := (entry.get("stdin") or JsonValue.Null).as_string() or ""
		add(cs, f"kept-{name}", stdin)
	}

	setup := "stock A 100\nstock B 50\nprice A 250\nprice B 1999\n"
	add(
		cs,
		"return-basic",
		setup + "order o1 A:12 B:2\nship o1\nreturn o1 A 5\nreturn o1 B 1\nreport\n",
	)
	add(
		cs,
		"return-refund-rounding",
		"stock A 10\nprice A 333\norder o1 A:3\nship o1\nreturn o1 A 1\nreturn o1 A 1\nreturn o1 A 1\nreport\n",
	)
	add(
		cs,
		"return-discounted-line",
		"stock A 50\nprice A 199\norder o1 A:10\nship o1\nreturn o1 A 1\nreturn o1 A 3\nreturn o1 A 6\nreturn o1 A 1\nreport\n",
	)
	add(
		cs,
		"return-state-errors",
		setup
		+ "order o1 A:2\nreturn o1 A 1\nship o1\ncancel o1\nreturn o1 A 1\norder o2 A:2\ncancel o2\nreturn o2 A 1\nreturn o3 A 1\n",
	)
	add(
		cs,
		"return-limit-errors",
		setup
		+ "order o1 A:4 B:1\nship o1\nreturn o1 A 5\nreturn o1 A 4\nreturn o1 A 1\nreturn o1 B 2\nreturn o1 B 1\nreturn o1 B 1\nreturn o1 C 1\nreport\n",
	)
	add(
		cs,
		"return-syntax-errors",
		setup
		+ "order o1 A:4\nship o1\nreturn\nreturn o1\nreturn o1 A\nreturn o1 A 1 2\nreturn O1 A 1\nreturn o1 a 1\nreturn o1 A 0\nreturn o1 A 100001\nreturn o1 A x\nreturn o1 A 01\nreturn o1 A 1\nreturn nosuch a 1\nreport\n",
	)
	add(
		cs,
		"return-restocks",
		"stock A 10\nprice A 100\norder o1 A:10\nship o1\norder o2 A:1\nreturn o1 A 4\norder o2 A:4\nreport\nreturn o1 A 6\nreport\n",
	)
	add(
		cs,
		"return-price-changed",
		setup + "order o1 A:2\nship o1\nprice A 1\nreturn o1 A 1\nreport\n",
	)
	add(
		cs,
		"return-two-orders-report",
		setup
		+ "order o1 A:1\norder o2 A:20 B:1\nship o1\nship o2\nreturn o2 A 7\nreturn o1 A 1\nreturn o2 B 1\nreport\n",
	)
	add(
		cs,
		"return-free-item",
		"stock A 5\norder o1 A:2\nship o1\nreturn o1 A 1\nreport\n",
	)

	examples := [
		cs.make(
			"ex-return",
			"stock A 20\nprice A 250\norder o1 A:12\nship o1\nreturn o1 A 5\nreturn o1 A 8\nreport\n",
		),
		cs.make(
			"ex-return-errors",
			"stock A 5\nprice A 100\norder o1 A:2\nreturn o1 A 1\nship o1\nreturn o1 B 1\nreturn o2 A 1\nreport\n",
		),
	]
	write_cases("c63-inventory-returns", examples, cs.list)
}
