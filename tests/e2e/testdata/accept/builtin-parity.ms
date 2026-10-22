import {expect_equal, expect_false, expect_true, fail} from "@std/testing.ms"
import from_int from "@std/math.ms"
import compile from "@std/string.ms"
import {filled, range_by, map_from_entries} from "@std/collections.ms"
import Bytes from "@std/bytes.ms"
import NumberError from "@std/math.ms"
import StringError from "@std/string.ms"

fn positive(value: Int) Bool:
    return value > 0

fn negative(value: Int) Bool:
    return value < 0

fn stringify(value: Int) String:
    return value.to_string_radix(radix: 10)

fn expand(value: Int) List[String]:
    return [stringify(value: value), "x"]

fn total(accumulator: Int, value: Int) Int:
    return accumulator + value

fn ordered(accumulator: String, value: Int) String:
    return "{accumulator}{value}"

fn compare(left: Int, right: Int) Int:
    if left < right:
        return -1
    if left > right:
        return 1

    return 0

fn common_result[T, E: Error](result: Result[T, E]) Result[T, Error]:
    match result:
        ok(value):
            return ok(value)
        error(cause):
            return error(Error(cause))

fn checked_expansion() Result[Unit, Error]:
    (
        not (
            try common_result(
                result: filled(value: "a", count: 3, max_items: 3)
            ) == ["a", "a", "a"]
        )
    ) | try expect_false
    (
        not (
            try common_result(
                result: range_by(
                    start: 0, end: 6, step: 2, max_items: 3
                )
            ) == [0, 2, 4]
        )
    ) | try expect_false
    (
        not (
            try common_result(
                result: range_by(
                    start: 3, end: -1, step: -1, max_items: 4
                )
            ) == [3, 2, 1, 0]
        )
    ) | try expect_false
    (
        not (
            try common_result(
                result: "x".pad_start(
                    target_length: 4, padding: "é🙂", max_bytes: 9
                )
            ) == "é🙂éx"
        )
    ) | try expect_false
    (
        not (
            try common_result(
                result: "x".pad_end(
                    target_length: 4, padding: "é🙂", max_bytes: 9
                )
            ) == "xé🙂é"
        )
    ) | try expect_false
    (
        not (
            try common_result(
                result: "aba".replace_all(
                    old: "a", new: "é", max_bytes: 5
                )
            ) == "ébé"
        )
    ) | try expect_false
    (
        not (
            try common_result(
                result: "é🙂".replace_all(
                    old: "", new: "-", max_bytes: 9
                )
            ) == "-é-🙂-"
        )
    ) | try expect_false
    (try common_result(result: "é🙂".slice_scalars(start: 0, end: 1))) | try expect_equal(
        expected: "é"
    )
    (try common_result(result: "é".repeat(count: 3, max_bytes: 6))) | try expect_equal(
        expected: "ééé"
    )
    return ok(unit)

