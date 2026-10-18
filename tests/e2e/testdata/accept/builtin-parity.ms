import from_int from "@std/bigint.ms"
import compile from "@std/regex.ms"
import panic from "@std/faults.ms"
import {filled, range_by, map_from_entries} from "@std/collections.ms"
import Bytes from "@std/bytes.ms"
import NumberError from "@std/numbers.ms"
import StringError from "@std/string.ms"

fn positive(value: Int) Bool:
    return value > 0

fn negative(value: Int) Bool:
    return value < 0

fn stringify(value: Int) String:
    return value.to_string_radix(10)

fn expand(value: Int) List[String]:
    return [stringify(value), "x"]

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

fn observe(value: Int) Unit:
    if not (value > 0):
        return panic("check failed")

fn observe_entry(key: String, value: Int) Unit:
    if not (key.byte_length() > 0):
        return panic("check failed")
    if not (value > 0):
        return panic("check failed")

fn common_result[T, E: Error](result: Result[T, E]) Result[T, Error]:
    return ok(try result)

fn checked_expansion() Result[Unit, Error]:
    if not ((filled("a", 3, 3) | try common_result) == ["a", "a", "a"]):
        return panic("check failed")
    if not ((range_by(0, 6, 2, 3) | try common_result) == [0, 2, 4]):
        return panic("check failed")
    if not ((range_by(3, -1, -1, 4) | try common_result) == [3, 2, 1, 0]):
        return panic("check failed")
    if not (("x".pad_start(4, "é🙂", 9) | try common_result) == "é🙂éx"):
        return panic("check failed")
    if not (("x".pad_end(4, "é🙂", 9) | try common_result) == "xé🙂é"):
        return panic("check failed")
    if not (("aba".replace_all("a", "é", 5) | try common_result) == "ébé"):
        return panic("check failed")
    if not (("é🙂".replace_all("", "-", 9) | try common_result) == "-é-🙂-"):
        return panic("check failed")
    if not (("é🙂".slice_scalars(0, 1) | try common_result) == "é"):
        return panic("check failed")
    if not (("é".repeat(3, 6) | try common_result) == "ééé"):
        return panic("check failed")

    return ok(unit)

