// Deterministic generators of small Manuscript programs for differential testing, a
// port of the generators of the former Rust `ms-conform fuzz` (same SplitMix64 stream,
// so a seed gives the program it always gave).
//
// * `program(seed)`: a well-typed program over Int, Float, Bool, String and `List[Int]`
//   expression trees, loops and a few recursive helpers. Checked Int arithmetic is tracked while
//   generating so most programs finish; roughly one in five ends in a deliberate fault
//   (overflow, division by zero, index out of range) after printing its earlier results.
// * `type_error(seed)`: the same kind of program with one injected type error.
// * `syntax_error(seed)`: the same kind of program with one text mutation.
//
// The output of every generated program is recorded from the oracle, so the generators
// only have to produce programs the oracle accepts or rejects the same way every time.
import (
	bit_xor,
	shift_right_unsigned,
	wrapping_add,
	wrapping_multiply,
	wrapping_subtract from "@std/math/math.ms",

	sorted_unique from "./tags.ms",
)

MAX_INT: Int := 9223372036854775807
MIN_INT: Int := -9223372036854775807 - 1
GOLDEN: Int := -7046029254386353131
MIX_ONE: Int := -4658895280553007687
MIX_TWO: Int := -7723592293110705685
SEED_XOR: Int := -3335678366873096957
WORDS: List[String] := [
	"alpha", "beta", "gamma", "delta", "ms", "x", "hello world", "  padded  ",
	"Tab\\there", "line\\nbreak", "quote\\\"d", "back\\\\slash", "brace{s}", "héllo",
	"日本語", "naïve", "emoji 😀", "", "a", "MiXeD CaSe", "42"
]
HELPER_FACT: String := "fn fact(n: Int) Int:\n    if n <= 1:\n        return 1\n    return n * fact(n - 1)\n"
HELPER_FIB: String := "fn fib(n: Int) Int:\n    var a = 0\n    var b = 1\n    var i = 0\n    while i < n:\n        next := a + b\n        a = b\n        b = next\n        i += 1\n    return a\n"
HELPER_GCD: String := "fn gcd(a: Int, b: Int) Int:\n    if b == 0:\n        return a\n    return gcd(b, a % b)\n"
HELPER_COLLATZ: String := "fn collatz(start: Int) Int:\n    var n = start\n    var steps = 0\n    while n != 1:\n        if n % 2 == 0:\n            n = n / 2\n        else:\n            n = 3 * n + 1\n        steps += 1\n    return steps\n"
// Statements that are each rejected by the checker, to splice into a valid program.
TYPE_ERRORS: List[String] := [
	"    bad: Int = \"text\"", "    bad := 1 + \"one\"",
	"    bad := undefined_name + 1", "    bad := missing_function(3)",
	"    bad: String = 5", "    bad := [1, \"two\"]", "    bad := 1.5 + 2",
	"    bad := true + 1", "    bad := say(1, 2)",
	"    bad := \"abc\".no_such_method()", "    fixed := 1\n    fixed = 2",
	"    bad := (1 < 2) < 3", "    bad: Bool = 1", "    bad := not 5",
	"    bad := [1, 2].get(\"x\")", "    bad := 1 and 2",
	"    if 1:\n        say(\"truthy\")", "    bad := say", "    return \"not an int\"",
	"    bad := Map[Int, Int]().get(1, 2, 3)"
]

// ---- the random stream ----

export type Rng:
	state: Int

export fn rng_new(seed: Int) Rng:
	return Rng(state: bit_xor(wrapping_multiply(seed, GOLDEN), SEED_XOR))

fn next_u64(var rng: Rng) Int:
	rng.state = wrapping_add(rng.state, GOLDEN)

	z := rng.state
	a := wrapping_multiply(bit_xor(z, shift_right_unsigned(z, 30)), MIX_ONE)
	b := wrapping_multiply(bit_xor(a, shift_right_unsigned(a, 27)), MIX_TWO)
	return bit_xor(b, shift_right_unsigned(b, 31))