test "list methods mutate explicit clones and remain typed":
    let original = [3, 1, 2, 1]
    let alias = original.clone()
    original.get(index: -1) | try expect_equal(expected: 1)
    let absent: Optional[Int] = none
    original.get(index: -9223372036854775808, default: -1) | try expect_equal(
        expected: -1
    )
    original.get(index: 9223372036854775807, default: -1) | try expect_equal(
        expected: -1
    )
    original.first() | try expect_equal(expected: some(3))
    original.last() | try expect_equal(expected: some(1))
    let empty: List[Int] = []
    empty.first() | try expect_equal(expected: absent)
    empty.last() | try expect_equal(expected: absent)
    (empty.is_empty()) | try expect_true
    (not original.is_empty()) | try expect_true
    (original.contains(value: 2)) | try expect_true
    (not original.contains(value: 8)) | try expect_true
    original.index_of(value: 1) | try expect_equal(expected: some(1))
    original.last_index_of(value: 1) | try expect_equal(expected: some(3))
    original.index_of(value: 8) | try expect_equal(expected: absent)
    original.last_index_of(value: 8) | try expect_equal(expected: absent)
    var chain_1 = original.clone()
    chain_1.prepend(value: 0)
    chain_1 | try expect_equal(expected: [0, 3, 1, 2, 1])
    var chain_2 = original.clone()
    chain_2.set(index: -1, value: 9)
    chain_2 | try expect_equal(expected: [3, 1, 2, 9])
    var chain_3 = original.clone()
    chain_3.remove(index: 1)
    chain_3 | try expect_equal(expected: [3, 2, 1])
    original.slice(start: 1, end: 3).get() | try expect_equal(expected: [1, 2])
    var chain_4 = original.clone()
    chain_4.reverse_in_place()
    chain_4 | try expect_equal(expected: [1, 2, 1, 3])
    original.sorted(compare: compare) | try expect_equal(expected: [1, 1, 2, 3])
    [-1, 0, 2, 3].filter(predicate: positive) | try expect_equal(expected: [2, 3])
    [-1, 0, 2, 3].find(predicate: positive) | try expect_equal(expected: some(2))
    [-1, 0, 2, 3].find_last(predicate: positive) | try expect_equal(expected: some(3))
    [-1, 0, 2, 3].find_index(predicate: positive) | try expect_equal(expected: some(2))
    [-1, 0, 2, 3].find_last_index(predicate: positive) | try expect_equal(
        expected: some(3)
    )
    original.find(predicate: negative) | try expect_equal(expected: absent)
    original.find_last(predicate: negative) | try expect_equal(expected: absent)
    original.find_index(predicate: negative) | try expect_equal(expected: absent)
    original.find_last_index(predicate: negative) | try expect_equal(expected: absent)
    (original.some(predicate: positive)) | try expect_true
    (original.every(predicate: positive)) | try expect_true
    (not original.some(predicate: negative)) | try expect_true
    (not original.every(predicate: negative)) | try expect_true
    (not empty.some(predicate: positive)) | try expect_true
    (empty.every(predicate: positive)) | try expect_true
    var observed_original: List[Int] = []
    original.for_each(
        fn(value) Unit:
            observed_original.append(value)
    )
    observed_original | try expect_equal(expected: original)
    original.map(transform: stringify) | try expect_equal(
        expected: ["3", "1", "2", "1"]
    )
    try expect_true(
        (
            original.map[String](transform: stringify).join(
                separator: ","
            ) == "3,1,2,1"
        )
    )
    (
        not (
            original.flat_map(transform: expand) == [
                "3", "x", "1", "x", "2", "x", "1", "x"
            ]
        )
    ) | try expect_false
    original.fold(initial: 0, step: total) | try expect_equal(expected: 7)
    original.fold_right(initial: "", step: ordered) | try expect_equal(expected: "1213")
    let convert = original.map[String]
    convert(transform: stringify) | try expect_equal(expected: ["3", "1", "2", "1"])
    var reversing = original.clone()
    let reverse = reversing.reverse_in_place
    reverse()
    reversing | try expect_equal(expected: [1, 2, 1, 3])
    let reduce = original.fold[Int]
    reduce(initial: 0, step: total) | try expect_equal(expected: 7)
    var chain_5 = original.clone()
    chain_5.splice(start: 1, delete_count: 2, replacement: [8, 9, 10])
    (not (chain_5 == [3, 8, 9, 10, 1])) | try expect_false
    var chain_6 = original.clone()
    chain_6.fill(value: 0, start: 1, end: 3)
    (chain_6 | try expect_equal(expected: [3, 0, 0, 1]))
    var chain_7 = original.clone()
    chain_7.copy_within(target: 1, start: 0, end: 3)
    (chain_7 | try expect_equal(expected: [3, 3, 1, 2]))
    original.keys() | try expect_equal(expected: [0, 1, 2, 3])
    (
        original.entries().get(index: 0) | try expect_equal(
            expected: ListEntry(index: 0, value: 3)
        )
    )
    original.to_set().values() | try expect_equal(expected: [3, 1, 2])
    try expect_equal([[1, 2], [], [3]].flat_map(transform: fn(value): value), [1, 2, 3])
    alias | try expect_equal(expected: [3, 1, 2, 1])

test "map enumeration, merge, and clear preserve insertion order":
    var original = Map[String, Int]()
    original.add(key: "a", value: 1)
    original.add(key: "b", value: 2)
    var other = Map[String, Int]()
    other.add(key: "b", value: 3)
    other.add(key: "c", value: 4)
    var merged = original.clone()
    merged.merge(other: other.clone())
    merged.keys() | try expect_equal(expected: ["a", "b", "c"])
    merged.values() | try expect_equal(expected: [1, 3, 4])
    (
        not (
            merged.entries() == [
                MapEntry(key: "a", value: 1), MapEntry(key: "b", value: 3),
                MapEntry(key: "c", value: 4)
            ]
        )
    ) | try expect_false
    map_from_entries(entries: merged.entries()) | try expect_equal(expected: merged)
    (
        not (
            map_from_entries(
                entries: [
                    MapEntry(key: "a", value: 1), MapEntry(key: "a", value: 2)
                ]
            ).values() == [2]
        )
    ) | try expect_false
    var observed_keys: List[String] = []
    var observed_values: List[Int] = []
    merged.for_each(
        fn(key, value):
            observed_keys.append(key)
            observed_values.append(value)
    )
    observed_keys | try expect_equal(expected: merged.keys())
    observed_values | try expect_equal(expected: merged.values())
    let get_keys = merged.keys
    get_keys() | try expect_equal(expected: ["a", "b", "c"])
    var chain_1 = original.clone()
    chain_1.clear()
    chain_1.length() | try expect_equal(expected: 0)
    original.values() | try expect_equal(expected: [1, 2])
    other.values() | try expect_equal(expected: [3, 4])

