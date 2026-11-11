import Closeable from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: ok(unit)

impl Marker:
    fn identity() Marker: self

fn marker() Marker!Error: ok(Marker(1))

fn result() Marker!Error:
    value := marker()
    return value.or_else(fn cause: error(cause))

fn optional() Marker?:
    value: Marker? := Marker(2)
    return value.or_else(fn: none)

fn generic[T](value: T?) T?: value.or_else(fn: none)

type Holder:
    label: String

impl Holder:
    fn label_ref() String: self.label

fn source_identity() Int:
    value := Holder("payload")
    borrowed := value.label_ref()
    return borrowed.length() + value.label.length()

fn independent_map() Int:
    value: Marker? := Marker(4)
    mapped := value.map(fn item: Marker(item.id + 1))
    return value.get().id + mapped.get().id
