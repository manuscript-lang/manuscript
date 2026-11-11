type Reading:
    value: Int8?

enum Measurement:
    Value(value: Float32?)

fn direct() Int8?:
    return 100 + 27

fn fractional() Float32?:
    return +(0.1 + 0.2)

fn signed() Int16?:
    return -(60 + 67)

fn unsigned() UInt64?:
    return 9223372036854775807 + 1

fn takes(value: Int8?) Int8?:
    return value

fn bindings_and_assignments() Int8?:
    var value: Int8? = 1 + 2
    value = 4 * 5
    return value

fn argument() Int8?:
    return takes(1 + 2)

fn function_value() Int8?:
    callable: fn(Int8?) Int8? := takes
    return callable(1 + 2)

fn record_single() Reading:
    return Reading(1)

fn record_arithmetic() Reading:
    return Reading(1 + 2)

fn enum_payload() Measurement:
    return Measurement.Value(0.1 + 0.2)

fn field_assignment() Reading:
    var value = Reading()
    value.value = 1 + 2
    return value

fn collection() List[Int8?]:
    return [1 + 2, none, -(60 + 67)]

fn conditional(condition: Bool) Int8?:
    return if condition: 1 + 2 else: none

fn optional_default(value: Int8? = 1 + 2) Int8?:
    return value

fn named_sized(value: Int8) Int8?:
    return value + 1

fn preserved_nested(value: Int8?) Int8??:
    return value

fn preserved_optional(value: Int8?) Int8?:
    return value

fn preserved_plain() Int8:
    return 1 + 2