test "set algebra and enumeration preserve source values":
    let left = [1, 2, 3].to_set()
    let right = [3, 4].to_set()
    left.union(other: right).values() | try expect_equal(expected: [1, 2, 3, 4])
    left.intersection(other: right).values() | try expect_equal(expected: [3])
    left.difference(other: right).values() | try expect_equal(expected: [1, 2])
    (
        left.symmetric_difference(other: right).values() | try expect_equal(
            expected: [1, 2, 4]
        )
    )
    ([3].to_set().is_subset_of(other: left)) | try expect_true
    (left.is_superset_of(other: [1, 3].to_set())) | try expect_true
    (not left.is_subset_of(other: right)) | try expect_true
    (not right.is_superset_of(other: left)) | try expect_true
    (left.is_disjoint_from(other: [5].to_set())) | try expect_true
    (not left.is_disjoint_from(other: right)) | try expect_true
    let empty = Set[Int]()
    (empty.is_subset_of(other: left)) | try expect_true
    (left.is_superset_of(other: empty)) | try expect_true
    (empty.is_disjoint_from(other: left)) | try expect_true
    left.entries() | try expect_equal(expected: [[1, 1], [2, 2], [3, 3]])
    var observed_left: List[Int] = []
    left.for_each(
        fn(value) Unit:
            observed_left.append(value)
    )
    observed_left | try expect_equal(expected: left.values())
    var chain_8 = left.clone()
    chain_8.clear()
    chain_8 | try expect_equal(expected: empty)
    left.values() | try expect_equal(expected: [1, 2, 3])

test "string methods use Unicode scalars":
    "é🙂é".get(index: -1) | try expect_equal(expected: "é")
    "é🙂é".scalar_at(index: 1) | try expect_equal(expected: 128578)
    let missing: Optional[String] = none
    "".get(index: 0, default: "?") | try expect_equal(expected: "?")
    "é".get(index: -9223372036854775808, default: "?") | try expect_equal(expected: "?")
    "é🙂é".index_of(value: "🙂") | try expect_equal(expected: some(1))
    "é🙂é".last_index_of(value: "é") | try expect_equal(expected: some(2))
    "é🙂é".last_index_of(value: "") | try expect_equal(expected: some(3))
    "é🙂é".index_of(value: "") | try expect_equal(expected: some(0))
    let absent: Optional[Int] = none
    "é🙂é".index_of(value: "z") | try expect_equal(expected: absent)
    "é🙂é".last_index_of(value: "z") | try expect_equal(expected: absent)
    "é🙂é".slice(start: -2, end: 3).get() | try expect_equal(expected: "🙂é")
    ("é🙂é".slice(start: 2, end: 1).is_error()) | try expect_true
    ("é🙂é".slice(start: -99, end: 1).is_error()) | try expect_true
    "é🙂".scalar_length() | try expect_equal(expected: 2)
    "é🙂".scalar_values() | try expect_equal(expected: [233, 128578])
    "\t hello \n".trim() | try expect_equal(expected: "hello")
    "\t hello \n".trim_start() | try expect_equal(expected: "hello \n")
    "\t hello \n".trim_end() | try expect_equal(expected: "\t hello")
    "éAb".upper() | try expect_equal(expected: "ÉAB")
    "ÉAB".lower() | try expect_equal(expected: "éab")
    ("abc".contains(value: "b")) | try expect_true
    ("abc".starts_with(prefix: "ab")) | try expect_true
    ("abc".ends_with(suffix: "bc")) | try expect_true
    "a,b,c".split(separator: ",", max_parts: 2) | try expect_equal(expected: ["a", "b"])
    "aba".replace(old: "a", new: "x", max_replacements: 1) | try expect_equal(
        expected: "xba"
    )
    let strip = " hello ".trim
    strip() | try expect_equal(expected: "hello")

    match checked_expansion():
        ok(_):
            let completed = unit
        error(cause):
            return fail(message: cause.message())

