// Generator for c66-sql-case. The expected outputs come from the Go oracle in
// oracle/*.ref (built with the local Go toolchain). The hidden cases are the inputs of
// c52-sql-engine (the behavior that must survive the edit) plus scenarios for CASE
// expressions. Deterministic; run: ms run bench/agent/gen.ms -- c66
import (
	JsonValue, parse from "@std/data/json.ms",

	root from "../../core/model.ms",
	Cases, build_oracle, write_cases from "../../lib/gen.ms",
	read_text from "../../lib/text.ms",
)

fn add(var cs Cases, name, script String) Void {
	cs.push(name, script)
}

// The entries of c52-sql-engine's hidden cases.
fn c52_inputs() List[JsonValue] {
	doc := parse(read_text(f"{root()}/challenges/c52-sql-engine/hidden/cases.json")).get_or(
		JsonValue.Null
	)
	return doc.as_list() or []
}

SETUP := "CREATE TABLE t (id INT PRIMARY KEY, n INT, s TEXT, g TEXT);\nINSERT INTO t VALUES (1, 5, 'apple', 'x'), (2, NULL, 'bee', 'x'), (3, 12, 'cat', 'y'), (4, 0, NULL, 'y'), (5, 7, 'dog', 'z');\n"

export fn gen_c66() Void {
	var cs = Cases(build_oracle("c66-sql-case"))

	for entry in c52_inputs() {
		name := (entry.get("name") or JsonValue.Null).as_string() or ""
		stdin := (entry.get("stdin") or JsonValue.Null).as_string() or ""
		add(cs, f"kept-{name}", stdin)
	}

	add(
		cs,
		"case-basic",
		SETUP
		+ "SELECT id, CASE WHEN n > 10 THEN 'big' WHEN n > 1 THEN 'mid' ELSE 'none' END AS k FROM t ORDER BY id;\n",
	)
	add(
		cs,
		"case-no-else-null",
		SETUP + "SELECT id, CASE WHEN n > 6 THEN n END AS v FROM t ORDER BY id;\n",
	)
	add(
		cs,
		"case-header-name",
		SETUP
		+ "SELECT CASE WHEN n > 6 THEN 1 ELSE 0 END, CASE WHEN id = 1 THEN s END FROM t ORDER BY id;\n",
	)
	add(
		cs,
		"case-first-true-wins",
		SETUP
		+ "SELECT id, CASE WHEN n > 1 THEN 'a' WHEN n > 5 THEN 'b' WHEN 1 = 1 THEN 'c' END AS v FROM t ORDER BY id;\n",
	)
	add(
		cs,
		"case-null-condition",
		SETUP
		+ "SELECT id, CASE WHEN n THEN 1 ELSE 2 END FROM t;\nSELECT id, CASE WHEN n > 1 THEN 'x' ELSE 'y' END AS v FROM t ORDER BY id;\n",
	)
	add(
		cs,
		"case-short-circuit",
		SETUP
		+ "SELECT id, CASE WHEN n IS NULL THEN 0 ELSE 100 / n END AS v FROM t ORDER BY id;\nSELECT CASE WHEN id = 1 THEN 1 ELSE 1 / 0 END FROM t WHERE id = 1;\nSELECT CASE WHEN id = 1 THEN 1 WHEN 1 / 0 = 1 THEN 2 END FROM t WHERE id = 1;\n",
	)
	add(
		cs,
		"case-evaluated-error",
		SETUP + "SELECT CASE WHEN id = 2 THEN 1 / 0 ELSE id END FROM t;\n",
	)
	add(
		cs,
		"case-mixed-types",
		SETUP
		+ "SELECT id, CASE WHEN id < 3 THEN id ELSE s END AS v FROM t ORDER BY id;\n",
	)
	add(
		cs,
		"case-non-boolean-condition",
		SETUP
		+ "SELECT CASE WHEN n THEN 1 END FROM t WHERE id = 1;\nSELECT CASE WHEN s THEN 1 END FROM t WHERE id = 1;\n",
	)
	add(
		cs,
		"case-where",
		SETUP
		+ "SELECT id FROM t WHERE CASE WHEN n IS NULL THEN 1 = 2 WHEN n > 6 THEN 1 = 1 ELSE 1 = 2 END ORDER BY id;\n",
	)
	add(
		cs,
		"case-order-by",
		SETUP
		+ "SELECT id FROM t ORDER BY CASE WHEN g = 'y' THEN 0 ELSE 1 END, id DESC;\n",
	)
	add(
		cs,
		"case-group-by",
		SETUP
		+ "SELECT CASE WHEN n IS NULL THEN 'null' WHEN n > 6 THEN 'hi' ELSE 'lo' END AS b, COUNT(*) AS c FROM t GROUP BY CASE WHEN n IS NULL THEN 'null' WHEN n > 6 THEN 'hi' ELSE 'lo' END ORDER BY b;\n",
	)
	add(
		cs,
		"case-in-aggregate",
		SETUP
		+ "SELECT g, SUM(CASE WHEN n > 6 THEN 1 ELSE 0 END) AS hi, COUNT(CASE WHEN n IS NULL THEN 1 END) AS nulls FROM t GROUP BY g ORDER BY g;\n",
	)
	add(
		cs,
		"case-around-aggregate",
		SETUP
		+ "SELECT g, CASE WHEN COUNT(*) > 1 THEN 'many' ELSE 'one' END AS c FROM t GROUP BY g ORDER BY g;\nSELECT CASE WHEN COUNT(*) > 4 THEN SUM(n) ELSE 0 END FROM t;\n",
	)
	add(
		cs,
		"case-ungrouped-column",
		SETUP + "SELECT g, CASE WHEN n > 1 THEN 1 ELSE 0 END FROM t GROUP BY g;\n",
	)
	add(
		cs,
		"case-having",
		SETUP
		+ "SELECT g FROM t GROUP BY g HAVING CASE WHEN COUNT(*) > 1 THEN SUM(n) > 5 ELSE 1 = 2 END ORDER BY g;\n",
	)
	add(
		cs,
		"case-update",
		SETUP
		+ "UPDATE t SET n = CASE WHEN n IS NULL THEN -1 WHEN n > 6 THEN n * 2 ELSE n END;\nSELECT id, n FROM t ORDER BY id;\n",
	)
	add(
		cs,
		"case-insert",
		SETUP
		+ "INSERT INTO t VALUES (6, CASE WHEN 1 = 1 THEN 60 ELSE 0 END, CASE WHEN 1 = 2 THEN 'a' ELSE 'b' END, 'w');\nSELECT * FROM t WHERE id = 6;\n",
	)
	add(
		cs,
		"case-nested",
		SETUP
		+ "SELECT id, CASE WHEN n IS NULL THEN 'n' ELSE CASE WHEN n > 6 THEN 'hi' ELSE CASE WHEN n = 0 THEN 'zero' ELSE 'lo' END END END AS v FROM t ORDER BY id;\n",
	)
	add(
		cs,
		"case-function-args",
		SETUP
		+ "SELECT UPPER(CASE WHEN id = 1 THEN s ELSE 'z' END), COALESCE(CASE WHEN n > 100 THEN 1 END, -1) FROM t WHERE id < 3 ORDER BY id;\n",
	)
	add(
		cs,
		"case-join",
		SETUP
		+ "CREATE TABLE u (id INT PRIMARY KEY, w INT);\nINSERT INTO u VALUES (1, 10), (3, 30);\nSELECT t.id, CASE WHEN u.w IS NULL THEN 'no' ELSE 'yes' END AS m FROM t LEFT JOIN u ON t.id = u.id ORDER BY t.id;\n",
	)
	add(
		cs,
		"case-keyword-case-insensitive",
		SETUP
		+ "select id, case when n > 6 then 'hi' else 'lo' end as v from t order by id;\n",
	)
	add(
		cs,
		"case-syntax-errors",
		SETUP
		+ "SELECT CASE END FROM t;\nSELECT CASE WHEN n > 1 THEN 1 FROM t;\nSELECT CASE WHEN n > 1 1 END FROM t;\nSELECT CASE n WHEN 1 THEN 2 END FROM t;\nSELECT CASE WHEN n > 1 THEN 1 ELSE END FROM t;\nSELECT CASE WHEN n > 1 THEN 1 ELSE 2 ELSE 3 END FROM t;\nSELECT CASE WHEN n > 1 THEN 1 END END FROM t;\n",
	)
	add(
		cs,
		"case-syntax-before-missing-table",
		"SELECT CASE END FROM nope;\nSELECT CASE WHEN 1 = 1 THEN 1 END FROM nope;\n",
	)
	add(
		cs,
		"case-reserved-words",
		"CREATE TABLE end (a INT);\nCREATE TABLE t (when INT);\nCREATE TABLE t (a INT, case INT);\nCREATE TABLE ok (a INT);\nSELECT a AS then FROM ok;\nSELECT a AS else FROM ok;\n",
	)
	add(
		cs,
		"case-in-select-star-order",
		SETUP
		+ "SELECT * FROM t ORDER BY CASE WHEN n IS NULL THEN 1 ELSE 0 END, n DESC;\n",
	)
	add(
		cs,
		"case-limit-offset",
		SETUP
		+ "SELECT id, CASE WHEN id % 2 = 0 THEN 'even' ELSE 'odd' END AS p FROM t ORDER BY id LIMIT 2 OFFSET 1;\n",
	)
	add(
		cs,
		"case-distinct",
		SETUP
		+ "SELECT DISTINCT CASE WHEN n > 6 THEN 'hi' ELSE 'lo' END AS v FROM t ORDER BY v;\n",
	)
	add(
		cs,
		"case-bool-result",
		SETUP + "SELECT CASE WHEN id = 1 THEN n > 1 ELSE 1 = 2 END FROM t;\n",
	)

	examples := [
		cs.make(
			"ex-case",
			"CREATE TABLE t (a INT, b TEXT);\nINSERT INTO t VALUES (1, 'x'), (NULL, 'y'), (30, 'z');\nSELECT b, CASE WHEN a > 10 THEN 'big' WHEN a > 0 THEN 'small' ELSE 'none' END AS size FROM t ORDER BY b;\n",
		),
		cs.make(
			"ex-case-aggregate",
			"CREATE TABLE t (g TEXT, v INT);\nINSERT INTO t VALUES ('a', 1), ('a', 5), ('b', 7);\nSELECT g, SUM(CASE WHEN v > 3 THEN v ELSE 0 END) AS big FROM t GROUP BY g ORDER BY g;\n",
		),
	]
	write_cases("c66-sql-case", examples, cs.list)
}