// A value in 0..n of the unsigned stream.
export fn below(var rng: Rng, n: Int) Int:
	bound := if n < 1: 1 else: n
	z := next_u64(rng)
	if z >= 0: return z % bound

	// z as unsigned is 2 * (z >> 1) + (z & 1), which does not fit an Int.
	half := shift_right_unsigned(z, 1)
	low := z - wrapping_multiply(half, 2)
	return (2 * (half % bound) + low) % bound

fn range(var rng: Rng, low: Int, high: Int) Int:
	return low + below(rng, high - low + 1)

fn chance(var rng: Rng, percent: Int) Bool:
	return below(rng, 100) < percent

fn pick(var rng: Rng, items: List[String]) String:
	return items[below(rng, items.length())].clone()

// ---- checked arithmetic ----

type Checked:
	ok: Bool
	value: Int

fn checked(value: Int) Checked:
	return Checked(ok: true, value: value)

fn overflow() Checked:
	return Checked(ok: false, value: 0)

fn checked_sum(x: Int, y: Int) Checked:
	r := wrapping_add(x, y)
	if (x >= 0) == (y >= 0) and (r >= 0) != (x >= 0): return overflow()

	return checked(r)

fn checked_difference(x: Int, y: Int) Checked:
	r := wrapping_subtract(x, y)
	if (x >= 0) != (y >= 0) and (r >= 0) != (x >= 0): return overflow()

	return checked(r)

fn checked_product(x: Int, y: Int) Checked:
	if x == 0 or y == 0: return checked(0)

	if x == -1:
		if y == MIN_INT: return overflow()
		return checked(-y)

	r := wrapping_multiply(x, y)
	if r / x != y: return overflow()

	return checked(r)

fn checked_quotient(x: Int, y: Int) Checked:
	if y == 0 or (x == MIN_INT and y == -1): return overflow()
	return checked(x / y)

fn checked_remainder(x: Int, y: Int) Checked:
	if y == 0 or (x == MIN_INT and y == -1): return overflow()
	return checked(x % y)

// ---- the generator ----

type IntVar:
	name: String
	value: Int

// `chars` is -1 when the length is not tracked.
type StrVar:
	name: String
	chars: Int

type ListVar:
	name: String
	items: List[Int]

type IntExpr:
	code: String
	ok: Bool
	value: Int

type StrExpr:
	code: String
	chars: Int

type ListExpr:
	code: String
	items: List[Int]

type Gen:
	rng: Rng
	ints: List[IntVar]
	floats: List[String]
	bools: List[String]
	strs: List[StrVar]
	lists: List[ListVar]
	next_id: Int
	out: List[String]
	helpers: List[String]
	tags: List[String]
	// Line counts of `out` at statement boundaries (safe places to splice).
	bounds: List[Int]

// A generated program and the feature tags it exercises.
export type Generated:
	source: String
	tags: List[String]

fn gen_new(seed: Int) Gen:
	return Gen(
		rng: rng_new(seed),
		ints: [],
		floats: [],
		bools: [],
		strs: [],
		lists: [],
		next_id: 0,
		out: [],
		helpers: [],
		tags: ["fuzz"],
		bounds: [],
	)

fn id(var g: Gen, prefix: String) String:
	g.next_id += 1
	return f"{prefix}{g.next_id}"

fn braced(code: String) String:
	return "{" + code + "}"

fn int_literal(var rng: Rng) Int:
	bucket := below(rng, 100)
	if bucket < 70: return range(rng, -50, 50)
	if bucket < 90: return range(rng, -1000000, 1000000)
	if bucket < 98: return range(rng, -1000000000000, 1000000000000)

	choices: List[Int] := [MAX_INT, MIN_INT, MAX_INT - 1, MIN_INT + 1, 0, 1, -1]
	return choices[below(rng, choices.length())]

// Source text of an Int literal; negatives are parenthesized so they nest anywhere.
fn int_code(n: Int) String:
	if n == MIN_INT: return "(-9223372036854775808)"
	if n < 0: return f"({n})"

	return f"{n}"

