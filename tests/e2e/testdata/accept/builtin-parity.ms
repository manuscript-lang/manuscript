import from_int from "@std/bigint.ms"
import compile from "@std/regex.ms"
import panic from "@std/faults.ms"
import {filled, range, map_from_entries} from "@std/collections.ms"
import Bytes from "@std/bytes.ms"
import NumberError from "@std/numbers.ms"
import StringError from "@std/string.ms"

fn positive(value: Int) -> Bool:
    return value > 0

fn negative(value: Int) -> Bool:
    return value < 0

fn stringify(value: Int) -> String:
    return value.to_string(radix: 10)

fn expand(value: Int) -> List[String]:
    return [stringify(value: value), "x"]

fn total(accumulator: Int, value: Int) -> Int:
    return accumulator + value

fn ordered(accumulator: String, value: Int) -> String:
    return "{accumulator}{value}"

fn compare(left: Int, right: Int) -> Int:
    if left < right:
        return -1
    if left > right:
        return 1

    return 0

fn observe(value: Int) -> Unit:
    if not (value > 0):
        return panic(message: "check failed")

fn observe_entry(key: String, value: Int) -> Unit:
    if not (key.byte_length() > 0):
        return panic(message: "check failed")
    if not (value > 0):
        return panic(message: "check failed")

fn common_result[T, E: Error](result: Result[T, E]) -> Result[T, Error]:
    match result:
        ok(value):
            return ok(value)

        error(cause):
            return error(Error(cause))

fn checked_expansion() -> Result[Unit, Error]:
    if not (
        try common_result(
            result: filled(value: "a", count: 3, max_items: 3)
        ) == ["a", "a", "a"]
    ):
        return panic(message: "check failed")
    if not (
        try common_result(
            result: range(start: 0, end: 6, step: 2, max_items: 3)
        ) == [0, 2, 4]
    ):
        return panic(message: "check failed")
    if not (
        try common_result(
            result: range(start: 3, end: -1, step: -1, max_items: 4)
        ) == [3, 2, 1, 0]
    ):
        return panic(message: "check failed")
    if not (
        try common_result(
            result: "x".pad_start(
                target_length: 4,
                padding: "é🙂",
                max_bytes: 9
            )
        ) == "é🙂éx"
    ):
        return panic(message: "check failed")
    if not (
        try common_result(
            result: "x".pad_end(
                target_length: 4,
                padding: "é🙂",
                max_bytes: 9
            )
        ) == "xé🙂é"
    ):
        return panic(message: "check failed")
    if not (
        try common_result(
            result: "aba".replace_all(old: "a", new: "é", max_bytes: 5)
        ) == "ébé"
    ):
        return panic(message: "check failed")
    if not (
        try common_result(
            result: "é🙂".replace_all(old: "", new: "-", max_bytes: 9)
        ) == "-é-🙂-"
    ):
        return panic(message: "check failed")
    if not (try common_result(result: "é🙂".slice_scalars(start: 0, end: 1)) == "é"):
        return panic(message: "check failed")
    if not (try common_result(result: "é".repeat(count: 3, max_bytes: 6)) == "ééé"):
        return panic(message: "check failed")

    return ok(unit)

