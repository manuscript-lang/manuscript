// conform: tags=diagnostics,formatter,modules,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/interface_hints_test.go:83 TestInterfaceViewHintUsesVisibleImplementations
import (
	Sq from "data.ms",
	Shape from "extension.ms",
)

fn shape() Shape => Sq(2)
// expect-error: MS2002 4:1 imports require a relative path or alias; write "./data.ms" for a file next to this one, "@std/name.ms" for the standard library, or declare an alias under [aliases] in ms.toml
