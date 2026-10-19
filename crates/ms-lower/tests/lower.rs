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
    assert!(mir.matches("call @close").count() >= 4);
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
fn network_handles_and_http_handlers() {
    let mir = lower(
        "network-http",
        "import {headers, HttpMethod, HttpRequest, HttpResponse} from \"@std/http.ms\"\nimport network from \"@std/net.ms\"\n\nfn handle(request: HttpRequest) HttpResponse:\n    return HttpResponse(status: 200, headers: headers(), body: request.path.to_bytes())\n\nfn run() Result[Int, Error]:\n    let net = network()\n    let server = try net.serve(address: \"127.0.0.1:0\", handler: handle, max_requests: 1)\n    let response = try net.request(method: HttpMethod.Get, url: \"http://{server.address()}/\", headers: headers(), body: \"\")\n    server.close()\n    return ok(response.metadata().status)\n\nexport fn main() Int:\n    let code = run().get(1)\n    return code\n",
    );
    assert!(mir.contains("msrt_net_network_serve"));
    assert!(mir.contains("msrt_net_network_request"));
    assert!(mir.contains("msrt_http_server_address"));
}

#[test]
fn upload_streams_cross_as_read_closures() {
    let mir = lower(
        "upload-stream",
        "import {expect_equal, expect_ok} from \"@std/testing.ms\"\nimport {Bytes} from \"@std/bytes.ms\"\nimport {headers, HttpMethod, HttpExchange, HttpError, HttpClientOptions, HttpServerOptions} from \"@std/http.ms\"\nimport {ReadStream, IoError} from \"@std/io.ms\"\nimport network from \"@std/net.ms\"\n\ntype Chunks:\n    sent: Bool\n\nimpl ReadStream for Chunks:\n    fn close() Unit:\n        self.sent = self.sent\n    fn read(max_bytes: Optional[Int] = none) Result[Optional[Bytes], IoError]:\n        if self.sent: return ok(none)\n        self.sent = true\n        return ok(some(\"upload-data\".to_bytes()))\n\nfn echo(exchange: HttpExchange) Result[Unit, HttpError]:\n    let body = match exchange.read():\n        ok(found): found\n        error(_): return error(HttpError.InvalidData)\n    let started = try exchange.send_headers(status: 200, headers: headers())\n    let written = match exchange.write_bytes(body.get(Bytes(values: []))):\n        ok(_): 0\n        error(_): return error(HttpError.InvalidData)\n    return ok(unit)\n\nfn run() Result[Int, Error]:\n    let server = try network().serve_stream(address: \"127.0.0.1:0\", handler: echo, options: HttpServerOptions())\n    let client = try network().http_client(options: HttpClientOptions())\n    let source = Chunks(sent: false)\n    let response = try client.request_stream(method: HttpMethod.Post, url: \"http://{server.address()}/\", headers: headers(), body: ReadStream(value: source))\n    return ok(response.metadata().status)\n\nexport fn main() Int:\n    return run().get(1)\n",
    );
    assert!(mir.contains("msrt_http_client_request_stream"));
    assert!(mir.contains("http.read"));
}