fn float_literal(var rng: Rng) String:
	kind := below(rng, 10)
	if kind == 0: return "0.0"
	if kind == 1: return f"{range(rng, 0, 9)}.5"
	if kind == 2: return f"{range(rng, 0, 1000)}.25"

	if kind == 3:
		mantissa := range(rng, 1, 9)
		exponent := range(rng, -9, 25)
		return f"{mantissa}.0e{exponent}"

	whole := range(rng, 0, 999)
	frac := range(rng, 0, 999)
	padded := if frac < 10: f"00{frac}" else: if frac < 100: f"0{frac}" else: f"{frac}"
	return f"{whole}.{padded}"

// The characters of `word` once escapes are processed.
fn escaped_len(word: String) Int:
	var n = 0
	var skip = false

	for c in word.chars():
		if skip:
			skip = false
			continue

		if c == "\\": skip = true
		n += 1

	return n

fn int_leaf(var g: Gen) IntExpr:
	if not g.ints.is_empty() and chance(g.rng, 55):
		v := g.ints[below(g.rng, g.ints.length())].clone()
		return IntExpr(code: v.name.clone(), ok: true, value: v.value)

	n := int_literal(g.rng)
	return IntExpr(code: int_code(n), ok: true, value: n)

fn binary(code: String, left: IntExpr, right: IntExpr, result: Checked) IntExpr:
	return IntExpr(
		code: code.clone(),
		ok: left.ok and right.ok and result.ok,
		value: result.value,
	)

// An Int expression and its value; `ok` is false when evaluating it faults.
fn int_expr(var g: Gen, depth: Int) IntExpr:
	if depth == 0 or chance(g.rng, 25): return int_leaf(g)

	which := below(g.rng, 12)

	if which <= 8:
		a := int_expr(g, depth - 1)
		b := int_expr(g, depth - 1)
		x := a.value
		y := b.value
		if which <= 2: return binary(f"({a.code} + {b.code})", a, b, checked_sum(x, y))
		if which <= 4: return binary(
			f"({a.code} - {b.code})",
			a,
			b,
			checked_difference(x, y),
		)
		if which <= 6: return binary(
			f"({a.code} * {b.code})",
			a,
			b,
			checked_product(x, y),
		)
		if which == 7: return binary(
			f"({a.code} / {b.code})",
			a,
			b,
			checked_quotient(x, y),
		)

		return binary(f"({a.code} % {b.code})", a, b, checked_remainder(x, y))

	if which == 9:
		a := int_expr(g, depth - 1)
		if a.value == MIN_INT: return IntExpr(code: f"(-{a.code})", ok: false, value: 0)

		return IntExpr(code: f"(-{a.code})", ok: a.ok, value: -a.value)

	if which == 10:
		if g.strs.is_empty(): return int_leaf(g)

		s := g.strs[below(g.rng, g.strs.length())].clone()
		g.tags.append("strings")
		return IntExpr(
			code: f"{s.name}.scalar_length()",
			ok: s.chars >= 0,
			value: s.chars,
		)

	if g.lists.is_empty(): return int_leaf(g)

	l := g.lists[below(g.rng, g.lists.length())].clone()
	g.tags.append("lists")
	if chance(g.rng, 50) or l.items.is_empty():
		return IntExpr(code: f"{l.name}.length()", ok: true, value: l.items.length())

	i := below(g.rng, l.items.length())
	return IntExpr(code: f"{l.name}.get({i})", ok: true, value: l.items[i])

// Retries until the expression does not fault.
fn safe_int(var g: Gen, depth: Int) IntExpr:
	for _attempt in 0..24:
		e := int_expr(g, depth)
		if e.ok: return e

	n := range(g.rng, -20, 20)
	return IntExpr(code: int_code(n), ok: true, value: n)

fn float_expr(var g: Gen, depth: Int) String:
	if depth == 0 or chance(g.rng, 30):
		if not g.floats.is_empty() and chance(g.rng, 50): return pick(g.rng, g.floats)
		return float_literal(g.rng)

	a := float_expr(g, depth - 1)
	b := float_expr(g, depth - 1)
	which := below(g.rng, 6)
	if which <= 1: return f"({a} + {b})"
	if which == 2: return f"({a} - {b})"
	if which <= 4: return f"({a} * {b})"

	return f"({a} / {b})"

