// expect-stdout: close 1
// expect-stdout: close 2
// expect-stdout: close 3
// expect-stdout: close 4
// expect-stdout: close 5
// expect-stdout: close 6
// expect-stdout: close 7
// expect-stdout: close 8
// expect-stdout: close 9
// expect-stdout: close 13
// expect-stdout: close 14
import Closeable, print from "@std/core.ms"

type Marker:
	id: Int

fn move Marker.close() Void!:
	print(f"close {self.id}")

fn present(id: Int) Marker?: Marker(id)

fn success(id: Int) Marker!Int: ok(Marker(id))

fn failure(id: Int) Int!Marker: error(Marker(id))

fn optional_cause() Void:
	_kept := ok_or(present(1), 0)

fn optional_callback() Void:
	_kept := present(2).ok_or_else(fn: 0)

fn result_error_map() Void:
	_kept := success(3).map_error(fn cause: cause + 1)

fn result_optional() Void:
	_kept := success(4).to_optional()

fn result_map() Void:
	_kept := failure(5).map(fn item: item + 1)

fn result_then() Void:
	_kept := failure(6).and_then(fn item: ok(item + 1))

fn transformed_map() Void:
	_mapped := success(7).map(fn item: item.id)

fn transformed_error() Void:
	_mapped := failure(8).map_error(fn item: item.id)

fn transformed_then() Void:
	_mapped: Int!Int := success(9).and_then(fn item: ok(item.id))

fn optional_or_else() Void:
	_kept := present(13) or null

fn result_or_else() Void:
	_kept := success(14).or_else(fn cause: error(cause))

fn main() Void:
	optional_cause()
	optional_callback()
	result_error_map()
	result_optional()
	result_map()
	result_then()
	transformed_map()
	transformed_error()
	transformed_then()
	optional_or_else()
	result_or_else()
