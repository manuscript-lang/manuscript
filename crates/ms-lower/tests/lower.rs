//! Lowers small programs and verifies the MIR.

use ms_lower::{Options, load, lower_program};
use std::path::PathBuf;

fn lower(name: &str, source: &str) -> String {
    let dir = std::env::temp_dir().join(format!("ms-lower-{}-{name}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("dir");
    let path: PathBuf = dir.join("main.ms");
    std::fs::write(&path, source).expect("write");
    let loaded = load::load(&path);
    let _ = std::fs::remove_dir_all(&dir);
    assert!(loaded.diagnostics.is_empty(), "{:?}", loaded.diagnostics);
    let program = loaded.program.expect("program");
    let module = lower_program(
        &program,
        &Options {
            entry: loaded.entry,
        },
    )
    .expect("lower");
    ms_mir::verify::verify_module(&module).expect("verified MIR");
    ms_mir::print::print_module(&module)
}

#[test]
fn strings_and_loops() {
    let mir = lower(
        "strings",
        "import stdout from \"@std/io.ms\"\n\nexport fn main() Int:\n    var total = 0\n    for x in [1, 2, 3]:\n        total += x\n    let r = stdout().write(\"total {total}\\n\")\n    return 0\n",
    );
    assert!(mir.contains("msrt_string_concat"));
    assert!(mir.contains("iadd.chk"));
}

#[test]
fn caller_evaluated_defaults() {
    let mir = lower(
        "defaults",
        "fn pad(x: Int, by: Int = 2) Int:\n    return x + by\n\nexport fn main() Int:\n    return pad(1)\n",
    );
    assert!(mir.contains("fn @pad"));
}

#[test]
fn match_closures_and_try() {
    let mir = lower(
        "match",
        "import {TextError} from \"@std/errors.ms\"\n\ntype Shape:\n    case Circle(radius: Int)\n    case Dot\n\nfn area(s: Shape) Int:\n    return match s:\n        Shape.Circle(r): r * r\n        _: 0\n\nfn first(xs: List[Int]) Result[Int, TextError]:\n    let n = try parse(xs.length())\n    return ok(n)\n\nfn parse(n: Int) Result[Int, TextError]:\n    if n > 0:\n        return ok(n)\n    return error(TextError(text: \"empty\"))\n\nexport fn main() Int:\n    let doubled = [1, 2, 3].map(fn(x) Int: x * 2)\n    return area(Shape.Circle(doubled.length()))\n",
    );
    assert!(mir.contains("switch"));
    assert!(mir.contains("closure.new"));
}

#[test]
fn var_parameters_return_updated_values() {
    let mir = lower(
        "vars",
        "type Counter:\n    total: Int\n\nimpl Counter:\n    var fn bump(by: Int) Int:\n        self.total += by\n        return self.total\n\nfn add(var xs: List[Int], v: Int) Unit:\n    xs.append(v)\n\nexport fn main() Int:\n    var c = Counter(total: 1)\n    let a = c.bump(4)\n    var l = [1]\n    add(var l, a)\n    return l.length()\n",
    );
    assert!(mir.contains(".vars"));
}

#[test]
fn interface_views_and_error_conversion() {
    let source = std::fs::read_to_string(
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/interfaces.ms"),
    )
    .expect("fixture");
    let mir = lower("interfaces", &source);
    assert!(mir.contains("iface.new"));
    assert!(mir.contains("call.method"));
}
