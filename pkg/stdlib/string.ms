# Canonical standard-library declarations. Implementations are native.

import Error from "@std/errors.ms"
import Optional from "@std/optional.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"

export type StringError:
    case InvalidInput
    case OutOfRange
    case LimitExceeded
    case Failed(message: String)

fn contains(value: String, text: String) -> Bool

fn ends_with(value: String, suffix: String) -> Bool

export fn from_scalars(values: List[Int]) -> Result[String, StringError]

fn join(parts: List[String], separator: String) -> String

fn lower(text: String) -> String

fn repeat(text: String, count: Int, max_bytes: Optional[Int] = none) -> Result[String, StringError]

fn replace(text: String, old: String, new: String, max_replacements: Optional[Int] = none) -> String

fn scalar_length(text: String) -> Int

fn scalar_values(text: String) -> List[Int]

fn slice_scalars(text: String, start: Int, end: Int) -> Result[String, StringError]

fn split(text: String, separator: String, max_parts: Optional[Int] = none) -> List[String]

fn starts_with(value: String, prefix: String) -> Bool

fn trim(text: String) -> String

fn upper(text: String) -> String

fn at(text: String, index: Int) -> Optional[String]

fn scalar_at(text: String, index: Int) -> Optional[Int]

fn index_of(text: String, value: String) -> Optional[Int]

fn last_index_of(text: String, value: String) -> Optional[Int]

fn trim_start(text: String) -> String

fn trim_end(text: String) -> String

fn slice(text: String, start: Int, end: Int) -> String

fn substring(text: String, start: Int, end: Int) -> String

fn pad_start(text: String, target_length: Int, padding: String, max_bytes: Optional[Int] = none) -> Result[String, StringError]

fn pad_end(text: String, target_length: Int, padding: String, max_bytes: Optional[Int] = none) -> Result[String, StringError]

fn replace_all(text: String, old: String, new: String, max_bytes: Optional[Int] = none) -> Result[String, StringError]

fn normalize(text: String, form: String, max_bytes: Optional[Int] = none) -> Result[String, StringError]

fn concat(text: String, values: String) -> String

impl Error for StringError:
    fn message() -> String

export type StringBuilder:
    fn append(value: String) -> Unit
    fn freeze() -> String
