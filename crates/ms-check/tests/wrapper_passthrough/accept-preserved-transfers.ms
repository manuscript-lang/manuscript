import Closeable from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: ok(unit)

fn transfer_ok_or() Unit:
    let value: Marker? = Marker(1)
    let _kept = value.ok_or("failure")

fn transfer_ok_or_else() Unit:
    let value: Marker? = Marker(1)
    let _kept = value.ok_or_else(fn: "failure")

fn transfer_map_error() Unit:
    let value: Marker!Int = ok(Marker(1))
    let _kept = value.map_error(fn cause: cause + 1)

fn transfer_to_optional() Unit:
    let value: Marker!Int = ok(Marker(1))
    let _kept = value.to_optional()

fn transfer_map() Unit:
    let value: Int!Marker = error(Marker(1))
    let _kept = value.map(fn item: item + 1)

fn transfer_and_then() Unit:
    let value: Int!Marker = error(Marker(1))
    let _kept = value.and_then(fn item: ok(item + 1))

fn generic_optional[T](value: T?) T!String: value.ok_or("failure")

fn generic_result[T](value: T!Int) T?: value.to_optional()

fn generic_error[E](value: Int!E) Int!E: value.map(fn item: item + 1)

fn independent_map() Int:
    let value: Marker!Int = ok(Marker(1))
    let mapped = value.map(fn item: Marker(item.id + 1))
    return value.get().id + mapped.get().id

fn independent_error_map() Int:
    let value: Int!Marker = error(Marker(1))
    let mapped = value.map_error(fn item: Marker(item.id + 1))
    return if value.is_error() and mapped.is_error(): 1 else: 0

fn independent_and_then() Int:
    let value: Marker!Int = ok(Marker(1))
    let mapped: Marker!Int = value.and_then(fn item: ok(Marker(item.id + 1)))
    return value.get().id + mapped.get().id

fn bound_generic[T: Clonable](value: T!Int) T?:
    let convert = value.to_optional
    return convert()

fn bound_generic_error[E: Clonable](value: Int!E) Int!E:
    let transform = value.map[Int]
    return transform(fn item: item + 1)

fn bound_transformed_resource() Int:
    let value: Marker!Int = ok(Marker(1))
    let transform = value.map[Marker]
    let first = transform(fn item: Marker(item.id + 1))
    let second = transform(fn item: Marker(item.id + 2))
    return value.get().id + first.get().id + second.get().id

fn bound_transformed_error_resource() Bool:
    let value: Int!Marker = error(Marker(1))
    let transform = value.map_error[Marker]
    let first = transform(fn item: Marker(item.id + 1))
    let second = transform(fn item: Marker(item.id + 2))
    return value.is_error() and first.is_error() and second.is_error()

fn collection_get_still_borrows() Int:
    let values = [Marker(1)]
    return values.first().get().id

fn direct_specialized_optional[T, E](value: T?, create: fn() E) T!E:
    return value.ok_or_else[E](create)

fn direct_specialized_result[T, E, U](value: T!E, transform: fn(T) U) U!E:
    return value.map[U](transform)

type Box:
    items: List[Int]

impl Box:
    fn read[T](_tag: T) List[Int]: self.items

    var fn change[T](_tag: T) Int:
        self.items.append(3)
        return self.items.length()

fn specialized_source_and_indexed_call() Int:
    var box = Box([1, 2])
    let count = box.read[Int](0).length()
    let changed = box.change[Int](0)
    let callbacks = [fn(value: Int) Int: value + 1]
    return count + changed + callbacks[0](4)
