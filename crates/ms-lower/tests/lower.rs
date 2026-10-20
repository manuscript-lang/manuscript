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
    // The changed argument travels through a slot the callee takes from and puts back into.
    assert!(mir.contains("slot "));
    assert!(mir.contains("take "));
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

#[test]
fn maps_and_sets() {
    let mir = lower(
        "maps",
        "export fn main() Int:\n    var m = {\"a\": 1}\n    m.add(\"b\", 2)\n    let s = Set[Int]([1, 2])\n    var total = 0\n    for e in m:\n        total += e.value\n    return total + s.length() + m.get_or(\"z\", 0)\n",
    );
    assert!(mir.contains("msrt_map_add"));
    assert!(mir.contains("msrt_list_to_set"));
    assert!(mir.contains("put "));
}

#[test]
fn methods_that_change_self_hand_it_back() {
    let mir = lower(
        "selfmut",
        "interface Counter:\n    fn next() Int\ntype C:\n    n: Int\nimpl Counter for C:\n    fn next() Int:\n        self.n += 1\n        return self.n\nexport fn main() Int:\n    let c = Counter(C(0))\n    let a = c.next()\n    return a + c.next()\n",
    );
    assert!(mir.contains("call.method"));
    assert!(mir.contains("store "));
}

#[test]
fn try_after_an_owned_argument_releases_it() {
    lower(
        "tryargs",
        "import {TextError} from \"@std/errors.ms\"\n\nfn make(n: Int) Result[String, TextError]:\n    if n > 0:\n        return ok(\"x\")\n    return error(TextError(text: \"no\"))\n\nfn join(a: String, b: String) String:\n    return a + b\n\nfn both(n: Int) Result[String, TextError]:\n    return ok(join(a: try make(n), b: try make(n - 1)))\n\nexport fn main() Int:\n    return 0\n",
    );
}

#[test]
fn with_closes_on_every_exit_and_generic_bounds_dispatch_statically() {
    let mir = lower(
        "with",
        "import Closeable from \"@std/cleanup.ms\"\n\ntype Res:\n    n: Int\n\nimpl Closeable for Res:\n    fn close() Unit:\n        let x = self.n\n\nfn run[T: Closeable](r: T, early: Bool) Int:\n    with it = r:\n        if early:\n            return 1\n    return 2\n\nexport fn main() Int:\n    var i = 0\n    while i < 3:\n        with c = Res(i):\n            i += 1\n            if i == 1:\n                continue\n            break\n    return run(r: Res(1), early: true) + i\n",
    );
    assert!(mir.matches("call @Res.close").count() >= 4);
    assert!(mir.contains("cleanup.push"));
}

#[test]
fn native_values_and_time() {
    let mir = lower(
        "native-values",
        "import stdout from \"@std/io.ms\"\nimport {sqrt, max} from \"@std/math.ms\"\nimport {Duration, parse_timestamp} from \"@std/time.ms\"\n\nfn via(f: fn(value: Float) Float, x: Float) Float: f(value: x)\n\nexport fn main() Int:\n    let to_text: fn() String = 7.to_string\n    let d: Duration = 2.seconds\n    let t = parse_timestamp(\"2020-01-02T03:04:05Z\")\n    let r = stdout().write(\"{to_text()} {via(f: sqrt, x: 4.0)} {max(left: 1, right: 2)} {d.to_milliseconds()}\\n\")\n    return 0\n",
    );
    assert!(mir.contains("closure.new"));
    assert!(mir.contains("msstd_time_parse_timestamp"));
}

#[test]
fn error_values_print_their_dynamic_text_and_equal_uses_impls() {
    let mir = lower(
        "dyntext",
        "import stdout from \"@std/io.ms\"\nimport {TextError} from \"@std/errors.ms\"\n\ntype Key:\n    id: Int\n    label: String\n\nimpl Equal for Key:\n    fn equals(other: Equal) Bool:\n        match other:\n            Key(value): return self.id == value.id\n            _: return false\n\nexport fn main() Int:\n    let e: Error = TextError(\"bad\")\n    let a = Key(id: 1, label: \"a\")\n    let b = Key(id: 1, label: \"b\")\n    let r = stdout().write(\"{e} {a == b}\\n\")\n    return 0\n",
    );
    assert!(mir.contains("iface.is"));
    assert!(mir.contains("iface.new"));
}

#[test]
fn loop_variables_survive_a_removed_trivial_join() {
    // `count` is untouched by the inner loop; reading it through the loop header while the
    // condition's join was being resolved once left a stale edge argument.
    let mir = lower(
        "joinloop",
        "type Reader:\n    pos: Int\n\nfn peek(reader: Reader) String:\n    return \"a\"\n\nfn advance(var reader: Reader) String:\n    reader.pos += 1\n    return \"a\"\n\nfn run(var reader: Reader) Int:\n    var count = 0\n    while true:\n        var key = \"\"\n        while reader.pos < 3 and \"abc\".contains(peek(reader)):\n            key = key.concat(advance(reader))\n        if key == \"\": return 9\n        count += 1\n        if count > 2: return count\n    return 0\n\nexport fn main() Int:\n    return run(Reader(pos: 0))\n",
    );
    assert!(mir.contains("fn @run"));
}

#[test]
fn method_values_type_applications_and_callee_capture() {
    let mir = lower(
        "values",
        "import stdout from \"@std/io.ms\"\n\nfn identity[T](value: T) T: value\n\nfn run(f: fn(value: Int) Int) Int: f(value: 1)\n\nexport fn main() Int:\n    let items = [4, 5]\n    let count = items.count\n    let lookup = items.get\n    let same = identity[Int]\n    var selected = same\n    let n = selected(match some(0):\n        some(_):\n            selected = fn(value: Int): value + 1\n            3\n        none: 3\n    )\n    let r = stdout().write(\"{lookup(1)} {n} {run(same)} {count(fn(x: Int): x > 4)}\\n\")\n    return 0\n",
    );
    assert!(mir.contains("closure.new"));
}

