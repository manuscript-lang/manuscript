# conform: tags=diagnostics,maps,modules,strings,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/collection_prelude_imports_test.go:131 TestPreludeImportPolicyUsesResolvedIdentity
from "@types" import List, Set, ListEntry
from "@domain/types.ms" import Map, MapEntry, CollectionError

def get() -> Int: (
    List(1).value
    + Set(2).value
    + Map[String, Int](3).value
    + ListEntry(4).value
    + MapEntry[String, Int](5).value
)

def cause() -> CollectionError: CollectionError("local")

export def main() -> Int: get() - 15
