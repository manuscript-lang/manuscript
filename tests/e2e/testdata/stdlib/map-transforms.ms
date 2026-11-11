import expect_equal, expect_false, expect_true from "@std/test/test.ms"

type Counter:
	count: Int

type Key:
	id: Int
	label: String

fn Key.equals(other: Key) Bool:
	return self.id == other.id

fn Key.hash() Int: 0

fn map_values[K: Hashable, V, W](values: Map[K, V], transform: fn(K, V) W) Map[K, W]:
	return values.map[W](transform)

fn map_keys[K: Hashable, V: Clonable, W: Hashable](
	values: Map[K, V],
	transform: fn(K, V) W
) Map[W, V]:
	return values.map_keys[W](transform)

fn reverse_map[K: Hashable, V, A: Clonable](
	values: Map[K, V],
	initial: A,
	step: fn(A, K, V) A
) A:
	return values.fold_right[A](initial.clone(), step)

fn reverse_set[T: Hashable, A: Clonable](values: Set[T], initial: A, step: fn(A, T) A) A:
	return values.fold_right(initial.clone(), step)

test "Map transformations and directional queries are callable":
	source: Map[String, Int] := {"b": 2, "a": 1}
	mapped := source.map(fn k, v: v.to_string())
	mapped["b"] | expect_equal("2")?

	keyed := source.map_keys(fn k, v: v)
	keyed[2] | expect_equal(2)?
	expect_equal(source.find_last(fn k, v: true).get().key, "a")?
	expect_equal(source.fold_right("", fn acc, k, v: acc + k), "ab")?

	values := Set[Int]([2, 1])
	expect_equal(values.find_last(fn v: true).get(), 1)?
	expect_equal(values.fold_right("", fn acc, v: acc + v.to_string()), "12")?

test "Map value transformation copies ordered snapshots and keeps independent values":
	first := Key(2, "b")
	second := Key(1, "a")
	third := Key(3, "c")
	var source = Map[Key, Counter]()
	source.add(first.clone(), Counter(2))
	source.add(second.clone(), Counter(1))
	source.add(third.clone(), Counter(3))

	var seen: List[String] = []

	var mapped = map_values(
		source.clone(),
		fn k,
		v:
			seen.append(k.label + v.count.to_string())
			return v
	)

	seen | expect_equal(["b2", "a1", "c3"])?
	expect_equal(mapped.keys().map(fn k: k.id), [2, 1, 3])?

	var edited = mapped[first].clone()
	edited.count = 7
	(mapped[first].count != 2 or source[first].count != 2) | expect_false?
	mapped.remove(first.clone())
	mapped.add(Key(5, "other"), Counter(5))
	(
		(
			not (source.contains(first))
			or source.contains(Key(5, "different"))
		) | expect_false?
	)

test "Map key transformation retains first equal keys and last values":
	source: Map[Int, Counter] := {
		2: Counter(1),
		1: Counter(2),
		4: Counter(3),
		3: Counter(4)
	}
	var created: List[Key] = []

	var mapped = map_keys(
		source.clone(),
		fn k,
		v:
			key := Key(k % 2, k.to_string())
			created.append(key.clone())
			return key
	)

	(created.length() != 4 or mapped.length() != 2) | expect_false?
	expect_equal(mapped.keys().map(fn k: k.label.clone()), ["2", "1"])?
	expect_equal(mapped.values().map(fn v: v.count), [3, 4])?

	var first_key = mapped.keys().get(0).clone()
	first_key.label = "first copy"
	expect_false((created.get(0).label != "2" or created.get(2).label != "4"))?

	var looked_up = mapped[Key(0, "lookup")].clone()
	looked_up.count = 9
	source[4].count | expect_equal(3)?
	mapped.clear()
	mapped.add(Key(7, "fresh"), Counter(10))
	source.length() | expect_equal(4)?

test "Map key transformation snapshots callbacks and keeps generic nesting":
	source: Map[Int, Counter] := {2: Counter(2), 1: Counter(1), 3: Counter(3)}
	var seen: List[Int] = []
	bound := source.clone().map_keys[String]

	mapped := bound(
		transform: fn k,
		v:
			seen.append(k)
			return k.to_string()
	)

	(seen != [2, 1, 3] or mapped.keys() != ["2", "1", "3"]) | expect_false?
	mapped["3"].count | expect_equal(3)?

	values: Map[String, Int] := {"a": 0}
	map := values.clone().map[Int?]
	expect_true((map(fn k, v: none)["a"].is_none()))?

	nested := values.map(fn k, v: Result[Int, Error].error(Error("nested")))
	nested["a"].err().message | expect_equal("nested")?

