// conform: tags=diagnostics
// conform: phase=check
import (
	Bytes from "@std/bytes.ms",
	ListBuilder,
	MapBuilder,
	SetBuilder,
	filled,
	map_from_entries from "@std/collections/collections.ms",
	ErrorCategory, TextError, category from "@std/errors.ms",
)

fn bytes() Bytes => Bytes([1])

fn build() List[Int] => ListBuilder[Int]().freeze()

fn text_error(message String) TextError => TextError(message)