test "bytes have analogous immutable operations":
    let data = Bytes([1, 2, 3, 2])
    data.get(index: -1) | try expect_equal(expected: 2)
    let missing: Optional[Int] = none
    data.get(index: -9223372036854775808, default: -1) | try expect_equal(expected: -1)
    (data.contains(value: Bytes([2, 3]))) | try expect_true
    data.index_of(value: Bytes([2])) | try expect_equal(expected: some(1))
    data.last_index_of(value: Bytes([2])) | try expect_equal(expected: some(3))
    data.index_of(value: Bytes([9])) | try expect_equal(expected: missing)
    (data.starts_with(prefix: Bytes([1, 2]))) | try expect_true
    (data.ends_with(suffix: Bytes([3, 2]))) | try expect_true
    data.slice(start: 1, end: 3).get() | try expect_equal(expected: Bytes([2, 3]))
    data.reversed() | try expect_equal(expected: Bytes([2, 3, 2, 1]))
    data.with_value(index: -1, value: 255) | try expect_equal(
        expected: Bytes([1, 2, 3, 255])
    )
    (Bytes([]).is_empty()) | try expect_true
    (not data.is_empty()) | try expect_true
    data | try expect_equal(expected: Bytes([1, 2, 3, 2]))
    255.to_string_radix(radix: 16) | try expect_equal(expected: "ff")
    1.5.to_string() | try expect_equal(expected: "1.5")
    (1.5.is_finite()) | try expect_true
    (not 1.5.is_nan()) | try expect_true

test "growth limits and invalid inputs return values":
    let too_large: Result[String, StringError] = error(StringError.LimitExceeded)
    let invalid: Result[String, StringError] = error(StringError.InvalidInput)
    "x".pad_start(target_length: 4, padding: "é🙂", max_bytes: 8) | try expect_equal(
        expected: too_large
    )
    (
        not (
            "x".pad_end(
                target_length: 9223372036854775807, padding: "é", max_bytes: 8
            ) == too_large
        )
    ) | try expect_false
    "abc".pad_start(target_length: 1, padding: "", max_bytes: 2) | try expect_equal(
        expected: too_large
    )
    "x".pad_start(target_length: -1, padding: " ", max_bytes: 8) | try expect_equal(
        expected: invalid
    )
    let unchanged: Result[String, StringError] = ok("x")
    "x".pad_end(target_length: 4, padding: "", max_bytes: 1) | try expect_equal(
        expected: unchanged
    )
    "abc".replace_all(old: "", new: "-", max_bytes: 6) | try expect_equal(
        expected: too_large
    )
    let list_limit: Result[List[Int], CollectionError] = error(
        CollectionError.LimitExceeded
    )
    let list_invalid: Result[List[Int], CollectionError] = error(
        CollectionError.InvalidInput
    )
    range_by(start: 0, end: 4, step: 1, max_items: 3) | try expect_equal(
        expected: list_limit
    )
    range_by(start: 0, end: 4, step: 0, max_items: 3) | try expect_equal(
        expected: list_invalid
    )
    filled(value: 1, count: 2, max_items: 1) | try expect_equal(expected: list_limit)

fn parity(value: Int) Int:
    return value % 2

fn default_value(key: String) Int:
    if key != "c": return -1

    return 3

test "grouping and lazy map defaults":
    let grouped = [1, 2, 3, 4].group_by(key: parity)
    grouped.keys() | try expect_equal(expected: [1, 0])
    grouped.values() | try expect_equal(expected: [[1, 3], [2, 4]])
    let group = [1, 2, 3, 4].group_by[Int]
    group(key: parity) | try expect_equal(expected: grouped)
    var original = Map[String, Int]()
    original.add(key: "a", value: 1)
    original.add_default(key: "a", value: 9)
    original | try expect_equal(expected: original)
    var calls: List[Int] = []
    let create = fn(key: String):
        calls.append(1)
        return 0
    original.add_default_from(key: "a", create: create)
    original | try expect_equal(expected: original)
    var chain_9 = original.clone()
    chain_9.add_default(key: "b", value: 2)
    (chain_9.values() | try expect_equal(expected: [1, 2]))
    var chain_10 = original.clone()
    chain_10.add_default_from(key: "c", create: default_value)
    (not (chain_10.values() == [1, 3])) | try expect_false
    original.values() | try expect_equal(expected: [1])
    calls.length() | try expect_equal(expected: 0)