test "list methods mutate explicit clones and remain typed":
    let original = [3, 1, 2, 1]
    let alias = original
    if not (original.at(index: -1) == some(1)):
        return panic(message: "check failed")

    let absent: Optional[Int] = none
    if not (original.at(index: -9223372036854775808) == absent):
        return panic(message: "check failed")
    if not (original.at(index: 9223372036854775807) == absent):
        return panic(message: "check failed")
    if not (original.first() == some(3)):
        return panic(message: "check failed")
    if not (original.last() == some(1)):
        return panic(message: "check failed")

    let empty: List[Int] = []
    if not (empty.first() == absent):
        return panic(message: "check failed")
    if not (empty.last() == absent):
        return panic(message: "check failed")
    if not (empty.is_empty()):
        return panic(message: "check failed")
    if not (not original.is_empty()):
        return panic(message: "check failed")
    if not (original.contains(value: 2)):
        return panic(message: "check failed")
    if not (not original.contains(value: 8)):
        return panic(message: "check failed")
    if not (original.index_of(value: 1) == some(1)):
        return panic(message: "check failed")
    if not (original.last_index_of(value: 1) == some(3)):
        return panic(message: "check failed")
    if not (original.index_of(value: 8) == absent):
        return panic(message: "check failed")
    if not (original.last_index_of(value: 8) == absent):
        return panic(message: "check failed")
    if not (original.clone().prepend(value: 0) == [0, 3, 1, 2, 1]):
        return panic(message: "check failed")
    if not (original.clone().set(index: -1, value: 9) == [3, 1, 2, 9]):
        return panic(message: "check failed")
    if not (original.clone().remove(index: 1) == [3, 2, 1]):
        return panic(message: "check failed")
    if not (original.slice(start: 1, end: 3).unwrap() == [1, 2]):
        return panic(message: "check failed")
    if not (original.clone().reverse_in_place() == [1, 2, 1, 3]):
        return panic(message: "check failed")
    if not (original.sorted(compare: compare) == [1, 1, 2, 3]):
        return panic(message: "check failed")
    if not ([-1, 0, 2, 3].filter(predicate: positive) == [2, 3]):
        return panic(message: "check failed")
    if not ([-1, 0, 2, 3].find(predicate: positive) == some(2)):
        return panic(message: "check failed")
    if not ([-1, 0, 2, 3].find_last(predicate: positive) == some(3)):
        return panic(message: "check failed")
    if not ([-1, 0, 2, 3].find_index(predicate: positive) == some(2)):
        return panic(message: "check failed")
    if not ([-1, 0, 2, 3].find_last_index(predicate: positive) == some(3)):
        return panic(message: "check failed")
    if not (original.find(predicate: negative) == absent):
        return panic(message: "check failed")
    if not (original.find_last(predicate: negative) == absent):
        return panic(message: "check failed")
    if not (original.find_index(predicate: negative) == absent):
        return panic(message: "check failed")
    if not (original.find_last_index(predicate: negative) == absent):
        return panic(message: "check failed")
    if not (original.some(predicate: positive)):
        return panic(message: "check failed")
    if not (original.every(predicate: positive)):
        return panic(message: "check failed")
    if not (not original.some(predicate: negative)):
        return panic(message: "check failed")
    if not (not original.every(predicate: negative)):
        return panic(message: "check failed")
    if not (not empty.some(predicate: positive)):
        return panic(message: "check failed")
    if not (empty.every(predicate: positive)):
        return panic(message: "check failed")

    original.for_each(operation: observe)
    if not (original.map(transform: stringify) == ["3", "1", "2", "1"]):
        return panic(message: "check failed")
    if not (
        original.map[String](transform: stringify).join(
            separator: ","
        ) == "3,1,2,1"
    ):
        return panic(message: "check failed")
    if not (
        original.flat_map(transform: expand) == [
            "3",
            "x",
            "1",
            "x",
            "2",
            "x",
            "1",
            "x"
        ]
    ):
        return panic(message: "check failed")
    if not (original.fold(initial: 0, step: total) == 7):
        return panic(message: "check failed")
    if not (original.fold_right(initial: "", step: ordered) == "1213"):
        return panic(message: "check failed")

    let convert = original.map[String]
    if not (convert(transform: stringify) == ["3", "1", "2", "1"]):
        return panic(message: "check failed")

    let reverse = original.clone().reverse_in_place
    if not (reverse() == [1, 2, 1, 3]):
        return panic(message: "check failed")

    let reduce = original.fold[Int]
    if not (reduce(initial: 0, step: total) == 7):
        return panic(message: "check failed")
    if not (
        original.clone().splice(
            start: 1,
            delete_count: 2,
            replacement: [8, 9, 10]
        ) == [3, 8, 9, 10, 1]
    ):
        return panic(message: "check failed")
    if not (original.clone().fill(value: 0, start: 1, end: 3) == [3, 0, 0, 1]):
        return panic(message: "check failed")
    if not (original.clone().copy_within(target: 1, start: 0, end: 3) == [3, 3, 1, 2]):
        return panic(message: "check failed")
    if not (original.keys() == [0, 1, 2, 3]):
        return panic(message: "check failed")
    if not (original.entries().at(index: 0) == some(ListEntry(index: 0, value: 3))):
        return panic(message: "check failed")
    if not (original.to_set().values() == [3, 1, 2]):
        return panic(message: "check failed")
    if not ([[1, 2], [], [3]].flat_map(transform: fn(value): value) == [1, 2, 3]):
        return panic(message: "check failed")
    if not (alias == [3, 1, 2, 1]):
        return panic(message: "check failed")