fn str_expr(var g: Gen, depth: Int) StrExpr:
	if depth == 0 or chance(g.rng, 35):
		if not g.strs.is_empty() and chance(g.rng, 45):
			v := g.strs[below(g.rng, g.strs.length())].clone()
			return StrExpr(code: v.name.clone(), chars: v.chars)

		word := pick(g.rng, WORDS)
		return StrExpr(code: "\"" + word + "\"", chars: escaped_len(word))

	a := str_expr(g, depth - 1)
	which := below(g.rng, 9)

	if which <= 2:
		b := str_expr(g, depth - 1)
		chars := if a.chars >= 0 and b.chars >= 0: a.chars + b.chars else: -1
		return StrExpr(code: f"({a.code} + {b.code})", chars: chars)

	if which == 3: return StrExpr(code: f"{a.code}.upper()", chars: a.chars)
	if which == 4: return StrExpr(code: f"{a.code}.lower()", chars: a.chars)
	if which == 5: return StrExpr(code: f"{a.code}.trim()", chars: -1)
	if which == 6: return StrExpr(code: f"{a.code}.reverse()", chars: a.chars)

	if which == 7:
		n := safe_int(g, 1)
		return StrExpr(
			code: "(f\"" + braced(n.code) + ":\" + " + a.code + ")",
			chars: -1,
		)

	b := str_expr(g, 0)
	c := str_expr(g, 0)
	return StrExpr(code: f"{a.code}.replace({b.code}, {c.code})", chars: -1)

fn bool_expr(var g: Gen, depth: Int) String:
	if depth == 0 or chance(g.rng, 20):
		if not g.bools.is_empty() and chance(g.rng, 50): return pick(g.rng, g.bools)
		return if chance(g.rng, 50): "true" else: "false"

	which := below(g.rng, 9)

	if which == 0:
		a := safe_int(g, depth - 1)
		b := safe_int(g, depth - 1)
		op := pick(g.rng, ["<", "<=", ">", ">=", "==", "!="])
		return f"({a.code} {op} {b.code})"

	if which == 1:
		a := float_expr(g, depth - 1)
		b := float_expr(g, depth - 1)
		op := pick(g.rng, ["<", ">", "==", "!="])
		return f"({a} {op} {b})"

	if which == 2:
		a := str_expr(g, depth - 1)
		b := str_expr(g, 0)
		method := pick(g.rng, ["contains", "starts_with", "ends_with"])
		return f"{a.code}.{method}({b.code})"

	if which == 3:
		a := str_expr(g, depth - 1)
		b := str_expr(g, depth - 1)
		op := pick(g.rng, ["==", "!="])
		return f"({a.code} {op} {b.code})"

	if which == 4: return f"(not {bool_expr(g, depth - 1)})"

	if which <= 6:
		left := bool_expr(g, depth - 1)
		right := bool_expr(g, depth - 1)
		return f"({left} and {right})"

	if which == 7:
		left := bool_expr(g, depth - 1)
		right := bool_expr(g, depth - 1)
		return f"({left} or {right})"

	a := str_expr(g, depth - 1)
	return f"{a.code}.is_empty()"

fn list_code(items: List[Int]) String:
	var parts = List[String]()
	for item in items: parts.append(int_code(item))
	return "[" + parts.join(", ") + "]"

