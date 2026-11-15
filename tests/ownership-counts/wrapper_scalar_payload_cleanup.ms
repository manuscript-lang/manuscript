// expect-stdout: close 1
// expect-stdout: close 2
// expect-stdout: close 3
// expect-stdout: close 4
// expect-stdout: close 5
// expect-stdout: close 6
// expect-stdout: close 7
// expect-stdout: close 8
// expect-stdout: close 9
// expect-stdout: bound map 10 10
// expect-stdout: close 10
// expect-stdout: bound error 11 11
// expect-stdout: close 11
// expect-stdout: bound then 12 12
// expect-stdout: close 12
// expect-stdout: close 13
// expect-stdout: close 14
import Closeable, print from "@std/core.ms"

type Marker:
	id: Int

fn var Marker.close() Void!:
	print(f"close {self.id}")

fn present(id: Int) Marker?: Marker(id)

fn success(id: Int) Marker!Int: ok(Marker(id))

fn failure(id: Int) Int!Marker: error(Marker(id))

fn optional_cause() Void:
	_kept := present(1).ok_or(0)

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

fn bound_map() Void:
	value := success(10)
	transform: fn(fn(Marker) Int) Int!Int := value.map[Int]
	first := transform(fn item: item.id)
	second := transform(fn item: item.id)
	print(f"bound map {first.get()} {second.get()}")

	_still_present := value.is_ok()

fn bound_error() Void:
	value := failure(11)
	transform: fn(fn(Marker) Int) Int!Int := value.map_error[Int]
	first := transform(fn item: item.id)
	second := transform(fn item: item.id)
	print(f"bound error {first.err()} {second.err()}")

	_still_present := value.is_error()

fn bound_then() Void:
	value := success(12)
	transform: fn(fn(Marker) Int!Int) Int!Int := value.and_then[Int]
	first := transform(fn item: ok(item.id))
	second := transform(fn item: ok(item.id))
	print(f"bound then {first.get()} {second.get()}")

	_still_present := value.is_ok()

fn optional_or_else() Void:
	_kept := present(13).or_else(fn: none)

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
	bound_map()
	bound_error()
	bound_then()
	optional_or_else()
	result_or_else()