test "map enumeration, merge, and clear preserve insertion order":
    let original = (Map[String, Int]().add(key: "a", value: 1).add(key: "b", value: 2))
    let other = (Map[String, Int]().add(key: "b", value: 3).add(key: "c", value: 4))
    let merged = original.clone().merge(other: other)
    if not (merged.keys() == ["a", "b", "c"]):
        return panic(message: "check failed")
    if not (merged.values() == [1, 3, 4]):
        return panic(message: "check failed")
    if not (
        merged.entries() == [
            MapEntry(key: "a", value: 1),
            MapEntry(key: "b", value: 3),
            MapEntry(key: "c", value: 4)
        ]
    ):
        return panic(message: "check failed")
    if not (map_from_entries(entries: merged.entries()) == merged):
        return panic(message: "check failed")
    if not (
        map_from_entries(
            entries: [
                MapEntry(key: "a", value: 1),
                MapEntry(key: "a", value: 2)
            ]
        ).values() == [2]
    ):
        return panic(message: "check failed")

    merged.for_each(operation: observe_entry)
    let get_keys = merged.keys
    if not (get_keys() == ["a", "b", "c"]):
        return panic(message: "check failed")
    if not (original.clone().clear().length() == 0):
        return panic(message: "check failed")
    if not (original.values() == [1, 2]):
        return panic(message: "check failed")
    if not (other.values() == [3, 4]):
        return panic(message: "check failed")

test "set algebra and enumeration preserve source values":
    let left = [1, 2, 3].to_set()
    let right = [3, 4].to_set()
    if not (left.union(other: right).values() == [1, 2, 3, 4]):
        return panic(message: "check failed")
    if not (left.intersection(other: right).values() == [3]):
        return panic(message: "check failed")
    if not (left.difference(other: right).values() == [1, 2]):
        return panic(message: "check failed")
    if not (left.symmetric_difference(other: right).values() == [1, 2, 4]):
        return panic(message: "check failed")
    if not ([3].to_set().is_subset_of(other: left)):
        return panic(message: "check failed")
    if not (left.is_superset_of(other: [1, 3].to_set())):
        return panic(message: "check failed")
    if not (not left.is_subset_of(other: right)):
        return panic(message: "check failed")
    if not (not right.is_superset_of(other: left)):
        return panic(message: "check failed")
    if not (left.is_disjoint_from(other: [5].to_set())):
        return panic(message: "check failed")
    if not (not left.is_disjoint_from(other: right)):
        return panic(message: "check failed")

    let empty = Set[Int]()
    if not (empty.is_subset_of(other: left)):
        return panic(message: "check failed")
    if not (left.is_superset_of(other: empty)):
        return panic(message: "check failed")
    if not (empty.is_disjoint_from(other: left)):
        return panic(message: "check failed")
    if not (left.entries() == [[1, 1], [2, 2], [3, 3]]):
        return panic(message: "check failed")

    left.for_each(operation: observe)
    if not (left.clone().clear() == empty):
        return panic(message: "check failed")
    if not (left.values() == [1, 2, 3]):
        return panic(message: "check failed")

