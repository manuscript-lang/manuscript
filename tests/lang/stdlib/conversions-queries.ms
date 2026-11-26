// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	panic from "@std/core.ms",
	expect_equal, expect_false, expect_true, fail from "@std/test/test.ms",
)

type Counter {
	calls Int
}

type Pending {
	values List[Int]
}

fn counted(var counter Counter) Counter {
	counter.calls += 1
	return counter.clone()
}

fn require_value[T, E](cause E, value T?) T!E {
	return ok_or(value, cause)
}

fn require_lazy[T, E](create fn() E, move value T?) T!E {
	if value != null { return ok(value) }
	return error(create())
}

fn success_only[T, E](hold value T!E) &T? {
	if item := value { return item }
	return null
}

fn reduce_map[K Hashable, V, A Clonable](
	values Map[K, V],
	initial A,
	step fn(A, K, V) A
) A {
	return values.fold[A](initial.clone(), step)
}

fn reduce_set[T Hashable, A Clonable](values Set[T], initial A, step fn(A, T) A) A {
	return values.fold(initial.clone(), step)
}

fn locate[K Hashable, V Clonable](
	values Map[K, V],
	predicate fn(K, V) Bool
) MapEntry[K, V]? {
	return values.find(predicate)
}

test "conversions and collection queries are callable" {
	present Int? := 2
	missing Int? := null
	ok_or(present, Error("absent")).get() | expect_equal(2)?
	expect_equal(ok_or(missing, Error("absent")).err().message, "absent")?

	failed Int! := error(Error("failed"))
	(failed.to_optional() == null) | expect_true?

	entries Map[String, Int] := {"b": 2, "a": 1}
	expect_equal(entries.fold(0, (acc, k, v) => acc + v), 3)?
	expect_equal(
		(
			entries.find((k, v) => v == 1)
			or panic("called Optional.get() on null")
		).key,
		"a",
	)?
	expect_true((entries.any((k, v) => v == 1)))?
	expect_true((entries.all((k, v) => v > 0)))?

	values := Set[Int]([2, 1])
	expect_equal(values.fold(0, (acc, n) => acc + n), 3)?
	expect_equal(values.find(n => n == 1) or panic("called Optional.get() on null"), 1)?
	expect_true((values.any(n => n == 1)))?
	expect_true((values.all(n => n > 0)))?
}

test "conversions retain unconstrained payloads nesting and lazy counts" {
	var counter = Counter(0)
	present Int? := 0
	missing Int? := null
	(
		(
			require_value(counted(counter), present).get() != 0
			or counter.calls != 1
		) | expect_false?
	)

	var cause = require_value(counter.clone(), missing).err().clone()
	cause.calls = 2
	counter.calls | expect_equal(1)?

	create := fn() Counter => Counter(10)
	(require_lazy(create, present).get() != 0 or counter.calls != 1) | expect_false?

	error_result := require_lazy(create, missing)
	error_result.err().calls | expect_equal(10)?

	var lazy_cause = error_result.err().clone()
	lazy_cause.calls = 4
	error_result.err().calls | expect_equal(10)?

	failure Counter!Pending := error(Pending([1, 2]))
	(success_only(failure) == null) | expect_true?

	success Counter! := ok(counter.clone())
	extract := () => success.clone().to_optional()
	var extracted = (extract() or panic("called Optional.get() on null")).clone()
	extracted.calls = 7
	counter.calls | expect_equal(1)?

	nested_none Int? := null
	nested Int?? := nested_none
	converted := ok_or(nested, Error("absent"))
	converted.is_error() | expect_true?
	(converted.to_optional() == null) | expect_true?

	false_value Bool? := false
	(
		(
			ok_or(false_value, Error("absent")).to_optional()
			or panic("called Optional.get() on null")
		)
		| expect_false?
	)

	unit_value Void? := void
	(ok_or(unit_value, Error("absent")).to_optional() != null) | expect_true?

	nested_inner Int! := error(Error("nested"))
	nested_result Int!? := nested_inner
	(
		(
			ok_or(nested_result.clone(), Error("absent")).to_optional()
			or panic("called Optional.get() on null")
		).err().message | expect_equal("nested")?
	)
}