// A small bounded list expression with a tracked value.
fn list_expr(var g: Gen, depth: Int) ListExpr:
	if depth == 0 or g.lists.is_empty() or chance(g.rng, 30):
		n := below(g.rng, 6)
		var items = List[Int]()
		for _index in 0..n: items.append(range(g.rng, -30, 30))

		// An empty literal has no element type; spell one out.
		if items.is_empty(): return ListExpr(code: "[1, 2, 3].take(0)", items: items)

		return ListExpr(code: list_code(items), items: items)

	base := g.lists[below(g.rng, g.lists.length())].clone()
	g.tags.append("closures")

	which := below(g.rng, 9)
	var items = List[Int]()

	if which == 0:
		k := range(g.rng, 2, 9)
		for x in base.items: items.append(x * k)
		return ListExpr(code: f"{base.name}.map(fn(x): x * {k})", items: items)

	if which == 1:
		k := range(g.rng, -5, 5)
		for x in base.items:
			if x > k: items.append(x)
		return ListExpr(
			code: f"{base.name}.filter(fn x: x > {int_code(k)})",
			items: items,
		)

	if which == 2:
		items = base.items.clone()
		items.sort()
		return ListExpr(
			code: f"{base.name}.sorted(fn a, b: a.compare(b))",
			items: items,
		)

	if which == 3:
		for index in 0..base.items.length(): items.append(
			base.items[base.items.length() - 1 - index]
		)
		return ListExpr(code: f"{base.name}.reversed()", items: items)

	if which == 4:
		other := g.lists[below(g.rng, g.lists.length())].clone()
		items = base.items.clone()
		for x in other.items: items.append(x)
		return ListExpr(code: f"{base.name}.concat({other.name})", items: items)

	if which == 5:
		n := range(g.rng, 0, 4)
		for index in 0..base.items.length():
			if index < n: items.append(base.items[index])
		return ListExpr(code: f"{base.name}.take({n})", items: items)

	if which == 6:
		n := range(g.rng, 0, 4)
		for index in 0..base.items.length():
			if index >= n: items.append(base.items[index])
		return ListExpr(code: f"{base.name}.drop({n})", items: items)

	if which == 7:
		// append mutates its receiver and returns Void; concat returns a new list.
		k := range(g.rng, -9, 99)
		items = base.items.clone()
		items.append(k)
		return ListExpr(code: f"{base.name}.concat([{int_code(k)}])", items: items)

	k := range(g.rng, 1, 4)
	for x in base.items:
		if (x + k) % 2 == 0: items.append(x + k)
	return ListExpr(
		code: f"{base.name}.map(fn(x): x + {k}).filter(fn(x): x % 2 == 0)",
		items: items,
	)

fn say_line(name: String) String:
	return "    say(f\"" + name + " = " + braced(name) + "\")"

fn statement(var g: Gen) Void:
	statement_body(g)
	g.bounds.append(g.out.length())

fn statement_body(var g: Gen) Void:
	which := below(g.rng, 16)

	if which <= 3:
		e := safe_int(g, 3)
		name := id(g, "i")
		g.out.append(f"    {name} := {e.code}")
		g.out.append(say_line(name))
		g.ints.append(IntVar(name: name.clone(), value: e.value))
		g.tags.append("numbers")
		return

	if which <= 5:
		code := float_expr(g, 3)
		name := id(g, "f")
		g.out.append(f"    {name} := {code}")
		g.out.append(say_line(name))
		g.floats.append(name.clone())
		g.tags.append("numbers")
		return

	if which <= 7:
		e := str_expr(g, 3)
		name := id(g, "s")
		g.out.append(f"    {name} := {e.code}")
		g.out.append("    say(f\"" + name + " = [" + braced(name) + "]\")")
		g.strs.append(StrVar(name: name.clone(), chars: e.chars))
		g.tags.append("strings")
		g.tags.append("interpolation")
		return

	if which <= 9:
		code := bool_expr(g, 3)
		name := id(g, "b")
		g.out.append(f"    {name} := {code}")
		g.out.append(say_line(name))
		g.bools.append(name.clone())
		return

	if which <= 11:
		e := list_expr(g, 2)
		name := id(g, "l")
		g.out.append(f"    {name} := {e.code}")
		g.out.append(
			"    say(f\"" + name + " = " + braced(name) + " len " + braced(
				name + ".length()"
			) + "\")"
		)
		g.lists.append(ListVar(name: name.clone(), items: e.items.clone()))
		g.tags.append("lists")
		return

	if which == 12: return loop_statement(g)
	if which == 13: return branch_statement(g)
	if which == 14: return helper_call(g)

	a := safe_int(g, 2)
	b := safe_int(g, 2)
	g.out.append(
		"    say(f\"" + braced(a.code) + " " + braced(b.code) + " " + braced(
			"(" + a.code + " < " + b.code + ")"
		) + " sum " + braced(a.code + " + " + b.code) + "\")"
	)
	g.tags.append("interpolation")

