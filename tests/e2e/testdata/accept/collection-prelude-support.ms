import expect_equal, expect_false, fail from "@std/test/test.ms"

fn slice(values: List[Int]) List[Int]!: values.slice(0, 1)

fn list_entries[T: Clonable](values: List[T]) List[ListEntry[T]]: values.entries()

fn map_entries[K: Hashable, V: Clonable](values: Map[K, V]) List[MapEntry[K, V]]: values.entries()

fn group[T: Clonable, K: Hashable](values: List[T], key: fn(T) K) Map[K, List[T]]: values.group_by(
	key
)

fn index[T: Equal](values: List[T], value: T) Int?: values.index_of(value)

fn first(values: List[Int]) Int!: values.first().ok_or()

fn unique[T: Hashable & Clonable](values: List[T]) Set[T]: values.to_set()

fn explain(cause: Error) String:
	return cause.message

test "public collection support types retain their standard runtime identities":
	values := [3, 4]
	entries: List[ListEntry[Int]] := list_entries(values)
	entry: ListEntry[Int] := ListEntry(0, 3)
	expect_equal(entries[0], entry)?

	var map = Map[String, Int]()
	map.add("a", 3)

	pairs: List[MapEntry[String, Int]] := map_entries(map)
	pair: MapEntry[String, Int] := MapEntry("a", 3)
	found: MapEntry[String, Int]? := map.find(
		fn(key: String, value: Int) Bool: (value == 3)
	)
	expect_false(pairs[0] != pair or found.get() != pair)?

	selected: List[Int]! := slice(values)
	expect_equal(selected.get(), [3])?

	invalid: List[Int]! := values.slice(0, 9)
	cause: Error := invalid.err()
	expect_equal(cause.kind, "ERANGE")?
	expect_false(explain(cause).is_empty())?

	grouped: Map[Int, List[Int]] := group(values, fn(value: Int) Int: (value % 2))
	distinct: Set[Int] := unique(values)
	expect_false(grouped[1] != [3] or distinct.values() != [3, 4])?
	expect_equal(index(values, 4).get(), 1)?

	absent: Int! := first([])
	missing: Error := absent.err()
	expect_equal(missing.kind, "ENOENT")?
	expect_false(not missing.message.contains("collection-prelude-support.ms:"))?
	expect_equal(first(values).get(), 3)?