test "Map fold uses ordered snapshots and returns independent accumulators" {
	var empty_calls List[Int] = []
	values Map[String, Counter] := {"b": Counter(2), "a": Counter(1), "c": Counter(3)}
	initial List[String] := []

	var visits = reduce_map(
		values.clone(),
		initial.clone(),
		(acc, k, v) => {
			var next = acc.clone()
			next.append(k + v.calls.to_string())
			return next
		}
	)

	(visits != ["b2", "a1", "c3"] or not (initial.is_empty())) | expect_false?
	visits.append("copy")
	initial.length() | expect_equal(0)?

	empty := Map[String, Counter]()
	fold := empty.fold[List[String]]

	var untouched = fold(
		step: (
			(acc, k, v) => {
				empty_calls.append(1)
				return acc.clone()
			}
		),
		initial: initial.clone(),
	)

	untouched.append("empty copy")
	initial.length() | expect_equal(0)?
	untouched | expect_equal(["empty copy"])?

	success Int!Counter := ok(2)
	var chain_1 = Map[String, Int]()
	chain_1.add("a", 3)

	nested := chain_1.fold(success.clone(), (acc, k, v) => acc.map(n => (n + v)))
	nested.get() | expect_equal(5)?
	empty_calls.is_empty() | expect_true?
}

test "Map find returns fresh entry shells with copied payloads" {
	var empty_calls List[Int] = []
	counter := Counter(2)
	values Map[String, Counter] := {
		"b": counter.clone(),
		"a": Counter(1),
		"c": Counter(3)
	}
	var visits List[String] = []
	found := (
		locate(
			values.clone(),
			(k, v) => {
				visits.append(k.clone())
				return k == "a"
			}
		)
		or panic("called Optional.get() on null")
	)
	(visits != ["b", "a"] or found.key != "a" or found.value.calls != 1) | expect_false?

	var source = Map[String, Counter]()
	source.add("b", counter.clone())

	find := source.clone().find
	var original = (find((k, v) => true) or panic("called Optional.get() on null")).clone()
	var edited = original.value.clone()
	edited.calls = 5
	counter.calls | expect_equal(2)?
	original.key = "other"
	original.value = Counter(9)
	(not (source.contains("b")) or source["b"].calls != 2) | expect_false?
	expect_equal(
		(
			source.find((k, v) => true)
			or panic("called Optional.get() on null")
		).key,
		"b",
	)?
	expect_true((source.find((k, v) => false) == null))?

	empty := Map[String, Counter]()
	expect_false(
		not (
			empty.find(
				(
					(k, v) => {
						empty_calls.append(1)
						return false
					}
				)
			) == null
		)
	)?
	empty_calls.is_empty() | expect_true?
}

test "Map predicates short circuit over snapshots including empty receivers" {
	var empty_calls List[Int] = []
	var values Map[String, Int] = {"b": 2, "a": 1, "c": 3}
	var seen List[String] = []
	any_of := values.clone().any
	expect_false(
		(
			not (
				any_of(
					(k, v) => {
						seen.append(k.clone())
						values.remove("a")
						values.add("c", 99)
						values.add("new", 4)
						return v == 1
					}
				)
			)
			or seen != ["b", "a"]
		)
	)?
	values.clear()
	values.add("b", 2)
	values.add("a", 1)
	values.add("c", 3)
	seen.splice(0, seen.length(), [])

	every := values.clone().all
	expect_false(
		(
			every(
				predicate: (k, v) => {
					seen.append(k.clone())
					values.remove("a")
					values.add("c", 99)
					values.add("new", 4)
					return v > 1
				}
			)
			or seen != ["b", "a"]
		)
	)?
	values.clear()
	expect_false(
		values.any(
			(
				(k, v) => {
					empty_calls.append(1)
					return false
				}
			)
		)
	)?
	expect_true(
		(
			values.all(
				(
					(k, v) => {
						empty_calls.append(1)
						return true
					}
				)
			)
		)
	)?

	complete Map[String, Int] := {"b": 2, "a": 1, "c": 3}
	expect_false((complete.any((k, v) => false) or not (complete.all((k, v) => true))))?
	empty_calls.is_empty() | expect_true?
}

type Key {
	id Int
	label String
}

fn Key.equals(other Key) Bool {
	return self.id == other.id
}

fn Key.hash() Int => 0