test "string methods use Unicode scalars":
    if not ("é🙂é".at(index: -1) == some("é")):
        return panic(message: "check failed")
    if not ("é🙂é".scalar_at(index: 1) == some(128578)):
        return panic(message: "check failed")

    let missing: Optional[String] = none
    if not ("".at(index: 0) == missing):
        return panic(message: "check failed")
    if not ("é".at(index: -9223372036854775808) == missing):
        return panic(message: "check failed")
    if not ("é🙂é".index_of(value: "🙂") == some(1)):
        return panic(message: "check failed")
    if not ("é🙂é".last_index_of(value: "é") == some(2)):
        return panic(message: "check failed")
    if not ("é🙂é".last_index_of(value: "") == some(3)):
        return panic(message: "check failed")
    if not ("é🙂é".index_of(value: "") == some(0)):
        return panic(message: "check failed")

    let absent: Optional[Int] = none
    if not ("é🙂é".index_of(value: "z") == absent):
        return panic(message: "check failed")
    if not ("é🙂é".last_index_of(value: "z") == absent):
        return panic(message: "check failed")
    if not ("é🙂é".slice(start: -2, end: 3).unwrap() == "🙂é"):
        return panic(message: "check failed")
    if not ("é🙂é".slice(start: 2, end: 1).is_error()):
        return panic(message: "check failed")
    if not ("é🙂é".slice(start: -99, end: 1).is_error()):
        return panic(message: "check failed")
    if not ("é🙂".scalar_length() == 2):
        return panic(message: "check failed")
    if not ("é🙂".scalar_values() == [233, 128578]):
        return panic(message: "check failed")
    if not ("\t hello \n".trim() == "hello"):
        return panic(message: "check failed")
    if not ("\t hello \n".trim_start() == "hello \n"):
        return panic(message: "check failed")
    if not ("\t hello \n".trim_end() == "\t hello"):
        return panic(message: "check failed")
    if not ("éAb".upper() == "ÉAB"):
        return panic(message: "check failed")
    if not ("ÉAB".lower() == "éab"):
        return panic(message: "check failed")
    if not ("abc".contains(value: "b")):
        return panic(message: "check failed")
    if not ("abc".starts_with(prefix: "ab")):
        return panic(message: "check failed")
    if not ("abc".ends_with(suffix: "bc")):
        return panic(message: "check failed")
    if not ("a,b,c".split(separator: ",", max_parts: 2) == ["a", "b"]):
        return panic(message: "check failed")
    if not ("aba".replace(old: "a", new: "x", max_replacements: 1) == "xba"):
        return panic(message: "check failed")

    let strip = " hello ".trim
    if not (strip() == "hello"):
        return panic(message: "check failed")

    match checked_expansion():
        ok(_):
            let completed = unit

        error(cause):
            return panic(message: cause.message())

test "bytes have analogous immutable operations":
    let data = Bytes([1, 2, 3, 2])
    if not (data.at(index: -1) == some(2)):
        return panic(message: "check failed")

    let missing: Optional[Int] = none
    if not (data.at(index: -9223372036854775808) == missing):
        return panic(message: "check failed")
    if not (data.contains(value: Bytes([2, 3]))):
        return panic(message: "check failed")
    if not (data.index_of(value: Bytes([2])) == some(1)):
        return panic(message: "check failed")
    if not (data.last_index_of(value: Bytes([2])) == some(3)):
        return panic(message: "check failed")
    if not (data.index_of(value: Bytes([9])) == missing):
        return panic(message: "check failed")
    if not (data.starts_with(prefix: Bytes([1, 2]))):
        return panic(message: "check failed")
    if not (data.ends_with(suffix: Bytes([3, 2]))):
        return panic(message: "check failed")
    if not (data.slice(start: 1, end: 3).unwrap() == Bytes([2, 3])):
        return panic(message: "check failed")
    if not (data.reversed() == Bytes([2, 3, 2, 1])):
        return panic(message: "check failed")
    if not (data.with_value(index: -1, value: 255) == Bytes([1, 2, 3, 255])):
        return panic(message: "check failed")
    if not (Bytes([]).is_empty()):
        return panic(message: "check failed")
    if not (not data.is_empty()):
        return panic(message: "check failed")
    if not (data == Bytes([1, 2, 3, 2])):
        return panic(message: "check failed")
    if not (255.to_string(radix: 16) == "ff"):
        return panic(message: "check failed")
    if not (1.5.to_string() == "1.5"):
        return panic(message: "check failed")
    if not (1.5.is_finite()):
        return panic(message: "check failed")
    if not (not 1.5.is_nan()):
        return panic(message: "check failed")

