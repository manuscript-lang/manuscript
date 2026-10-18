import Bytes from "@std/bytes.ms"
import panic from "@std/faults.ms"

test "Bytes split is binary safe":
    let data = Bytes([255, 0, 1, 0, 254])
    if data.split(Bytes([0])) != [Bytes([255]), Bytes([1]), Bytes([254])]:
        return panic("byte split")

test "Bytes split handles exact and nonoverlapping separators":
    let empty = Bytes([])
    if Bytes([0, 7, 0]).split(Bytes([0])) != [empty, Bytes([7]), empty]: return panic(
        "edge empty byte parts"
    )
    if Bytes([0, 0]).split(Bytes([0])) != [empty, empty, empty]: return panic(
        "adjacent byte separators"
    )
    if Bytes([255, 0, 9, 255, 0]).split(Bytes([255, 0])) != [empty, Bytes([9]), empty]: return panic(
        "multibyte separator"
    )
    if Bytes([1, 1, 1]).split(Bytes([1, 1])) != [empty, Bytes([1])]: return panic(
        "overlapping separator"
    )
    if Bytes([1]).split(Bytes([1, 2])) != [Bytes([1])]: return panic("long separator")
    if empty.split(Bytes([0])) != [empty]: return panic("empty data nonempty separator")

test "Bytes empty separator splits bytes without decoding":
    let empty = Bytes([])
    if not (empty.split(empty).is_empty()): return panic("empty binary explosion")
    if Bytes([0, 255, 128]).split(empty) != [Bytes([0]), Bytes([255]), Bytes([128])]: return panic(
        "binary explosion"
    )

    let scalars = "é".to_bytes().split(empty)
    if scalars != [Bytes([195]), Bytes([169])]: return panic(
        "byte split used scalar indexes"
    )
    if scalars.at(0).unwrap().to_string().is_some(): return panic(
        "byte split repaired invalid UTF-8"
    )
    if "é".to_bytes().split(Bytes([169])) != [Bytes([195]), empty]: return panic(
        "separator decoded as text"
    )

test "Bytes split optional limits truncate parts":
    let data = Bytes([1, 0, 2, 0, 3, 0])
    let separator = Bytes([0])
    let expected = [Bytes([1]), Bytes([2]), Bytes([3]), Bytes([])]
    if data.split(separator) != expected or data.split(separator, none) != expected: return panic(
        "omitted/none split cap"
    )
    if data.split(separator: separator, max_parts: some(2)) != [Bytes([1]), Bytes([2])]: return panic(
        "some split cap"
    )
    if data.split(separator, max_parts: 1) != [Bytes([1])]: return panic(
        "split retained unsplit remainder"
    )
    if (
        not (data.split(separator, 0).is_empty())
        or not (Bytes([]).split(separator, 0).is_empty())
    ): return panic("zero split cap")
    if data.split(separator, 9999999) != expected: return panic("large split cap")
    if data.split(Bytes([]), 2) != [Bytes([1]), Bytes([0])]: return panic(
        "empty separator cap"
    )

fn split_then[T](data: Bytes, separator: Bytes, transform: fn(value: List[Bytes]) T) T:
    return data.split(separator) | transform

fn call_split(
    operation: fn(separator: Bytes, max_parts: Optional[Int]) List[Bytes]
) List[Bytes]:
    return operation(Bytes([0]), some(2))

test "Bytes split bound methods and generic forwarding retain contracts":
    var data = Bytes([1, 0, 2])
    let split = data.split
    let typed: fn(separator: Bytes, max_parts: Optional[Int]) List[Bytes] = data.split
    data = Bytes([9])
    if split(Bytes([0])) != [Bytes([1]), Bytes([2])]: return panic(
        "bound byte receiver"
    )
    if split(max_parts: 1, separator: Bytes([0])) != [Bytes([1])]: return panic(
        "bound byte labels/defaults"
    )
    if call_split(typed) != [Bytes([1]), Bytes([2])]: return panic(
        "typed split callback"
    )
    if (
        split_then[Bool](
            Bytes([1, 0, 2]),
            Bytes([0]),
            fn(value): value.length() == 2
        ) != true
    ): return panic("generic split result")

test "Bytes split returns independent List storage and immutable views":
    let data = Bytes([1, 0, 2])
    let first = data.split(Bytes([0]))
    let second = data.split(Bytes([0]))
    let payload = first.at(0).unwrap()
    let edited = payload.with_value(0, 99)
    let extracted = payload.values()
    extracted.set(0, 88)
    first.set(0, Bytes([77])).append(Bytes([66]))
    if (edited != Bytes([99]) or payload != Bytes([1]) or data != Bytes([1, 0, 2])): return panic(
        "split payload mutation"
    )
    if second != [Bytes([1]), Bytes([2])]: return panic("split outer storage alias")

    let empty = Bytes([])
    let zero_parts = data.split(Bytes([0]), 0)
    zero_parts.append(empty)
    if not (data.split(Bytes([0]), 0).is_empty()): return panic(
        "zero split storage alias"
    )

    let no_parts = empty.split(empty)
    no_parts.append(Bytes([1]))
    if not (empty.split(empty).is_empty()): return panic("empty split storage alias")
