import expect_equal from "@std/test/test.ms"

type Row:
	name: String
	tags: List[String]

type Bad:
	why: String

fn first_tag(r: Row) String?:
	return r.tags[0]

fn named(r: Row) String!Bad:
	return ok(r.name)

fn relay(result: Row!Bad, var visits: List[Int]) Row!Bad:
	visits.append(1)
	return result

fn tail(result: Row!Bad, var visits: List[Int]) String!Bad:
	row := relay(result, var visits)?
	return ok(row.name)

fn make(n: Int) Row:
	return Row(
		"row-{n}-with-a-heap-allocated-name",
		["tag-{n}-with-a-heap-allocated-text"],
	)

test "wrapped parts are references into their arguments":
	var visits: List[Int] = []
	r := make(1)
	o: String? := r.name
	k: Row!Bad := ok(r)
	first_tag(r).get() | expect_equal("tag-1-with-a-heap-allocated-text")?
	named(r).get() | expect_equal("row-1-with-a-heap-allocated-name")?
	o.get() | expect_equal(r.name)?
	k.get().tags.length() | expect_equal(1)?

	good: Row!Bad := ok(make(2))
	tail(good, var visits).get() | expect_equal("row-2-with-a-heap-allocated-name")?

	bad: Row!Bad := error(Bad("a failure with a heap allocated reason"))
	(
		tail(bad, var visits).err().why | expect_equal(
			"a failure with a heap allocated reason"
		)?
	)
	(
		tail(ok(make(3)), var visits).get() | expect_equal(
			"row-3-with-a-heap-allocated-name"
		)?
	)
	visits | expect_equal([1, 1, 1])?