test "growth limits and invalid inputs return values":
    let too_large: Result[String, StringError] = error(StringError.LimitExceeded)
    let invalid: Result[String, StringError] = error(StringError.InvalidInput)
    if not ("x".pad_start(target_length: 4, padding: "é🙂", max_bytes: 8) == too_large):
        return panic(message: "check failed")
    if not (
        "x".pad_end(
            target_length: 9223372036854775807,
            padding: "é",
            max_bytes: 8
        ) == too_large
    ):
        return panic(message: "check failed")
    if not ("abc".pad_start(target_length: 1, padding: "", max_bytes: 2) == too_large):
        return panic(message: "check failed")
    if not ("x".pad_start(target_length: -1, padding: " ", max_bytes: 8) == invalid):
        return panic(message: "check failed")

    let unchanged: Result[String, StringError] = ok("x")
    if not ("x".pad_end(target_length: 4, padding: "", max_bytes: 1) == unchanged):
        return panic(message: "check failed")
    if not ("abc".replace_all(old: "", new: "-", max_bytes: 6) == too_large):
        return panic(message: "check failed")

    let list_limit: Result[List[Int], CollectionError] = error(
        CollectionError.LimitExceeded
    )
    let list_invalid: Result[List[Int], CollectionError] = error(
        CollectionError.InvalidInput
    )
    if not (range(start: 0, end: 4, step: 1, max_items: 3) == list_limit):
        return panic(message: "check failed")
    if not (range(start: 0, end: 4, step: 0, max_items: 3) == list_invalid):
        return panic(message: "check failed")
    if not (filled(value: 1, count: 2, max_items: 1) == list_limit):
        return panic(message: "check failed")

fn parity(value: Int) -> Int:
    return value % 2

fn default_value(key: String) -> Int:
    if not (key == "c"):
        return panic(message: "check failed")

    return 3

fn must_not_run(key: String) -> Int:
    if not (false):
        return panic(message: "check failed")

    return 0

test "grouping and lazy map defaults":
    let grouped = [1, 2, 3, 4].group_by(key: parity)
    if not (grouped.keys() == [1, 0]):
        return panic(message: "check failed")
    if not (grouped.values() == [[1, 3], [2, 4]]):
        return panic(message: "check failed")

    let group = [1, 2, 3, 4].group_by[Int]
    if not (group(key: parity) == grouped):
        return panic(message: "check failed")

    let original = Map[String, Int]().add(key: "a", value: 1)
    if not (original.add_default(key: "a", value: 9) == original):
        return panic(message: "check failed")
    if not (original.add_default_from(key: "a", create: must_not_run) == original):
        return panic(message: "check failed")
    if not (original.clone().add_default(key: "b", value: 2).values() == [1, 2]):
        return panic(message: "check failed")
    if not (
        original.clone().add_default_from(
            key: "c",
            create: default_value
        ).values() == [1, 3]
    ):
        return panic(message: "check failed")
    if not (original.values() == [1]):
        return panic(message: "check failed")

fn verify_text_and_numbers() -> Result[Unit, Error]:
    if not (try common_result(result: "é".normalize(form: "NFC", max_bytes: 2)) == "é"):
        return panic(message: "check failed")
    if not (try common_result(result: "é".normalize(form: "NFD", max_bytes: 3)) == "é"):
        return panic(message: "check failed")
    if not (
        try common_result(
            result: "ﬁ".normalize(form: "NFKC", max_bytes: 2)
        ) == "fi"
    ):
        return panic(message: "check failed")
    if not (
        try common_result(
            result: "ﬁ".normalize(form: "NFKD", max_bytes: 2)
        ) == "fi"
    ):
        return panic(message: "check failed")
    if not (try common_result(result: 1.5.to_fixed(digits: 3)) == "1.500"):
        return panic(message: "check failed")
    if not (try common_result(result: 1.5.to_exponential(digits: 3)) == "1.500e+0"):
        return panic(message: "check failed")
    if not (try common_result(result: 1.5.to_precision(precision: 4)) == "1.500"):
        return panic(message: "check failed")
    if not (try common_result(result: 12345.0.to_precision(precision: 3)) == "1.23e+4"):
        return panic(message: "check failed")
    if not (
        try common_result(
            result: 0.000001.to_precision(precision: 2)
        ) == "0.0000010"
    ):
        return panic(message: "check failed")

    return ok(unit)

