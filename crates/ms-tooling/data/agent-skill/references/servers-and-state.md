# Servers and state

A `serve` handler runs on many threads and only reads what it captures, so it cannot change shared state. Do not look for a Mutex or Cell and do not write an accept loop. Give the state one owner, a promise, and let handlers send it events through a `pipe`.

- The owner takes the reader (`var hits`) and loops until every writer has closed; it returns the final state with `wait()`.
- Each handler call takes its own writer with `events.writer()`; a writer cannot be shared, and it is cheap.
- Keep one `gate` writer open so the owner does not end early; close it after `server.close()`.
- A pipe carries any value, including a record holding a `WriteStream`. A handler that wants answers or pushes (chat, live updates) sends the owner its own writer inside a request; the owner keeps it and writes to it later. Data a handler only reads lives in a read-only source (a file, or a value built before `serve`).

<!-- complete: server-state.ms -->
```manuscript
import promise from "@std/concurrency/promise.ms"
import pipe, Pipe, ReadStream from "@std/io/io.ms"
import serve from "@std/net/net.ms"
import buffered, text, HttpResponse from "@std/net/http.ms"
import fetch from "@std/net/fetch.ms"
import expect_equal from "@std/test/test.ms"

// The one owner of the tally: it reads events until every writer has closed.
fn tally(var hits: ReadStream[String]) Map[String, Int]!:
	var counts = Map[String, Int]()
	for path in hits:
		counts[path] = counts.get_or(path, 0) + 1
	return ok(counts)

// One handler call: tell the owner which path was hit, then answer.
fn record(events: Pipe[String], path: String) HttpResponse:
	var out = events.writer()
	if out.write(path.clone()).is_error(): return text(503, "busy")
	return text(200, "ok")

test "handlers report to one owner":
	var events = pipe[String](16)
	var hits = events.reader()
	var gate = events.writer()
	owner := promise(fn: tally(hits))
	var server = serve("127.0.0.1:0", buffered(fn request: record(events, request.path)))?
	void fetch(f"http://{server.address()}/a").wait()?
	void fetch(f"http://{server.address()}/a").wait()?
	void fetch(f"http://{server.address()}/b").wait()?
	server.close()?
	gate.close()?
	counts := owner.wait()?
	expect_equal(counts.get_or("/a", 0), 2)?
	expect_equal(counts.get_or("/b", 0), 1)?
```

`serve(":0", ...)` picks a free port; `server.address()` names it. `buffered` adapts `fn(HttpRequest) HttpResponse` for `serve`; use `HttpExchange` for streaming bodies.
