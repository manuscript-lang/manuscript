// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Closeable from "@std/core.ms",
	expect_contains, expect_fault from "@std/test/test.ms",
)

type Marker:
	id: Int

fn move Marker.close() Void!: error(Error("scalar wrapper payload closed"))

fn present() Marker?: Marker(1)

fn success() Marker!Int: ok(Marker(2))

fn failure() Int!Marker: error(Marker(3))

fn optional_cause() Void:
	_kept := ok_or(present(), 0)

fn optional_callback() Void:
	_kept := ok_or(present(), 0)

fn result_error_map() Void:
	_kept := success().map_error(fn cause: cause + 1)

fn result_optional() Void:
	_kept := success().to_optional()

fn result_map() Void:
	_kept := failure().map(fn item: item + 1)

fn result_then() Void:
	_kept := failure().and_then(fn item: ok(item + 1))

fn transformed_map() Void:
	_mapped := success().map(fn item: item.id)

fn transformed_error() Void:
	_mapped := failure().map_error(fn item: item.id)

fn transformed_then() Void:
	_mapped: Int!Int := success().and_then(fn item: ok(item.id))

test "scalar retained wrapper branches retain their cleanup duty":
	(expect_fault(optional_cause)?) | expect_contains("resource could not be closed")?
	(
		(expect_fault(optional_callback)?)
		| expect_contains("resource could not be closed")?
	)
	(expect_fault(result_error_map)?) | expect_contains("resource could not be closed")?
	(expect_fault(result_optional)?) | expect_contains("resource could not be closed")?
	(expect_fault(result_map)?) | expect_contains("resource could not be closed")?
	(expect_fault(result_then)?) | expect_contains("resource could not be closed")?

test "direct transforming callbacks close their owned scalar input":
	(expect_fault(transformed_map)?) | expect_contains("resource could not be closed")?
	(
		(expect_fault(transformed_error)?)
		| expect_contains("resource could not be closed")?
	)
	(expect_fault(transformed_then)?) | expect_contains("resource could not be closed")?

fn optional_or_else() Void:
	_kept := present() or null

fn result_or_else() Void:
	_kept := success().or_else(fn cause: error(cause))

test "scalar or_else success branches retain their cleanup duty":
	(expect_fault(optional_or_else)?) | expect_contains("resource could not be closed")?
	(expect_fault(result_or_else)?) | expect_contains("resource could not be closed")?