fn verify_text_and_numbers() Result[Unit, Error]:
    (try common_result(result: "é".normalize(form: "NFC", max_bytes: 2))) | try expect_equal(
        expected: "é"
    )
    (try common_result(result: "é".normalize(form: "NFD", max_bytes: 3))) | try expect_equal(
        expected: "é"
    )
    try expect_true(
        (
            try common_result(
                result: "ﬁ".normalize(form: "NFKC", max_bytes: 2)
            ) == "fi"
        )
    )
    try expect_true(
        (
            try common_result(
                result: "ﬁ".normalize(form: "NFKD", max_bytes: 2)
            ) == "fi"
        )
    )
    (try common_result(result: 1.5.to_fixed(digits: 3))) | try expect_equal(
        expected: "1.500"
    )
    (try common_result(result: 1.5.to_exponential(digits: 3))) | try expect_equal(
        expected: "1.500e+0"
    )
    (try common_result(result: 1.5.to_precision(precision: 4))) | try expect_equal(
        expected: "1.500"
    )
    (try common_result(result: 12345.0.to_precision(precision: 3))) | try expect_equal(
        expected: "1.23e+4"
    )
    (
        not (
            try common_result(
                result: 0.000001.to_precision(precision: 2)
            ) == "0.0000010"
        )
    ) | try expect_false
    return ok(unit)

test "normalization, empty separators, and precision formatting":
    match verify_text_and_numbers():
        ok(_):
            let completed = unit
        error(cause):
            return fail(message: cause.message())

    "é🙂".split(separator: "", max_parts: 8) | try expect_equal(expected: ["é", "🙂"])
    let empty_texts: List[String] = []
    "".split(separator: "", max_parts: 8) | try expect_equal(expected: empty_texts)
    "é🙂".replace(old: "", new: "-", max_replacements: 1) | try expect_equal(
        expected: "-é🙂"
    )
    "".replace(old: "", new: "-", max_replacements: 1) | try expect_equal(expected: "-")
    "é".concat(other: "🙂") | try expect_equal(expected: "é🙂")
    let invalid: Result[String, StringError] = error(StringError.InvalidInput)
    let invalid_number: Result[String, NumberError] = error(NumberError.InvalidInput)
    let limit: Result[String, StringError] = error(StringError.LimitExceeded)
    "é".normalize(form: "invalid", max_bytes: 8) | try expect_equal(expected: invalid)
    "é".normalize(form: "NFD", max_bytes: 2) | try expect_equal(expected: limit)
    1.0.to_fixed(digits: 101) | try expect_equal(expected: invalid_number)
    1.0.to_precision(precision: 0) | try expect_equal(expected: invalid_number)

fn verify_bigint_and_regex() Result[Unit, Error]:
    let a = from_int(value: 12)
    let b = from_int(value: 5)
    a.add(other: b).to_string_radix(radix: 10) | try expect_equal(expected: "17")
    a.subtract(other: b).to_string_radix(radix: 10) | try expect_equal(expected: "7")
    a.multiply(other: b).to_string_radix(radix: 10) | try expect_equal(expected: "60")
    (try common_result(result: a.divide(other: b))).to_int() | try expect_equal(
        expected: some(2)
    )
    (try common_result(result: a.remainder(other: b))).to_int() | try expect_equal(
        expected: some(2)
    )
    a.compare(other: b) | try expect_equal(expected: 1)
    a.bit_and(other: b).to_int() | try expect_equal(expected: some(4))
    a.bit_or(other: b).to_int() | try expect_equal(expected: some(13))
    a.bit_xor(other: b).to_int() | try expect_equal(expected: some(9))
    let pattern = try common_result(result: compile(pattern: "[0-9]+"))
    (pattern.matches(text: "a12b3")) | try expect_true
    (
        not (
            try common_result(
                result: pattern.find_all(text: "a12b3", max_matches: 2)
            ) == ["12", "3"]
        )
    ) | try expect_false
    (
        not (
            try common_result(
                result: pattern.replace_all(
                    text: "a12b3", replacement: "x", max_bytes: 4
                )
            ) == "axbx"
        )
    ) | try expect_false
    return ok(unit)

test "BigInt and Regex share function implementations with methods":
    match verify_bigint_and_regex():
        ok(_):
            let completed = unit
        error(cause):
            return fail(message: cause.message())

test "generic native methods accept omitted single-parameter labels":
    let values = [1, 2]
    values.map(stringify) | try expect_equal(expected: ["1", "2"])
    values.map[String](stringify) | try expect_equal(expected: ["1", "2"])
    values.flat_map(expand) | try expect_equal(expected: ["1", "x", "2", "x"])
    values.group_by(parity).keys() | try expect_equal(expected: [1, 0])
    let convert = values.map[String]
    convert(stringify) | try expect_equal(expected: ["1", "2"])
    var observed_values: List[Int] = []
    values.for_each(
        fn(value) Unit:
            observed_values.append(value)
    )
    observed_values | try expect_equal(expected: values)
