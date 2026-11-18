import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Void!: ok()

fn transfer_ok_or() Void:
    value: Marker? := Marker(1)
    _kept := value.ok_or("failure")

fn transfer_ok_or_else() Void:
    value: Marker? := Marker(1)
    _kept := value.ok_or_else(fn: "failure")

fn transfer_map_error() Void:
    value: Marker!Int := ok(Marker(1))
    _kept := value.map_error(fn cause: cause + 1)

fn transfer_to_optional() Void:
    value: Marker!Int := ok(Marker(1))
    _kept := value.to_optional()

fn transfer_map() Void:
    value: Int!Marker := error(Marker(1))
    _kept := value.map(fn item: item + 1)

fn transfer_and_then() Void:
    value: Int!Marker := error(Marker(1))
    _kept := value.and_then(fn item: ok(item + 1))

fn generic_optional[T](value: T?) T!String: value.ok_or("failure")

fn generic_result[T](value: T!Int) T?: value.to_optional()

fn generic_error[E](value: Int!E) Int!E: value.map(fn item: item + 1)

fn collection_get_still_borrows() Int:
    values := [Marker(1)]
    return values.first().get().id

fn direct_specialized_optional[T, E](create: fn() E, value: T?) T!E:
    return value.ok_or_else[E](create)

fn direct_specialized_result[T, E, U](value: T!E, transform: fn(T) U) U!E:
    return value.map[U](transform)

type Box:
    items: List[Int]

fn Box.read[T](_tag: T) List[Int]: self.items

fn var Box.change[T](_tag: T) Int:
    self.items.append(3)
    return self.items.length()

fn specialized_source_and_indexed_call() Int:
    var box = Box([1, 2])
    count := box.read[Int](0).length()
    changed := box.change[Int](0)
    callbacks := [fn(value: Int) Int: value + 1]
    return count + changed + callbacks[0](4)