test "list methods mutate explicit clones and remain typed":
    let original = [3, 1, 2, 1]
    let alias = original
    if not (original.at(-1) == some(1)):
        return panic("check failed")

    let absent: Optional[Int] = none
    if not (original.at(-9223372036854775808) == absent):
        return panic("check failed")
    if not (original.at(9223372036854775807) == absent):
        return panic("check failed")
    if not (original.first() == some(3)):
        return panic("check failed")
    if not (original.last() == some(1)):
        return panic("check failed")

    let empty: List[Int] = []
    if not (empty.first() == absent):
        return panic("check failed")
    if not (empty.last() == absent):
        return panic("check failed")
    if not (empty.is_empty()):
        return panic("check failed")
    if not (not original.is_empty()):
        return panic("check failed")
    if not (original.contains(2)):
        return panic("check failed")
    if not (not original.contains(8)):
        return panic("check failed")
    if not (original.index_of(1) == some(1)):
        return panic("check failed")
    if not (original.last_index_of(1) == some(3)):
        return panic("check failed")
    if not (original.index_of(8) == absent):
        return panic("check failed")
    if not (original.last_index_of(8) == absent):
        return panic("check failed")
    if not (original.clone().prepend(0) == [0, 3, 1, 2, 1]):
        return panic("check failed")
    if not (original.clone().set(-1, 9) == [3, 1, 2, 9]):
        return panic("check failed")
    if not (original.clone().remove(1) == [3, 2, 1]):
        return panic("check failed")
    if not (original.slice(1, 3).unwrap() == [1, 2]):
        return panic("check failed")
    if not (original.clone().reverse_in_place() == [1, 2, 1, 3]):
        return panic("check failed")
    if not (original.sorted(compare) == [1, 1, 2, 3]):
        return panic("check failed")
    if not ([-1, 0, 2, 3].filter(positive) == [2, 3]):
        return panic("check failed")
    if not ([-1, 0, 2, 3].find(positive) == some(2)):
        return panic("check failed")
    if not ([-1, 0, 2, 3].find_last(positive) == some(3)):
        return panic("check failed")
    if not ([-1, 0, 2, 3].find_index(positive) == some(2)):
        return panic("check failed")
    if not ([-1, 0, 2, 3].find_last_index(positive) == some(3)):
        return panic("check failed")
    if not (original.find(negative) == absent):
        return panic("check failed")
    if not (original.find_last(negative) == absent):
        return panic("check failed")
    if not (original.find_index(negative) == absent):
        return panic("check failed")
    if not (original.find_last_index(negative) == absent):
        return panic("check failed")
    if not (original.some(positive)):
        return panic("check failed")
    if not (original.every(positive)):
        return panic("check failed")
    if not (not original.some(negative)):
        return panic("check failed")
    if not (not original.every(negative)):
        return panic("check failed")
    if not (not empty.some(positive)):
        return panic("check failed")
    if not (empty.every(positive)):
        return panic("check failed")

    original.for_each(observe)
    if not (original.map(stringify) == ["3", "1", "2", "1"]):
        return panic("check failed")
    if not (original.map[String](stringify).join(",") == "3,1,2,1"):
        return panic("check failed")
    if not (original.flat_map(expand) == ["3", "x", "1", "x", "2", "x", "1", "x"]):
        return panic("check failed")
    if not (original.fold(0, total) == 7):
        return panic("check failed")
    if not (original.fold_right("", ordered) == "1213"):
        return panic("check failed")

    let convert = original.map[String]
    if not (convert(stringify) == ["3", "1", "2", "1"]):
        return panic("check failed")

    let reverse = original.clone().reverse_in_place
    if not (reverse() == [1, 2, 1, 3]):
        return panic("check failed")

    let reduce = original.fold[Int]
    if not (reduce(0, total) == 7):
        return panic("check failed")
    if not (original.clone().splice(1, 2, [8, 9, 10]) == [3, 8, 9, 10, 1]):
        return panic("check failed")
    if not (original.clone().fill(0, 1, 3) == [3, 0, 0, 1]):
        return panic("check failed")
    if not (original.clone().copy_within(1, 0, 3) == [3, 3, 1, 2]):
        return panic("check failed")
    if not (original.keys() == [0, 1, 2, 3]):
        return panic("check failed")
    if not (original.entries().at(0) == some(ListEntry(0, 3))):
        return panic("check failed")
    if not (original.to_set().values() == [3, 1, 2]):
        return panic("check failed")
    if not ([[1, 2], [], [3]].flat_map(fn(value): value) == [1, 2, 3]):
        return panic("check failed")
    if not (alias == [3, 1, 2, 1]):
        return panic("check failed")

test "map enumeration, merge, and clear preserve insertion order":
    let original = (Map[String, Int]().add("a", 1).add("b", 2))
    let other = (Map[String, Int]().add("b", 3).add("c", 4))
    let merged = original.clone().merge(other)
    if not (merged.keys() == ["a", "b", "c"]):
        return panic("check failed")
    if not (merged.values() == [1, 3, 4]):
        return panic("check failed")
    if not (merged.entries() == [MapEntry("a", 1), MapEntry("b", 3), MapEntry("c", 4)]):
        return panic("check failed")
    if not (map_from_entries(merged.entries()) == merged):
        return panic("check failed")
    if not (map_from_entries([MapEntry("a", 1), MapEntry("a", 2)]).values() == [2]):
        return panic("check failed")

    merged.for_each(observe_entry)
    let get_keys = merged.keys
    if not (get_keys() == ["a", "b", "c"]):
        return panic("check failed")
    if not (original.clone().clear().length() == 0):
        return panic("check failed")
    if not (original.values() == [1, 2]):
        return panic("check failed")
    if not (other.values() == [3, 4]):
        return panic("check failed")

