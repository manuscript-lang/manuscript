// conform: tags=diagnostics,maps,modules,strings,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/collection_prelude_imports_test.go:131 TestPreludeImportPolicyUsesResolvedIdentity
import (
	Map, MapEntry from "@domain/types.ms",
	List, ListEntry, Set from "@types",
)

fn get() Int => (
	List(1).value
	+ Set(2).value
	+ Map[String, Int](3).value
	+ ListEntry(4).value
	+ MapEntry[String, Int](5).value
)

fn cause() CollectionError => CollectionError("local")

export fn main() Int => get() - 15
// expect-error: MS2002 4:1 unknown import alias @domain; this project declares none, so add one under [aliases] in ms.toml, e.g. "@lib" = "./src/lib" (use @std/... for the standard library)