fn loop_statement(var g: Gen) Void:
	n := range(g.rng, 0, 8)
	k := range(g.rng, -5, 9)
	name := id(g, "acc")
	kind := below(g.rng, 3)
	g.tags.append("control-flow")

	if kind == 0:
		g.out.append(f"    var {name} = 0")
		g.out.append(f"    for i in 0..{n}:")
		g.out.append(f"        {name} += i * {int_code(k)}")
		g.out.append(say_line(name))
		return

	if kind == 1:
		g.out.append(f"    var {name} = 0")
		g.out.append(f"    var step{name} = 0")
		g.out.append(f"    while step{name} < {n}:")
		g.out.append(f"        step{name} += 1")
		g.out.append(f"        {name} += step{name} * step{name} + {int_code(k)}")
		g.out.append(say_line(name))
		return

	if g.lists.is_empty(): return

	l := g.lists[below(g.rng, g.lists.length())].clone()
	g.out.append(f"    var {name} = 0")
	g.out.append(f"    for x in {l.name}:")
	g.out.append("        if x % 2 == 0:")
	g.out.append(f"            {name} += x")
	g.out.append("        else:")
	g.out.append(f"            {name} -= 1")
	g.out.append(say_line(name))

fn branch_statement(var g: Gen) Void:
	cond := bool_expr(g, 2)
	a := str_expr(g, 1)
	b := str_expr(g, 1)
	g.tags.append("control-flow")
	g.out.append(f"    if {cond}:")
	g.out.append(f"        say({a.code})")
	g.out.append("    else:")
	g.out.append(f"        say({b.code})")

fn helper_call(var g: Gen) Void:
	g.tags.append("functions")

	which := below(g.rng, 4)

	if which == 0:
		n := range(g.rng, 0, 20)
		g.helpers.append(HELPER_FACT.clone())
		g.out.append(
			"    say(f\"fact(" + f"{n}" + ") = " + braced(
				f"fact({n})"
			) + "\")"
		)
		return

	if which == 1:
		n := range(g.rng, 0, 60)
		g.helpers.append(HELPER_FIB.clone())
		g.out.append("    say(f\"fib(" + f"{n}" + ") = " + braced(f"fib({n})") + "\")")
		return

	if which == 2:
		a := range(g.rng, 1, 5000)
		b := range(g.rng, 1, 5000)
		g.helpers.append(HELPER_GCD.clone())
		g.out.append(
			"    say(f\"gcd(" + f"{a}, {b}" + ") = " + braced(
				f"gcd({a}, {b})"
			) + "\")"
		)
		return

	n := range(g.rng, 1, 3000)
	g.helpers.append(HELPER_COLLATZ.clone())
	g.out.append(
		"    say(f\"collatz(" + f"{n}" + ") = " + braced(
			f"collatz({n})"
		) + "\")"
	)

// A last statement that must fault, after everything above has printed.
fn fault_statement(var g: Gen) Void:
	g.tags.append("faults")

	big := id(g, "big")
	kind := below(g.rng, 7)
	k := range(g.rng, 1, 5)

	if kind == 0:
		g.out.append(f"    {big} := 9223372036854775807")
		g.out.append("    say(f\"" + braced(f"{big} + {k}") + "\")")
	else if kind == 1:
		g.out.append(f"    {big} := 9223372036854775807")
		g.out.append("    say(f\"" + braced(f"{big} * {k + 1}") + "\")")
	else if kind == 2:
		g.out.append(f"    {big} := -9223372036854775808")
		g.out.append("    say(f\"" + braced(f"{big} - {k}") + "\")")
	else if kind == 3:
		g.out.append(f"    {big} := -9223372036854775808")
		g.out.append("    say(f\"" + braced(f"-{big}") + "\")")
	else if kind == 4:
		a := safe_int(g, 2)
		g.out.append(f"    {big} := {a.code} - {a.code}")
		g.out.append("    say(f\"" + braced(f"{a.code} / {big}") + "\")")
	else if kind == 5:
		a := safe_int(g, 2)
		g.out.append(f"    {big} := {a.code} - {a.code}")
		g.out.append("    say(f\"" + braced(f"{a.code} % {big}") + "\")")
	else if g.lists.is_empty():
		g.out.append(f"    {big} := [1, 2, 3]")
		g.out.append("    say(f\"" + braced(f"{big}.get({3 + k})") + "\")")
	else:
		l := g.lists[below(g.rng, g.lists.length())].clone()
		g.out.append(
			"    say(f\"" + braced(
				f"{l.name}.get({l.items.length() + k})"
			) + "\")"
		)

