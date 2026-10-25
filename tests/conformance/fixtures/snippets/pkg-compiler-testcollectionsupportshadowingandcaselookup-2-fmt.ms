# conform: tags=formatter,lists,modules,parser,stdlib-bytes,stdlib-collections,stdlib-errors,strings,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/compiler/collection_prelude_imports_test.go:92 TestCollectionSupportShadowingAndCaseLookup
from "@std/collections.ms" import ListBuilder, MapBuilder, SetBuilder, range, filled, map_from_entries
from "@std/core.ms" import ErrorCategory, TextError, category
from "@std/bytes.ms" import Bytes

def bytes() -> Bytes: Bytes([1])

def build() -> List[Int]: ListBuilder[Int]().build()

def text_error(message: String) -> TextError: TextError(message)
