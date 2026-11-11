// conform: tags=diagnostics
// conform: phase=check
import ListBuilder, MapBuilder, SetBuilder, filled, map_from_entries from "@std/collections/collections.ms"
import ErrorCategory, TextError, category from "@std/errors.ms"
import Bytes from "@std/bytes.ms"
fn bytes() Bytes: Bytes([1])
fn build() List[Int]: ListBuilder[Int]().freeze()
fn text_error(message: String) TextError: TextError(message)
