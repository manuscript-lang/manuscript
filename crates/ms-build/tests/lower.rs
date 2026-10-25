//! Lowers small programs and verifies the MIR.

// Links the msrt_* runtime symbols that the standard-library crates reference.
use ms_driver::{CheckRequest, check_graph, load_file};
use ms_lower::{Options, lower_program};
use ms_rt as _;
use std::path::PathBuf;

fn lower(name: &str, source: &str) -> String {
    let dir = std::env::temp_dir().join(format!("ms-lower-{}-{name}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("dir");
    let path: PathBuf = dir.join("main.ms");
    std::fs::write(&path, source).expect("write");
    let loaded = check_graph(
        load_file(&path.to_string_lossy(), Default::default()),
        CheckRequest::default(),
    );
    let _ = std::fs::remove_dir_all(&dir);
    assert!(loaded.success(), "{:?}", loaded.diagnostics);
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
        "from \"@std/io.ms\" import stdout\n\nexport def main() -> Int:\n    var total = 0\n    for x in [1, 2, 3]:\n        total += x\n    let r = stdout().write(f\"total {total}\\n\")\n    return 0\n",
    );
    assert!(mir.contains("msrt_string_concat"));
    assert!(mir.contains("iadd.chk"));
}

#[test]
fn rsa_source_calls_and_function_values() {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../tests/e2e/testdata/stdlib/crypto-rsa.ms");
    let loaded = check_graph(
        load_file(&path.to_string_lossy(), Default::default()),
        CheckRequest::default(),
    );
    assert!(loaded.success(), "{:?}", loaded.diagnostics);
    let (module, tests) = ms_lower::lower_tests(
        &loaded.program.expect("program"),
        &Options {
            entry: loaded.entry,
        },
    )
    .expect("lower RSA fixture");
    assert_eq!(tests.len(), 4);
    ms_mir::verify::verify_module(&module).expect("verified RSA MIR");
    let mir = ms_mir::print::print_module(&module);
    for name in [
        "sign",
        "verify",
        "sign_pss",
        "verify_pss",
        "encrypt",
        "decrypt",
    ] {
        assert!(mir.contains(&format!("msrt_crypto_rsa_{name}")), "{name}");
    }
    assert!(mir.contains("alt.tag"));
    assert!(mir.contains("iface.new"));
}

#[test]
fn caller_evaluated_defaults() {
    let mir = lower(
        "defaults",
        "def pad(x: Int, by: Int = 2) -> Int:\n    return x + by\n\nexport def main() -> Int:\n    return pad(1)\n",
    );
    assert!(mir.contains("fn @pad"));
}

#[test]
fn match_closures_and_try() {
    let mir = lower(
        "match",
        "from \"@std/core.ms\" import TextError\n\ntype Shape:\n    case Circle(radius: Int)\n    case Dot\n\ndef area(s: Shape) -> Int:\n    return match s:\n        case Shape.Circle(r): r * r\n        case _: 0\n\ndef first(xs: List[Int]) -> Result[Int, TextError]:\n    let n = try parse(xs.length())\n    return ok(n)\n\ndef parse(n: Int) -> Result[Int, TextError]:\n    if n > 0:\n        return ok(n)\n    return error(TextError(text: \"empty\"))\n\nexport def main() -> Int:\n    let doubled = [1, 2, 3].map(lambda (x) -> Int: x * 2)\n    return area(Shape.Circle(doubled.length()))\n",
    );
    assert!(mir.contains("switch"));
    assert!(mir.contains("closure.new"));
}

#[test]
fn var_parameters_return_updated_values() {
    let mir = lower(
        "vars",
        "type Counter:\n    total: Int\n\nimpl Counter:\n    var def bump(by: Int) -> Int:\n        self.total += by\n        return self.total\n\ndef add(var xs: List[Int], v: Int) -> Unit:\n    xs.append(v)\n\nexport def main() -> Int:\n    var c = Counter(total: 1)\n    let a = c.bump(4)\n    var l = [1]\n    add(var l, a)\n    return l.length()\n",
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
        "export def main() -> Int:\n    var m = {\"a\": 1}\n    m.add(\"b\", 2)\n    let s = Set[Int]([1, 2])\n    var total = 0\n    for e in m:\n        total += e.value\n    return total + s.length() + m.get_or(\"z\", 0)\n",
    );
    assert!(mir.contains("msrt_map_add"));
    assert!(mir.contains("msrt_list_to_set"));
    assert!(mir.contains("put "));
}

#[test]
fn methods_that_change_self_hand_it_back() {
    let mir = lower(
        "selfmut",
        "interface Counter:\n    var def next() -> Int\ntype C:\n    n: Int\nimpl Counter for C:\n    var def next() -> Int:\n        self.n += 1\n        return self.n\nexport def main() -> Int:\n    var c: Counter = C(0)\n    let a = c.next()\n    return a + c.next()\n",
    );
    assert!(mir.contains("call.method"));
    assert!(mir.contains("store "));
}

#[test]
fn try_after_an_owned_argument_releases_it() {
    lower(
        "tryargs",
        "from \"@std/core.ms\" import TextError\n\ndef make(n: Int) -> Result[String, TextError]:\n    if n > 0:\n        return ok(\"x\")\n    return error(TextError(text: \"no\"))\n\ndef join(a: String, b: String) -> String:\n    return a + b\n\ndef both(n: Int) -> Result[String, TextError]:\n    return ok(join(a: try make(n), b: try make(n - 1)))\n\nexport def main() -> Int:\n    return 0\n",
    );
}

#[test]
fn with_closes_on_every_exit_and_generic_bounds_dispatch_statically() {
    let mir = lower(
        "with",
        "from \"@std/core.ms\" import Closeable\n\ntype Res:\n    n: Int\n\nimpl Closeable for Res:\n    def close() -> Unit:\n        let x = self.n\n\ndef run[T: Closeable](r: T, early: Bool) -> Int:\n    with let it = r:\n        if early:\n            return 1\n    return 2\n\nexport def main() -> Int:\n    var i = 0\n    while i < 3:\n        with let c = Res(i):\n            i += 1\n            if i == 1:\n                continue\n            break\n    return run(r: Res(1), early: True) + i\n",
    );
    assert!(mir.matches("call @Res.close").count() >= 4);
    assert!(mir.contains("cleanup.push"));
}

#[test]
fn native_values_and_time() {
    let mir = lower(
        "native-values",
        "from \"@std/io.ms\" import stdout\nfrom \"@std/math.ms\" import sqrt, max\nfrom \"@std/time.ms\" import Duration, parse_timestamp\n\ndef via(f: Callable[[Float], Float], x: Float) -> Float: f(x)\n\nexport def main() -> Int:\n    let to_text: Callable[[], String] = 7.to_string\n    let d: Duration = 2.seconds\n    let t = parse_timestamp(\"2020-01-02T03:04:05Z\")\n    let r = stdout().write(f\"{to_text()} {via(sqrt, 4.0)} {max(left: 1, right: 2)} {d.to_milliseconds()}\\n\")\n    return 0\n",
    );
    assert!(mir.contains("closure.new"));
    assert!(mir.contains("msstd_time_parse_timestamp"));
}

#[test]
fn error_values_print_their_dynamic_text_and_equal_uses_impls() {
    let mir = lower(
        "dyntext",
        "from \"@std/io.ms\" import stdout\nfrom \"@std/core.ms\" import TextError\n\ntype Key:\n    id: Int\n    label: String\n\nimpl Equal for Key:\n    def equals(other: Equal) -> Bool:\n        match other:\n            case Key(value): return self.id == value.id\n            case _: return False\n\nexport def main() -> Int:\n    let e: Error = TextError(\"bad\")\n    let a = Key(id: 1, label: \"a\")\n    let b = Key(id: 1, label: \"b\")\n    let r = stdout().write(f\"{e} {a == b}\\n\")\n    return 0\n",
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
        "type Reader:\n    pos: Int\n\ndef peek(reader: Reader) -> String:\n    return \"a\"\n\ndef advance(var reader: Reader) -> String:\n    reader.pos += 1\n    return \"a\"\n\ndef run(var reader: Reader) -> Int:\n    var count = 0\n    while True:\n        var key = \"\"\n        while reader.pos < 3 and \"abc\".contains(peek(reader)):\n            key = key.concat(advance(var reader))\n        if key == \"\": return 9\n        count += 1\n        if count > 2: return count\n    return 0\n\nexport def main() -> Int:\n    var reader = Reader(pos: 0)\n    return run(var reader)\n",
    );
    assert!(mir.contains("fn @run"));
}

#[test]
fn method_values_type_applications_and_callee_capture() {
    let mir = lower(
        "values",
        "from \"@std/io.ms\" import stdout\n\ndef identity[T](value: T) -> T: value\n\ndef run(f: Callable[[Int], Int]) -> Int: f(1)\n\nexport def main() -> Int:\n    let items = [4, 5]\n    let count = items.count\n    let lookup = items.get\n    let same = identity[Int]\n    var selected = identity[Int]\n    let n = selected(match some(0):\n        case some(_):\n            selected = lambda (value: Int): value + 1\n            3\n        case none: 3\n    )\n    let r = stdout().write(f\"{lookup(1)} {n} {run(same)} {count(lambda (x: Int): x > 4)}\\n\")\n    return 0\n",
    );
    assert!(mir.contains("closure.new"));
}

#[test]
fn comparable_impls_order_extremes_and_result_methods_are_values() {
    let mir = lower(
        "ordering",
        "from \"@std/io.ms\" import stdout\nfrom \"@std/math.ms\" import max\n\ntype Version:\n    major: Int\n\nimpl Comparable for Version:\n    def compare(other: Comparable) -> Int:\n        match other:\n            case Version(value): return self.major - value.major\n            case _: return 0\n\nexport def main() -> Int:\n    let a = Version(1)\n    let b = Version(2)\n    let c: Result[Int, Error] = ok(1)\n    let e = c.is_ok\n    let r = stdout().write(f\"{max(a, b).major} {e()}\\n\")\n    return 0\n",
    );
    assert!(mir.contains("call.method"));
}

#[test]
fn lambdas_and_function_values_fill_omitted_defaults() {
    let mir = lower(
        "defaults",
        "from \"@std/io.ms\" import stdout\n\ndef scale(value: Int, by: Int = 2) -> Int: value * by\n\nexport def main() -> Int:\n    let f = scale\n    let g = lambda (value: Int = 4): value\n    let r = stdout().write(f\"{f(3)} {f(3, 3)} {g()}\\n\")\n    return 0\n",
    );
    assert!(mir.contains("opt.is_some"));
}

#[test]
fn direct_call_with_try_default_runs_it_in_the_callee_frame() {
    let mir = lower(
        "trydefault",
        "from \"@std/io.ms\" import stdout\nfrom \"@std/core.ms\" import TextError\n\ndef fail() -> Result[Int, TextError]: return error(TextError(\"no\"))\n\ndef get(value: Int = try fail()) -> Result[Int, TextError]: return ok(value)\n\nexport def main() -> Int:\n    let r = stdout().write(f\"{get(2).is_ok()} {get().is_ok()}\\n\")\n    return 0\n",
    );
    assert!(mir.contains("call.ind"));
}

#[test]
fn entries_keys_and_add_default_from_lower() {
    let mir = lower(
        "entries",
        "from \"@std/io.ms\" import stdout\n\nexport def main() -> Int:\n    var m: Map[String, Int] = Map()\n    m.add_default_from(\"a\", lambda (key: String): 5)\n    let items = [4, 5]\n    let r = stdout().write(f\"{items.keys()} {items.entries().length()}\\n\")\n    return 0\n",
    );
    assert!(mir.contains("msrt_map_contains"));
}

#[test]
fn impl_method_inherits_contract_defaults_and_binds_with_a_changed_receiver() {
    let mir = lower(
        "inherited",
        "from \"@std/process.ms\" import Subprocess, CommandOutput, CommandError\nfrom \"@std/bytes.ms\" import Bytes\nfrom \"@std/time.ms\" import Duration\nfrom \"@std/csv.ms\" import CsvOptions\n\ninterface Runner:\n    var def run(\n        program: String,\n        arguments: List[String],\n        input: Bytes,\n        max_output_bytes: Optional[Int] = none,\n        timeout: Optional[Duration] = none\n    ) -> Result[CommandOutput, CommandError]\n    def spawn(program: String, arguments: List[String]) -> Result[Subprocess, CommandError]\n\ntype Capture:\n    calls: Int\n\nimpl Runner for Capture:\n    var def run(\n        program: String,\n        arguments: List[String],\n        input: Bytes,\n        max_output_bytes: Optional[Int],\n        timeout: Optional[Duration]\n    ) -> Result[CommandOutput, CommandError]:\n        self.calls += 1\n        return ok(CommandOutput(0, input, \"\".to_bytes()))\n\n    def spawn(program: String, arguments: List[String]) -> Result[Subprocess, CommandError]:\n        return error(CommandError.Unavailable)\n\nexport def main() -> Int:\n    var capture = Capture(0)\n    let bound = capture.run\n    let r = capture.run(\"x\", [], \"\".to_bytes())\n    let o = CsvOptions()\n    return 0\n",
    );
    assert!(mir.contains("msrt_string_to_bytes"));
}

#[test]
fn instant_arithmetic() {
    let mir = lower(
        "instant-arithmetic",
        "from \"@std/time.ms\" import clock\n\nexport def main() -> Int:\n    let a = clock().now()\n    let b = a + 5.seconds\n    let d = b - a\n    let c = b - 1.seconds\n    return d.to_nanoseconds() + c.difference(a).to_nanoseconds()\n",
    );
    assert!(mir.contains("msstd_time_instant_shift"));
    assert!(mir.contains("msstd_time_instant_difference"));
    assert!(mir.contains("msstd_time_instant_unshift"));
}

#[test]
fn error_category_tests_standard_error_tables() {
    let mir = lower(
        "category",
        "from \"@std/core.ms\" import category\nfrom \"@std/io.ms\" import IoError\n\nexport def main() -> Int:\n    let cause: Error = IoError.Closed\n    let c = category(cause)\n    return 0\n",
    );
    assert!(mir.contains("iface.is"));
}

#[test]
fn try_in_an_argument_releases_the_receiver_and_earlier_arguments() {
    let mir = lower(
        "trydrop",
        "from \"@std/http.ms\" import headers, HttpHeaders, HttpMethod\nfrom \"@std/net.ms\" import network\n\ndef hs() -> Result[HttpHeaders, Error]: return ok(headers())\n\ndef one() -> Result[String, Error]: return ok(\"b\")\n\ndef go(n: Int) -> Result[Int, Error]:\n    let r = network().request(method: HttpMethod.Get, url: f\"http://x/{n}\", headers: (try hs()), body: \"\")\n    let s = f\"abc {n}\".replace(\"a\", (try one()))\n    return ok(0)\n\nexport def main() -> Int:\n    let r = go(1)\n    return 0\n",
    );
    assert!(mir.contains("drop"));
}

#[test]
fn try_in_a_literal_releases_the_elements_built_before_it() {
    // The verifier rejects an owned element, map, or key left unreleased on the early return.
    lower(
        "tryliteral",
        "from \"@std/core.ms\" import TextError\n\ndef bad() -> Result[String, Error]:\n    return error(TextError(\"no\"))\n\ndef list() -> Result[Int, Error]:\n    let xs = [\"a\", try bad(), \"c\"]\n    return ok(xs.length())\n\ndef nested() -> Result[Int, Error]:\n    let xs = [[\"a\"], [\"b\", try bad()]]\n    return ok(xs.length())\n\ndef map_value() -> Result[Int, Error]:\n    let m = {\"a\": \"x\", \"b\": try bad()}\n    return ok(m.length())\n\ndef map_key() -> Result[Int, Error]:\n    let m = {\"a\": \"x\", (try bad()): \"y\"}\n    return ok(m.length())\n\nexport def main() -> Int:\n    let a = list()\n    let b = nested()\n    let c = map_value()\n    let d = map_key()\n    return 0\n",
    );
}

#[test]
fn element_slot_keeps_a_record_whose_field_is_named_like_the_parameter() {
    let mir = lower(
        "elemslot",
        "type Child:\n    value: Int\n\nexport def main() -> Int:\n    var values = [Child(1), Child(1)]\n    let c = Child(9)\n    values.fill(c, 0, 1)\n    return values.length()\n",
    );
    assert!(mir.contains("store %"));
}

#[test]
fn collection_builders_are_shared_handles() {
    let mir = lower(
        "shared-builders",
        "from \"@std/collections.ms\" import ListBuilder\n\nexport def main() -> Int:\n    var b = ListBuilder[Int]()\n    b.append(1)\n    b.append(2)\n    return b.build().length()\n",
    );
    assert!(mir.contains("shared.new"));
    assert!(mir.contains("shared.addr"));
    assert!(mir.contains("builder is sealed"));
}

#[test]
fn a_for_over_a_temporary_iterator_drops_it_when_the_loop_ends() {
    let mir = lower(
        "iterator-scope",
        "from \"@std/core.ms\" import Iterator\n\ntype Counter:\n    n: Int\n    label: String\n\nimpl Iterator[Int] for Counter:\n    var def next() -> Optional[Int]:\n        if self.n == 0: return none\n        self.n -= 1\n        return some(self.n)\n\ndef make() -> Counter:\n    return Counter(n: 3, label: \"c\")\n\ndef after() -> Int:\n    return 7\n\nexport def main() -> Int:\n    var total = 0\n    for x in make():\n        total += x\n    return total + after()\n",
    );
    let main = mir.split("fn @main").nth(1).expect("main");
    let drop = main.find("drop ").expect("the iterator is dropped");
    let call = main.find("@after").expect("the call after the loop");
    assert!(
        drop < call,
        "the hidden iterator outlives the loop:\n{main}"
    );
}