test "empty transformations skip callbacks and allocate independent storage":
	var empty_calls: List[Int] = []
	source := Map[String, Int]()

	var mapped = source.map[Counter](
		(
			fn k,
			v:
				empty_calls.append(1)
				return Counter(0)
		)
	)

	mapped.add("new", Counter(1))
	(source.is_empty()) | expect_true?

	var keyed = source.map_keys[Key](
		(
			fn k,
			v:
				empty_calls.append(1)
				return Key(0, "unused")
		)
	)

	keyed.add(Key(1, "new"), 1)
	(source.is_empty()) | expect_true?
	empty_calls.is_empty() | expect_true?

test "Map reverse fold and last match retain ordered snapshots":
	source: Map[String, Counter] := {"b": Counter(2), "a": Counter(1), "c": Counter(3)}
	initial: List[String] := []

	var folded = reverse_map(
		source.clone(),
		initial.clone(),
		fn acc,
		k,
		v:
			var next = acc.clone()
			next.append(k + v.count.to_string())
			return next
	)

	folded | expect_equal(["c3", "a1", "b2"])?
	folded.append("copy")
	initial.length() | expect_equal(0)?

	var seen: List[String] = []
	find := source.clone().find_last
	var found = (
		find(
			predicate: fn k,
			v:
				seen.append(k.clone())
				return k == "a"
		)
		.get()
		.clone()
	)
	(seen != ["c", "a"] or found.key != "a") | expect_false?

	var edited = found.value.clone()
	edited.count = 8
	source["a"].count | expect_equal(1)?
	found.key = "changed"
	source.contains("changed") | expect_false?

test "Set reverse fold and last match preserve snapshots and callbacks":
	b := Key(2, "b")
	a := Key(1, "a")
	c := Key(3, "c")
	source := Set[Key]([b.clone(), a.clone(), c.clone()])
	initial: List[String] := []

	var folded = reverse_set(
		source.clone(),
		initial.clone(),
		fn acc,
		v:
			var next = acc.clone()
			next.append(v.label.clone())
			return next
	)

	folded | expect_equal(["c", "a", "b"])?
	folded.append("copy")
	initial.length() | expect_equal(0)?

	var seen: List[Int] = []
	find := source.clone().find_last
	var found = find(
		fn v:
			seen.append(v.id)
			return v.id == 1
	).get().clone()
	seen | expect_equal([3, 1])?
	found.label = "found"
	a.label | expect_equal("a")?

test "empty and nonmatching reverse queries keep fold and predicate contracts":
	var empty_calls: List[Int] = []
	initial: List[Int] := []
	empty_map := Map[String, Int]()
	empty_set := Set[Int]()
	map_fold := empty_map.fold_right[List[Int]]

	var map_result = map_fold(
		step: (
			fn acc,
			k,
			v:
				empty_calls.append(1)
				return acc.clone()
		),
		initial: initial.clone(),
	)

	map_result.append(1)

	set_fold := empty_set.fold_right[List[Int]]

	var set_result = set_fold(
		initial.clone(),
		(
			fn acc,
			v:
				empty_calls.append(1)
				return acc.clone()
		),
	)

	set_result.append(2)
	map_result | expect_equal([1])?
	set_result | expect_equal([2])?
	initial.is_empty() | expect_true?
	expect_false(
		not (
			empty_map
			.find_last(
				(
					fn k,
					v:
						empty_calls.append(1)
						return false
				)
			)
			.is_none()
		)
	)?
	expect_false(
		not (
			empty_set
			.find_last(
				(
					fn v:
						empty_calls.append(1)
						return false
				)
			)
			.is_none()
		)
	)?

	values: Map[String, Int] := {"b": 2, "a": 1, "c": 3}
	var seen_map: List[String] = []
	expect_false(
		(
			not (
				values
				.find_last(
					fn k,
					v:
						seen_map.append(k.clone())
						return false
				)
				.is_none()
			)
			or seen_map != ["c", "a", "b"]
		)
	)?

	members := Set[Int]([2, 1, 3])
	var seen_set: List[Int] = []
	expect_false(
		(
			not (
				members
				.find_last(
					fn v:
						seen_set.append(v)
						return false
				)
				.is_none()
			)
			or seen_set != [3, 1, 2]
		)
	)?
	empty_calls.is_empty() | expect_true?
