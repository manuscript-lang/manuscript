// conform: tags=control-flow,faults,formatter,generics,interfaces,interpolation,lists,match,modules,optional,parser,records,stdlib-testing,strings,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/result-argument-inference.ms
import expect_equal, expect_false, fail from "@std/test/test.ms"

type Failure:
	code: Int

fn erase[T, E](r: Result[T, E]) Result[T, E]: r

fn optional[T: Clonable](r: T!?) T!: r.get().clone()

fn same[T, E](r: T!E) T!E: r

fn both[T, E](cause: E, r: T!E) T!E: r

fn number() Int!Failure: ok(7)

type Events:
	values: List[Int]

fn record(var events: Events, value: Int) Int!:
	events.values.append(value)
	return ok(value)

fn default_value(var events: Events) Int:
	events.values.append(3)
	return 3

fn ordered[T](
	first: T!,
	second: T!,
	var events: Events,
	last: Int = default_value(events)
) T!:
	events.values.append(4)
	return first

test "infer success and error types from Result arguments":
	r: Int! := error(Error("eleven", kind: "EBADMSG"))
	inferred := erase(r)
	explicit := erase[Int, Error](r)
	wrapped := optional(r)
	known := Error("five")
	inferred_from_known := both(known, r)

	for value in [
		inferred.clone(), explicit.clone(), wrapped, inferred_from_known.clone()
	]:
		expect_false(not value.is_error())?
		expect_equal(value.err().message, "eleven")?
		expect_equal(value.err().kind, "EBADMSG")?

	generic: Result[Int, Failure] := error(Failure(31))
	failed := erase(generic)
	expect_false(not failed.is_error())?
	expect_equal(failed.err().code, 31)?

test "nested success preserves its domain and inferred errors remain exact":
	inner: Int!Failure := error(Failure(41))
	outer: Result[Int!Failure, Failure] := ok(inner)
	value := erase(outer).get()
	expect_false(not value.is_error())?
	expect_equal(value.err().code, 41)?

	exact := same(inner)
	expect_false(not exact.is_error())?
	expect_equal(exact.err().code, 41)?

	if seven := erase(number()):
		expect_equal(seven, 7)?
	else:
		return fail("changed success case")

test "inference evaluates once in written order before defaults":
	var events = Events([])
	result := ordered(
		second: record(var events, 2), first: record(var events, 1), var events
	)
	expect_equal(events.values, [2, 1, 3, 4])?

	value := result?
	expect_equal(value, 1)?
