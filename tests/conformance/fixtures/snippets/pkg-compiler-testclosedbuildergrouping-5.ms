# conform: tags=diagnostics,modules,stdlib-string,strings,tier-stdlib
# conform: phase=check
# conform: origin=pkg/compiler/builder_range_test.go:30 TestClosedBuilderGrouping
from "@std/string.ms" import StringBuilder

def fragment() -> String: return "x"

def probe(flag: Bool) -> String:
    let b = StringBuilder()