fn assemble(g: Gen, seed: Int) Generated:
	var source = f"// Generated by ms-conform fuzz, seed {seed}.\n"
	source += "import stdout from \"@std/io/io.ms\"\n"
	source += "\nfn say(text: String) Void:\n    _written := stdout().write(f\"{text}\\n\")\n\n"

	var seen = List[String]()

	for helper in g.helpers:
		if not seen.contains(helper):
			source += helper + "\n"
			seen.append(helper.clone())

	source += "export fn main() Int:\n"
	for line in g.out: source += line + "\n"
	source += "    return 0\n"
	return Generated(source: source, tags: sorted_unique(g.tags))

// A valid program for `seed`.
export fn program(seed: Int) Generated:
	var g = gen_new(seed)
	count := 6 + below(g.rng, 14)
	for _index in 0..count: statement(g)
	if chance(g.rng, 20): fault_statement(g)
	return assemble(g, seed)

// A program with one injected type error; checking it must fail the same way every
// time.
export fn type_error(seed: Int) Generated:
	var g = gen_new(bit_xor(seed, 0x5eed))
	count := 2 + below(g.rng, 6)
	for _index in 0..count: statement(g)

	var at = 0
	if not g.bounds.is_empty(): at = g.bounds[below(g.rng, g.bounds.length())]

	error := pick(g.rng, TYPE_ERRORS)
	g.out.insert(at, error.clone())
	g.tags.append("diagnostics")
	g.tags.append("types")
	return assemble(g, seed)

// `line` without its first `text`.
fn without_first(line: String, text: String) String:
	at := line.index_of(text) or (-1)
	if at < 0: return line.clone()

	return line.slice(0, at) + line.slice(at + text.length(), line.length())

// A valid program mutated at the text level; the oracle decides how it fails.
export fn syntax_error(seed: Int) Generated:
	var g = gen_new(bit_xor(seed, 0xbad))
	count := 2 + below(g.rng, 5)
	for _index in 0..count: statement(g)

	valid := assemble(g, seed)
	var rng = rng_new(bit_xor(seed, 0xf00d))
	var lines = valid.source.split("\n")
	lines.pop()

	var body_start = 0

	for index in 0..lines.length():
		if lines[index].starts_with("export fn main"):
			body_start = index + 1
			break

	at := body_start + below(rng, lines.length() - body_start)
	line := lines[at].clone()
	var chars = List[String]()
	for c in line.chars(): chars.append(c.clone())

	which := below(rng, 9)
	var mutated = line.replace(" = ", " == ")

	if which == 0: mutated = ""
	else if which == 1 and not chars.is_empty():
		skip := below(rng, chars.length())
		mutated = ""
		for index in 0..chars.length():
			if index != skip: mutated += chars[index]
	else if which == 2: mutated = line + ")"
	else if which == 3: mutated = line + " +"
	else if which == 4: mutated = "  " + line
	else if which == 5: mutated = without_first(line, "(")
	else if which == 6: mutated = without_first(line, "\"")
	else if which == 7: mutated = line + ":"

	lines[at] = mutated
	return Generated(
		source: lines.join("\n") + "\n",
		tags: ["diagnostics", "fuzz", "layout", "parser"],
	)
