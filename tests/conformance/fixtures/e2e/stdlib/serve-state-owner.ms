// conform: tags=testing,tier-io
// conform: phase=test
import promise from "@std/concurrency/promise.ms"
import pipe, Pipe, ReadStream from "@std/io/io.ms"
import serve from "@std/net/net.ms"
import buffered, text, HttpResponse from "@std/net/http.ms"
import fetch from "@std/net/fetch.ms"
import expect_equal from "@std/test/test.ms"

// The one owner of the tally: it reads events until every writer has closed.
fn tally(var hits ReadStream[String]) Map[String, Int]!:
	var counts = Map[String, Int]()
	for path in hits:
		counts[path] = counts.get_or(path, 0) + 1
	return ok(counts)

// One handler call: tell the owner which path was hit, then answer.
fn record(events Pipe[String], path String) HttpResponse:
	var out = events.writer()
	if out.write(path.clone()).is_error(): return text(503, "busy")
	return text(200, "ok")

test "handlers report to one owner":
	var events = pipe[String](16)
	var hits = events.reader()
	var gate = events.writer()
	owner := promise(() => tally(hits))
	var server = serve("127.0.0.1:0", buffered(request => record(events, request.path)))?
	void fetch(f"http://{server.address()}/a").wait()?
	void fetch(f"http://{server.address()}/a").wait()?
	void fetch(f"http://{server.address()}/b").wait()?
	server.close()?
	gate.close()?
	counts := owner.wait()?
	expect_equal(counts.get_or("/a", 0), 2)?
	expect_equal(counts.get_or("/b", 0), 1)?
