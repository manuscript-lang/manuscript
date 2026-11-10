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

impl Closeable for Marker:
	var fn close() Unit!:
		print("close {self.id}")

fn present(id: Int) Marker?: Marker(id)

fn success(id: Int) Marker!Int: ok(Marker(id))

fn failure(id: Int) Int!Marker: error(Marker(id))

fn optional_cause() Unit:
	_kept := present(1).ok_or(0)

fn optional_callback() Unit:
	_kept := present(2).ok_or_else(fn: 0)

fn result_error_map() Unit:
	_kept := success(3).map_error(fn cause: cause + 1)

fn result_optional() Unit:
	_kept := success(4).to_optional()

fn result_map() Unit:
	_kept := failure(5).map(fn item: item + 1)

fn result_then() Unit:
	_kept := failure(6).and_then(fn item: ok(item + 1))

fn transformed_map() Unit:
	_mapped := success(7).map(fn item: item.id)

fn transformed_error() Unit:
	_mapped := failure(8).map_error(fn item: item.id)

fn transformed_then() Unit:
	_mapped: Int!Int = success(9).and_then(fn item: ok(item.id))

fn bound_map() Unit:
	value := success(10)
	transform: fn(fn(Marker) Int) Int!Int = value.map[Int]
	first := transform(fn item: item.id)
	second := transform(fn item: item.id)
	print("bound map {first.get()} {second.get()}")

	_still_present := value.is_ok()

fn bound_error() Unit:
	value := failure(11)
	transform: fn(fn(Marker) Int) Int!Int = value.map_error[Int]
	first := transform(fn item: item.id)
	second := transform(fn item: item.id)
	print("bound error {first.err()} {second.err()}")

	_still_present := value.is_error()

fn bound_then() Unit:
	value := success(12)
	transform: fn(fn(Marker) Int!Int) Int!Int = value.and_then[Int]
	first := transform(fn item: ok(item.id))
	second := transform(fn item: ok(item.id))
	print("bound then {first.get()} {second.get()}")

	_still_present := value.is_ok()

fn optional_or_else() Unit:
	_kept := present(13).or_else(fn: none)

fn result_or_else() Unit:
	_kept := success(14).or_else(fn cause: error(cause))

fn main() Unit:
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