test "set algebra and enumeration preserve source values":
    let left = [1, 2, 3].to_set()
    let right = [3, 4].to_set()
    if not (left.union(right).values() == [1, 2, 3, 4]):
        return panic("check failed")
    if not (left.intersection(right).values() == [3]):
        return panic("check failed")
    if not (left.difference(right).values() == [1, 2]):
        return panic("check failed")
    if not (left.symmetric_difference(right).values() == [1, 2, 4]):
        return panic("check failed")
    if not ([3].to_set().is_subset_of(left)):
        return panic("check failed")
    if not (left.is_superset_of([1, 3].to_set())):
        return panic("check failed")
    if not (not left.is_subset_of(right)):
        return panic("check failed")
    if not (not right.is_superset_of(left)):
        return panic("check failed")
    if not (left.is_disjoint_from([5].to_set())):
        return panic("check failed")
    if not (not left.is_disjoint_from(right)):
        return panic("check failed")

    let empty = Set[Int]()
    if not (empty.is_subset_of(left)):
        return panic("check failed")
    if not (left.is_superset_of(empty)):
        return panic("check failed")
    if not (empty.is_disjoint_from(left)):
        return panic("check failed")
    if not (left.entries() == [[1, 1], [2, 2], [3, 3]]):
        return panic("check failed")

    left.for_each(observe)
    if not (left.clone().clear() == empty):
        return panic("check failed")
    if not (left.values() == [1, 2, 3]):
        return panic("check failed")

test "string methods use Unicode scalars":
    if not ("é🙂é".at(-1) == some("é")):
        return panic("check failed")
    if not ("é🙂é".scalar_at(1) == some(128578)):
        return panic("check failed")

    let missing: Optional[String] = none
    if not ("".at(0) == missing):
        return panic("check failed")
    if not ("é".at(-9223372036854775808) == missing):
        return panic("check failed")
    if not ("é🙂é".index_of("🙂") == some(1)):
        return panic("check failed")
    if not ("é🙂é".last_index_of("é") == some(2)):
        return panic("check failed")
    if not ("é🙂é".last_index_of("") == some(3)):
        return panic("check failed")
    if not ("é🙂é".index_of("") == some(0)):
        return panic("check failed")

    let absent: Optional[Int] = none
    if not ("é🙂é".index_of("z") == absent):
        return panic("check failed")
    if not ("é🙂é".last_index_of("z") == absent):
        return panic("check failed")
    if not ("é🙂é".slice(-2, 3).unwrap() == "🙂é"):
        return panic("check failed")
    if not ("é🙂é".slice(2, 1).is_error()):
        return panic("check failed")
    if not ("é🙂é".slice(-99, 1).is_error()):
        return panic("check failed")
    if not ("é🙂".scalar_length() == 2):
        return panic("check failed")
    if not ("é🙂".scalar_values() == [233, 128578]):
        return panic("check failed")
    if not ("\t hello \n".trim() == "hello"):
        return panic("check failed")
    if not ("\t hello \n".trim_start() == "hello \n"):
        return panic("check failed")
    if not ("\t hello \n".trim_end() == "\t hello"):
        return panic("check failed")
    if not ("éAb".upper() == "ÉAB"):
        return panic("check failed")
    if not ("ÉAB".lower() == "éab"):
        return panic("check failed")
    if not ("abc".contains("b")):
        return panic("check failed")
    if not ("abc".starts_with("ab")):
        return panic("check failed")
    if not ("abc".ends_with("bc")):
        return panic("check failed")
    if not ("a,b,c".split(",", 2) == ["a", "b"]):
        return panic("check failed")
    if not ("aba".replace("a", "x", 1) == "xba"):
        return panic("check failed")

    let strip = " hello ".trim
    if not (strip() == "hello"):
        return panic("check failed")

    try checked_expansion()

