// conform: tags=closures,control-flow,faults,formatter,generics,interfaces,lists,modules,optional,parser,records,stdlib-testing,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/field-defaults.ms
import expect_equal, expect_false, expect_true from "@std/test/test.ms"

type Counter {
	value Int = 0
}

fn mark(var counter Counter, value Int) Int {
	counter.value = counter.value * 10 + value
	return value
}

type Ordered {
	counter Counter
	first Int = mark(counter: counter, value: 3)
	second Int = mark(counter: counter, value: 4)
	third Int = first + second
}

type Data {
	number Int = 5
	values List[Int] = [number]
	callback fn() Int = (
		() => {
			return number
		}
	)
}

type Box[T] {
	value T
	copy T = value
}

fn unit_default(var calls List[Int]) Void {
	calls.append(1)
}

type Explicit {
	calls List[Int]
	nothing Void = unit_default(calls)
	option Int? = 9
}

test "record defaults and explicit overrides" {
	data := Data()
	(
		(
			data.number != 5
			or data.values[0] != 5
			or data.callback() != 5
		) | expect_false?
	)

	changed := Data(number: 0)
	(
		(
			(
				changed.number != 0
				or changed.values[0] != 0
				or changed.callback() != 0
			)
		) | expect_false?
	)

	calls List[Int] := []
	explicit := Explicit(calls: calls.clone(), nothing: void, option: null)
	calls.is_empty() | expect_true?
	(explicit.option == null) | expect_true?

	box := Box(value: "text")
	box.copy | expect_equal("text")?

	specified := Box[Int](value: 7, copy: 0)
	specified.copy | expect_equal(0)?
}

test "supplied fields precede defaults in field order" {
	var log = Counter()
	ordered := Ordered(
		counter: Counter(),
		third: mark(counter: log, value: 1),
		second: mark(counter: log, value: 2),
	)
	(
		(
			(
				log.value != 12
				or ordered.first != 3
				or ordered.second != 2
				or ordered.third != 1
			)
		) | expect_false?
	)

	again := Ordered(counter: Counter())
	(again.third != 7) | expect_false?
}

test "mutable defaults have fresh storage" {
	var first = Data()
	second := Data()
	first.values.append(8)
	(first.values.length() != 2 or second.values.length() != 1) | expect_false?
}

interface ReadWithDefault {
	fn get(fallback Int?) Int
}

type Reader {
	number Int = 5
}

fn Reader.get(fallback Int?) Int {
	return fallback or self.number
}

type Marker { ... }

fn no_op() Void { ... }

test "ordinary empty declarations and interface omission" {
	no_op()

	_marker := Marker()
	view ReadWithDefault := Reader()
	(view.get() != 5 or view.get(fallback: 7) != 7) | expect_false?
}
// expect-format: rewritten
// expect-formatted: import expect_equal, expect_false, expect_true from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: type Counter {
// expect-formatted: \tvalue Int = 0
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn mark(var counter Counter, value Int) Int {
// expect-formatted: \tcounter.value = counter.value * 10 + value
// expect-formatted: \treturn value
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Ordered {
// expect-formatted: \tcounter Counter
// expect-formatted: \tfirst Int = mark(counter: counter, value: 3)
// expect-formatted: \tsecond Int = mark(counter: counter, value: 4)
// expect-formatted: \tthird Int = first + second
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Data {
// expect-formatted: \tnumber Int = 5
// expect-formatted: \tvalues List[Int] = [number]
// expect-formatted: \tcallback fn() Int = (
// expect-formatted: \t\t() => {
// expect-formatted: \t\t\treturn number
// expect-formatted: \t\t}
// expect-formatted: \t)
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Box[T] {
// expect-formatted: \tvalue T
// expect-formatted: \tcopy T = value
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn unit_default(var calls List[Int]) Void {
// expect-formatted: \tcalls.append(1)
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Explicit {
// expect-formatted: \tcalls List[Int]
// expect-formatted: \tnothing Void = unit_default(calls)
// expect-formatted: \toption Int? = 9
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "record defaults and explicit overrides" {
// expect-formatted: \tdata := Data()
// expect-formatted: \t((data.number != 5 or data.values[0] != 5 or data.callback() != 5) | expect_false?)
// expect-formatted:
// expect-formatted: \tchanged := Data(number: 0)
// expect-formatted: \t(
// expect-formatted: \t\t(
// expect-formatted: \t\t\t(
// expect-formatted: \t\t\t\tchanged.number != 0
// expect-formatted: \t\t\t\tor changed.values[0] != 0
// expect-formatted: \t\t\t\tor changed.callback() != 0
// expect-formatted: \t\t\t)
// expect-formatted: \t\t) | expect_false?
// expect-formatted: \t)
// expect-formatted:
// expect-formatted: \tcalls List[Int] := []
// expect-formatted: \texplicit := Explicit(calls: calls.clone(), nothing: void, option: null)
// expect-formatted: \tcalls.is_empty() | expect_true?
// expect-formatted: \t(explicit.option == null) | expect_true?
// expect-formatted:
// expect-formatted: \tbox := Box(value: "text")
// expect-formatted: \tbox.copy | expect_equal("text")?
// expect-formatted:
// expect-formatted: \tspecified := Box[Int](value: 7, copy: 0)
// expect-formatted: \tspecified.copy | expect_equal(0)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "supplied fields precede defaults in field order" {
// expect-formatted: \tvar log = Counter()
// expect-formatted: \tordered := Ordered(
// expect-formatted: \t\tcounter: Counter(),
// expect-formatted: \t\tthird: mark(counter: log, value: 1),
// expect-formatted: \t\tsecond: mark(counter: log, value: 2),
// expect-formatted: \t)
// expect-formatted: \t(
// expect-formatted: \t\t(
// expect-formatted: \t\t\t(
// expect-formatted: \t\t\t\tlog.value != 12
// expect-formatted: \t\t\t\tor ordered.first != 3
// expect-formatted: \t\t\t\tor ordered.second != 2
// expect-formatted: \t\t\t\tor ordered.third != 1
// expect-formatted: \t\t\t)
// expect-formatted: \t\t) | expect_false?
// expect-formatted: \t)
// expect-formatted:
// expect-formatted: \tagain := Ordered(counter: Counter())
// expect-formatted: \t(again.third != 7) | expect_false?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "mutable defaults have fresh storage" {
// expect-formatted: \tvar first = Data()
// expect-formatted: \tsecond := Data()
// expect-formatted: \tfirst.values.append(8)
// expect-formatted: \t(first.values.length() != 2 or second.values.length() != 1) | expect_false?
// expect-formatted: }
// expect-formatted:
// expect-formatted: interface ReadWithDefault {
// expect-formatted: \tfn get(fallback Int?) Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Reader {
// expect-formatted: \tnumber Int = 5
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn Reader.get(fallback Int?) Int {
// expect-formatted: \treturn fallback or self.number
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Marker { ... }
// expect-formatted:
// expect-formatted: fn no_op() Void { ... }
// expect-formatted:
// expect-formatted: test "ordinary empty declarations and interface omission" {
// expect-formatted: \tno_op()
// expect-formatted:
// expect-formatted: \t_marker := Marker()
// expect-formatted: \tview ReadWithDefault := Reader()
// expect-formatted: \t(view.get() != 5 or view.get(fallback: 7) != 7) | expect_false?
// expect-formatted: }
