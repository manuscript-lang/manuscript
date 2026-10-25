from "@std/sync.ms" import lock
from "@std/web_build.ms" import StaticBuild
from "@std/web_assets.ms" import asset, load_asset
from "@std/web.ms" import html
from "@std/http.ms" import Request
from "@std/fs.ms" import filesystem, join
from "@std/io.ms" import IoError
from "@std/shared.ms" import share
from "@std/testing.ms" import expect_equal, expect_true

test "static builds render ordinary handlers and export through private scoped staging":
    var site = StaticBuild()
    try site.render("/", "index.html", lambda request: html("<h1>Hello</h1>"))
    try site.add(
        "/assets/app.css", "assets/app.css", try asset("body{}".to_bytes(), "text/css")
    )
    try expect_equal((try site.assets()).handle(Request(path: "/")).status, 200)

    let captured = share("")

    try site.stage(
        lambda path:
            with var flag_guard = lock(captured):
                flag_guard.value = path.clone()

            let data = filesystem().read_file(join([path.clone(), "index.html"]), 1024)
            if data.is_error(): return error(IoError.Unavailable)
            if data.get().decode_utf8().get() != "<h1>Hello</h1>": return error(
                IoError.InvalidData
            )

            let loaded = load_asset(join([path.clone(), "assets/app.css"]), 100)
            if loaded.is_error() or loaded.get().data.decode_utf8().get() != "body{}": return error(
                IoError.InvalidData
            )

            return ok(())
    )

    try expect_true(filesystem().stat(captured.get(), False).is_error())

test "static builds reject traversal portable collisions and exhausted budgets":
    let value = try asset("data".to_bytes())

    for path in ["../secret", "/absolute", "a/../b", "a\\b", "con.txt", "a//b", "name."]:
        var site = StaticBuild()
        try expect_true(site.add("/a", path.clone(), value.clone()).is_error())

    var site = StaticBuild()
    try site.add("/a", "A", value.clone())
    try expect_true(site.add("/b", "a", value.clone()).is_error())
    try expect_true(site.add("/b", "a/child", value.clone()).is_error())

    var tiny = StaticBuild(max_bytes: 3)
    try expect_true(tiny.add("/a", "a", value.clone()).is_error())

test "rewrites retain original inputs preserve query by default and enforce a bound":
    let original = Request(path: "/old", query: "x=1")
    var current = try original.rewrite("/new")
    try expect_equal(current.path, "/new")
    try expect_equal(current.query, "x=1")
    try expect_equal(current.original_path, some("/old"))
    current = try current.rewrite("/other", "x=2")
    try expect_equal(current.query, "x=2")
    try expect_equal(current.original_query, some("x=1"))
    while current.rewrite_count < 8: current = try current.rewrite("/again")
    try expect_true(current.rewrite("/loop").is_error())
    try expect_true(original.rewrite("/../bad").is_error())
    try expect_equal(original.path, "/old")

test "static generation rejects unsupported representation headers and private policies":
    for field in ["Content-Encoding", "Content-Security-Policy", "Cache-Control"]:
        var site = StaticBuild()

        let result = site.render(
            "/",
            "index.html",
            lambda request:
                let response = html("hello")
                response.headers.append(field, "no-store".to_bytes()).get()
                return response
        )

        try expect_true(result.is_error())