test "Set fold and find preserve ordered snapshots and copied payloads" {
	var empty_calls List[Int] = []
	a := Key(1, "a")
	b := Key(2, "b")
	c := Key(3, "c")
	var values = Set[Key]([b.clone(), a.clone(), c.clone()])
	initial List[String] := []

	var visits = reduce_set(
		values.clone(),
		initial.clone(),
		(acc, v) => {
			var next = acc.clone()
			next.append(v.label.clone())
			return next
		}
	)

	visits | expect_equal(["b", "a", "c"])?
	visits.append("copy")
	initial.length() | expect_equal(0)?

	bound_empty := Set[Key]().fold[List[String]]

	var empty_result = bound_empty(
		initial.clone(),
		(
			(acc, v) => {
				empty_calls.append(1)
				return acc.clone()
			}
		),
	)

	empty_result.append("empty copy")
	initial.length() | expect_equal(0)?
	values.clear()
	values.add(b.clone())
	values.add(a.clone())
	values.add(c.clone())

	var seen List[Int] = []
	find := values.clone().find
	var found = (
		find(
			v => {
				seen.append(v.id)
				return v.id == 1
			}
		)
		or panic("called Optional.get() on null")
	).clone()
	seen | expect_equal([2, 1])?
	found.label = "found"
	a.label | expect_equal("a")?
	values.clear()
	expect_false(
		not (
			values.find(
				(
					v => {
						empty_calls.append(1)
						return false
					}
				)
			) == null
		)
	)?

	flags := Set[Bool]([false])
	expect_false(flags.find(v => true) or panic("called Optional.get() on null"))?
	empty_calls.is_empty() | expect_true?
}

test "Set predicates short circuit over snapshots and keep empty identities" {
	var empty_calls List[Int] = []
	var values = Set[Int]([2, 1, 3])
	var seen List[Int] = []
	any_of := values.clone().any
	expect_false(
		(
			not (
				any_of(
					v => {
						seen.append(v)
						values.remove(1)
						values.add(4)
						return v == 1
					}
				)
			)
			or seen != [2, 1]
		)
	)?
	values.clear()
	values.add(2)
	values.add(1)
	values.add(3)
	seen.splice(0, seen.length(), [])

	every := values.clone().all
	expect_false(
		(
			every(
				v => {
					seen.append(v)
					values.remove(1)
					values.add(4)
					return v > 1
				}
			)
			or seen != [2, 1]
		)
	)?
	values.clear()
	expect_false(
		values.any(
			(
				v => {
					empty_calls.append(1)
					return false
				}
			)
		)
	)?
	expect_true(
		(
			values.all(
				(
					v => {
						empty_calls.append(1)
						return true
					}
				)
			)
		)
	)?

	complete := Set[Int]([2, 1])
	expect_false(complete.any(v => false) or not (complete.all(v => true)))?
	expect_true((complete.find(v => false) == null))?
	empty_calls.is_empty() | expect_true?
}

test "nonmatching queries and all-true predicates visit the complete snapshot" {
	map Map[String, Int] := {"b": 2, "a": 1, "c": 3}
	var map_visits List[String] = []
	expect_false(
		(
			map.any(
				(k, v) => {
					map_visits.append(k.clone())
					return false
				}
			)
			or map_visits != ["b", "a", "c"]
		)
	)?
	map_visits.splice(0, map_visits.length(), [])
	expect_false(
		(
			not (
				map.all(
					(k, v) => {
						map_visits.append(k.clone())
						return true
					}
				)
			)
			or map_visits != ["b", "a", "c"]
		)
	)?
	map_visits.splice(0, map_visits.length(), [])
	expect_false(
		(
			not (
				map.find(
					(k, v) => {
						map_visits.append(k.clone())
						return false
					}
				) == null
			)
			or map_visits != ["b", "a", "c"]
		)
	)?

	set := Set[Int]([2, 1, 3])
	var set_visits List[Int] = []
	expect_false(
		(
			set.any(
				v => {
					set_visits.append(v)
					return false
				}
			)
			or set_visits != [2, 1, 3]
		)
	)?
	set_visits.splice(0, set_visits.length(), [])
	expect_false(
		(
			not (
				set.all(
					v => {
						set_visits.append(v)
						return true
					}
				)
			)
			or set_visits != [2, 1, 3]
		)
	)?
	set_visits.splice(0, set_visits.length(), [])
	expect_false(
		(
			not (
				set.find(
					v => {
						set_visits.append(v)
						return false
					}
				) == null
			)
			or set_visits != [2, 1, 3]
		)
	)?
}

fn find_port(port Int?) Int! {
	value := ok_or(port.clone(), Error("missing"))?
	return ok(value)
}

test "ok_or reports its explicit cause" {
	absent Int? := null
	direct Int! := ok_or(absent, Error("missing"))
	direct.err().message | expect_equal("missing")?
	find_port(null).err().message | expect_equal("missing")?
	find_port(8080).get() | expect_equal(8080)?

	named Int! := ok_or(absent, Error("port"))
	named.err().message | expect_equal("port")?
}
// expect-exit: 0
// expect-tests: passed=9 failed=0
