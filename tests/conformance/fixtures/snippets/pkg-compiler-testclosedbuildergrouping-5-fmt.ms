# conform: tags=formatter,modules,parser,stdlib-string,strings,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/compiler/builder_range_test.go:30 TestClosedBuilderGrouping
import StringBuilder from "@std/string.ms"

fn fragment() String: return "x"

fn probe(flag: Bool) String:
    let b = StringBuilder()