test "normalization, empty separators, and precision formatting":
    match verify_text_and_numbers():
        ok(_):
            let completed = unit

        error(cause):
            return panic(message: cause.message())

    if not ("é🙂".split(separator: "", max_parts: 8) == ["é", "🙂"]):
        return panic(message: "check failed")

    let empty_texts: List[String] = []
    if not ("".split(separator: "", max_parts: 8) == empty_texts):
        return panic(message: "check failed")
    if not ("é🙂".replace(old: "", new: "-", max_replacements: 1) == "-é🙂"):
        return panic(message: "check failed")
    if not ("".replace(old: "", new: "-", max_replacements: 1) == "-"):
        return panic(message: "check failed")
    if not ("é".concat(other: "🙂") == "é🙂"):
        return panic(message: "check failed")

    let invalid: Result[String, StringError] = error(StringError.InvalidInput)
    let invalid_number: Result[String, NumberError] = error(NumberError.InvalidInput)
    let limit: Result[String, StringError] = error(StringError.LimitExceeded)
    if not ("é".normalize(form: "invalid", max_bytes: 8) == invalid):
        return panic(message: "check failed")
    if not ("é".normalize(form: "NFD", max_bytes: 2) == limit):
        return panic(message: "check failed")
    if not (1.0.to_fixed(digits: 101) == invalid_number):
        return panic(message: "check failed")
    if not (1.0.to_precision(precision: 0) == invalid_number):
        return panic(message: "check failed")

fn verify_bigint_and_regex() -> Result[Unit, Error]:
    let a = from_int(value: 12)
    let b = from_int(value: 5)
    if not (a.add(other: b).to_string(radix: 10) == "17"):
        return panic(message: "check failed")
    if not (a.subtract(other: b).to_string(radix: 10) == "7"):
        return panic(message: "check failed")
    if not (a.multiply(other: b).to_string(radix: 10) == "60"):
        return panic(message: "check failed")
    if not ((try common_result(result: a.divide(other: b))).to_int() == some(2)):
        return panic(message: "check failed")
    if not ((try common_result(result: a.remainder(other: b))).to_int() == some(2)):
        return panic(message: "check failed")
    if not (a.compare(other: b) == 1):
        return panic(message: "check failed")
    if not (a.bit_and(other: b).to_int() == some(4)):
        return panic(message: "check failed")
    if not (a.bit_or(other: b).to_int() == some(13)):
        return panic(message: "check failed")
    if not (a.bit_xor(other: b).to_int() == some(9)):
        return panic(message: "check failed")

    let pattern = try common_result(result: compile(pattern: "[0-9]+"))
    if not (pattern.matches(text: "a12b3")):
        return panic(message: "check failed")
    if not (
        try common_result(
            result: pattern.find_all(text: "a12b3", max_matches: 2)
        ) == ["12", "3"]
    ):
        return panic(message: "check failed")
    if not (
        try common_result(
            result: pattern.replace_all(
                text: "a12b3",
                replacement: "x",
                max_bytes: 4
            )
        ) == "axbx"
    ):
        return panic(message: "check failed")

    return ok(unit)

test "BigInt and Regex share function implementations with methods":
    match verify_bigint_and_regex():
        ok(_):
            let completed = unit

        error(cause):
            return panic(message: cause.message())

test "generic native methods accept omitted single-parameter labels":
    let values = [1, 2]
    if not (values.map(stringify) == ["1", "2"]):
        return panic("check failed")
    if not (values.map[String](stringify) == ["1", "2"]):
        return panic("check failed")
    if not (values.flat_map(expand) == ["1", "x", "2", "x"]):
        return panic("check failed")
    if not (values.group_by(parity).keys() == [1, 0]):
        return panic("check failed")

    let convert = values.map[String]
    if not (convert(stringify) == ["1", "2"]):
        return panic("check failed")

    values.for_each(observe)