#[test]
fn comparable_impls_order_extremes_and_result_methods_are_values() {
    let mir = lower(
        "ordering",
        "import stdout from \"@std/io.ms\"\nimport {max} from \"@std/math.ms\"\n\ntype Version:\n    major: Int\n\nimpl Comparable for Version:\n    fn compare(other: Comparable) Int:\n        match other:\n            Version(value): return self.major - value.major\n            _: return 0\n\nexport fn main() Int:\n    let a = Version(1)\n    let b = Version(2)\n    let c: Result[Int, Error] = ok(1)\n    let e = c.is_ok\n    let r = stdout().write(\"{max(a, b).major} {e()}\\n\")\n    return 0\n",
    );
    assert!(mir.contains("call.method"));
}

#[test]
fn lambdas_and_function_values_fill_omitted_defaults() {
    let mir = lower(
        "defaults",
        "import stdout from \"@std/io.ms\"\n\nfn scale(value: Int, by: Int = 2) Int: value * by\n\nexport fn main() Int:\n    let f = scale\n    let g = fn(value: Int = 4): value\n    let r = stdout().write(\"{f(3)} {f(3, 3)} {g()}\\n\")\n    return 0\n",
    );
    assert!(mir.contains("opt.is_some"));
}

#[test]
fn direct_call_with_try_default_runs_it_in_the_callee_frame() {
    let mir = lower(
        "trydefault",
        "import stdout from \"@std/io.ms\"\nimport {TextError} from \"@std/errors.ms\"\n\nfn fail() Result[Int, TextError]: return error(TextError(\"no\"))\n\nfn get(value: Int = try fail()) Result[Int, TextError]: return ok(value)\n\nexport fn main() Int:\n    let r = stdout().write(\"{get(2).is_ok()} {get().is_ok()}\\n\")\n    return 0\n",
    );
    assert!(mir.contains("call.ind"));
}

#[test]
fn entries_keys_and_add_default_from_lower() {
    let mir = lower(
        "entries",
        "import stdout from \"@std/io.ms\"\n\nexport fn main() Int:\n    var m: Map[String, Int] = Map()\n    m.add_default_from(\"a\", fn(key: String): 5)\n    let items = [4, 5]\n    let r = stdout().write(\"{items.keys()} {items.entries().length()} {[1].to_set().entries()}\\n\")\n    return 0\n",
    );
    assert!(mir.contains("msrt_map_contains"));
}

#[test]
fn impl_method_inherits_contract_defaults_and_binds_with_a_changed_receiver() {
    let mir = lower(
        "inherited",
        "import {Commands, Subprocess, CommandOutput, CommandError} from \"@std/process.ms\"\nimport Bytes from \"@std/bytes.ms\"\nimport Duration from \"@std/time.ms\"\nimport {CsvOptions} from \"@std/csv.ms\"\n\ntype Capture:\n    calls: Int\n\nimpl Commands for Capture:\n    fn run(\n        program: String,\n        arguments: List[String],\n        input: Bytes,\n        max_output_bytes: Optional[Int],\n        timeout: Optional[Duration]\n    ) Result[CommandOutput, CommandError]:\n        self.calls += 1\n        return ok(CommandOutput(0, input, \"\".to_bytes()))\n\n    fn spawn(program: String, arguments: List[String]) Result[Subprocess, CommandError]:\n        return error(CommandError.Unavailable)\n\nexport fn main() Int:\n    var capture = Capture(0)\n    let bound = capture.run\n    let r = capture.run(\"x\", [])\n    let o = CsvOptions()\n    return 0\n",
    );
    assert!(mir.contains("msrt_string_to_bytes"));
}

#[test]
fn instant_arithmetic() {
    let mir = lower(
        "instant-arithmetic",
        "import {clock} from \"@std/time.ms\"\n\nexport fn main() Int:\n    let a = clock().now()\n    let b = a + 5.seconds\n    let d = b - a\n    let c = b - 1.seconds\n    return d.to_nanoseconds() + c.difference(a).to_nanoseconds()\n",
    );
    assert!(mir.contains("msstd_time_instant_shift"));
    assert!(mir.contains("msstd_time_instant_difference"));
    assert!(mir.contains("msstd_time_instant_unshift"));
}

#[test]
fn error_category_tests_standard_error_tables() {
    let mir = lower(
        "category",
        "import {category} from \"@std/errors.ms\"\nimport {IoError} from \"@std/io.ms\"\n\nexport fn main() Int:\n    let cause: Error = IoError.Closed\n    let c = category(cause)\n    return 0\n",
    );
    assert!(mir.contains("iface.is"));
}

#[test]
fn try_in_an_argument_releases_the_receiver_and_earlier_arguments() {
    let mir = lower(
        "trydrop",
        "import {headers, HttpHeaders, HttpMethod} from \"@std/http.ms\"\nimport network from \"@std/net.ms\"\n\nfn hs() Result[HttpHeaders, Error]: return ok(headers())\n\nfn one() Result[Int, Error]: return ok(1)\n\nfn go(n: Int) Result[Int, Error]:\n    let r = network().request(method: HttpMethod.Get, url: \"http://x/{n}\", headers: (try hs()), body: \"\")\n    let s = \"abc {n}\".replace(\"a\", \"b\", max_replacements: (try one()))\n    return ok(0)\n\nexport fn main() Int:\n    let r = go(1)\n    return 0\n",
    );
    assert!(mir.contains("drop"));
}
