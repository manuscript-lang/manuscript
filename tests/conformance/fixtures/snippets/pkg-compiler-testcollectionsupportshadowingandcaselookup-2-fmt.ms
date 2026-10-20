# conform: tags=formatter,lists,modules,parser,stdlib-bytes,stdlib-collections,stdlib-errors,strings,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/compiler/collection_prelude_imports_test.go:92 TestCollectionSupportShadowingAndCaseLookup
import {ListBuilder, MapBuilder, SetBuilder, range, filled, map_from_entries} from "@std/collections.ms"
import {ErrorCategory, TextError, category} from "@std/errors.ms"
import Bytes from "@std/bytes.ms"
fn bytes() Bytes: Bytes([1])
fn build() List[Int]: ListBuilder[Int]().freeze()
fn text_error(message: String) TextError: TextError(message)
