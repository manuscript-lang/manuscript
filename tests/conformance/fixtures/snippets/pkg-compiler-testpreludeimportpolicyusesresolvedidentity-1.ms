# conform: tags=diagnostics,maps,modules,strings,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/collection_prelude_imports_test.go:131 TestPreludeImportPolicyUsesResolvedIdentity
import {List, Set, ListEntry} from "@types"
import {Map, MapEntry, CollectionError} from "@domain/types.ms"

fn get() Int: (
    List(1).value
    + Set(2).value
    + Map[String, Int](3).value
    + ListEntry(4).value
    + MapEntry[String, Int](5).value
)

fn cause() CollectionError: CollectionError("local")

export fn main() Int: get() - 15
