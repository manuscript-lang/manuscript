# conform: tags=generics,interfaces,lists,records,strings,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/wrapped-lends.ms
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
    let row = try relay(result, var visits)
    return ok(row.name)

fn make(n: Int) Row:
    return Row(
        "row-{n}-with-a-heap-allocated-name", ["tag-{n}-with-a-heap-allocated-text"]
    )

test "wrapped parts are references into their arguments":
    var visits: List[Int] = []
    let r = make(1)
    let o: String? = r.name
    let k: Row!Bad = ok(r)
    first_tag(r).get() | try expect_equal("tag-1-with-a-heap-allocated-text")
    named(r).get() | try expect_equal("row-1-with-a-heap-allocated-name")
    o.get() | try expect_equal(r.name)
    k.get().tags.length() | try expect_equal(1)

    let good: Row!Bad = ok(make(2))
    tail(good, var visits).get() | try expect_equal("row-2-with-a-heap-allocated-name")

    let bad: Row!Bad = error(Bad("a failure with a heap allocated reason"))
    tail(bad, var visits).err().why | try expect_equal(
        "a failure with a heap allocated reason"
    )
    tail(ok(make(3)), var visits).get() | try expect_equal(
        "row-3-with-a-heap-allocated-name"
    )
    visits | try expect_equal([1, 1, 1])