test "bytes have analogous immutable operations":
    let data = Bytes([1, 2, 3, 2])
    if not (data.at(-1) == some(2)):
        return panic("check failed")

    let missing: Optional[Int] = none
    if not (data.at(-9223372036854775808) == missing):
        return panic("check failed")
    if not (data.contains(Bytes([2, 3]))):
        return panic("check failed")
    if not (data.index_of(Bytes([2])) == some(1)):
        return panic("check failed")
    if not (data.last_index_of(Bytes([2])) == some(3)):
        return panic("check failed")
    if not (data.index_of(Bytes([9])) == missing):
        return panic("check failed")
    if not (data.starts_with(Bytes([1, 2]))):
        return panic("check failed")
    if not (data.ends_with(Bytes([3, 2]))):
        return panic("check failed")
    if not (data.slice(1, 3).unwrap() == Bytes([2, 3])):
        return panic("check failed")
    if not (data.reversed() == Bytes([2, 3, 2, 1])):
        return panic("check failed")
    if not (data.with_value(-1, 255) == Bytes([1, 2, 3, 255])):
        return panic("check failed")
    if not (Bytes([]).is_empty()):
        return panic("check failed")
    if not (not data.is_empty()):
        return panic("check failed")
    if not (data == Bytes([1, 2, 3, 2])):
        return panic("check failed")
    if not (255.to_string_radix(16) == "ff"):
        return panic("check failed")
    if not (1.5.to_string() == "1.5"):
        return panic("check failed")
    if not (1.5.is_finite()):
        return panic("check failed")
    if not (not 1.5.is_nan()):
        return panic("check failed")

test "growth limits and invalid inputs return values":
    let too_large: Result[String, StringError] = error(StringError.LimitExceeded)
    let invalid: Result[String, StringError] = error(StringError.InvalidInput)
    if not ("x".pad_start(4, "é🙂", 8) == too_large):
        return panic("check failed")
    if not ("x".pad_end(9223372036854775807, "é", 8) == too_large):
        return panic("check failed")
    if not ("abc".pad_start(1, "", 2) == too_large):
        return panic("check failed")
    if not ("x".pad_start(-1, " ", 8) == invalid):
        return panic("check failed")

    let unchanged: Result[String, StringError] = ok("x")
    if not ("x".pad_end(4, "", 1) == unchanged):
        return panic("check failed")
    if not ("abc".replace_all("", "-", 6) == too_large):
        return panic("check failed")

    let list_limit: Result[List[Int], CollectionError] = error(
        CollectionError.LimitExceeded
    )
    let list_invalid: Result[List[Int], CollectionError] = error(
        CollectionError.InvalidInput
    )
    if not (range_by(0, 4, 1, 3) == list_limit):
        return panic("check failed")
    if not (range_by(0, 4, 0, 3) == list_invalid):
        return panic("check failed")
    if not (filled(1, 2, 1) == list_limit):
        return panic("check failed")

fn parity(value: Int) Int:
    return value % 2

fn default_value(key: String) Int:
    if not (key == "c"):
        return panic("check failed")

    return 3

fn must_not_run(key: String) Int:
    if not (false):
        return panic("check failed")

    return 0

test "grouping and lazy map defaults":
    let grouped = [1, 2, 3, 4].group_by(parity)
    if not (grouped.keys() == [1, 0]):
        return panic("check failed")
    if not (grouped.values() == [[1, 3], [2, 4]]):
        return panic("check failed")

    let group = [1, 2, 3, 4].group_by[Int]
    if not (group(parity) == grouped):
        return panic("check failed")

    let original = Map[String, Int]().add("a", 1)
    if not (original.add_default("a", 9) == original):
        return panic("check failed")
    if not (original.add_default_from("a", must_not_run) == original):
        return panic("check failed")
    if not (original.clone().add_default("b", 2).values() == [1, 2]):
        return panic("check failed")
    if not (original.clone().add_default_from("c", default_value).values() == [1, 3]):
        return panic("check failed")
    if not (original.values() == [1]):
        return panic("check failed")

fn verify_text_and_numbers() Result[Unit, Error]:
    if not (("é".normalize("NFC", 2) | try common_result) == "é"):
        return panic("check failed")
    if not (("é".normalize("NFD", 3) | try common_result) == "é"):
        return panic("check failed")
    if not (("ﬁ".normalize("NFKC", 2) | try common_result) == "fi"):
        return panic("check failed")
    if not (("ﬁ".normalize("NFKD", 2) | try common_result) == "fi"):
        return panic("check failed")
    if not ((1.5.to_fixed(3) | try common_result) == "1.500"):
        return panic("check failed")
    if not ((1.5.to_exponential(3) | try common_result) == "1.500e+0"):
        return panic("check failed")
    if not ((1.5.to_precision(4) | try common_result) == "1.500"):
        return panic("check failed")
    if not ((12345.0.to_precision(3) | try common_result) == "1.23e+4"):
        return panic("check failed")
    if not ((0.000001.to_precision(2) | try common_result) == "0.0000010"):
        return panic("check failed")

    return ok(unit)

test "normalization, empty separators, and precision formatting":
    try verify_text_and_numbers()
    if not ("é🙂".split("", 8) == ["é", "🙂"]):
        return panic("check failed")

    let empty_texts: List[String] = []
    if not ("".split("", 8) == empty_texts):
        return panic("check failed")
    if not ("é🙂".replace("", "-", 1) == "-é🙂"):
        return panic("check failed")
    if not ("".replace("", "-", 1) == "-"):
        return panic("check failed")
    if not ("é".concat("🙂") == "é🙂"):
        return panic("check failed")

    let invalid: Result[String, StringError] = error(StringError.InvalidInput)
    let invalid_number: Result[String, NumberError] = error(NumberError.InvalidInput)
    let limit: Result[String, StringError] = error(StringError.LimitExceeded)
    if not ("é".normalize("invalid", 8) == invalid):
        return panic("check failed")
    if not ("é".normalize("NFD", 2) == limit):
        return panic("check failed")
    if not (1.0.to_fixed(101) == invalid_number):
        return panic("check failed")
    if not (1.0.to_precision(0) == invalid_number):
        return panic("check failed")

fn verify_bigint_and_regex() Result[Unit, Error]:
    let a = from_int(12)
    let b = from_int(5)
    if not (a.add(b).to_string_radix(10) == "17"):
        return panic("check failed")
    if not (a.subtract(b).to_string_radix(10) == "7"):
        return panic("check failed")
    if not (a.multiply(b).to_string_radix(10) == "60"):
        return panic("check failed")
    if not ((a.divide(b) | try common_result | .to_int()) == some(2)):
        return panic("check failed")
    if not ((a.remainder(b) | try common_result | .to_int()) == some(2)):
        return panic("check failed")
    if not (a.compare(b) == 1):
        return panic("check failed")
    if not (a.bit_and(b).to_int() == some(4)):
        return panic("check failed")
    if not (a.bit_or(b).to_int() == some(13)):
        return panic("check failed")
    if not (a.bit_xor(b).to_int() == some(9)):
        return panic("check failed")

    let pattern = compile("[0-9]+") | try common_result
    if not (pattern.matches("a12b3")):
        return panic("check failed")
    if not ((pattern.find_all("a12b3", 2) | try common_result) == ["12", "3"]):
        return panic("check failed")
    if not ((pattern.replace_all("a12b3", "x", 4) | try common_result) == "axbx"):
        return panic("check failed")

    return ok(unit)

test "BigInt and Regex share function implementations with methods":
    try verify_bigint_and_regex()

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
