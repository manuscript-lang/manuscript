// Shared body of the HTTP request guards: a keep-alive HTTP request to a trivial
// handler costs a fixed number of instructions. The program serves one connection of
// 10000 requests with one server worker and counts the server alone: the client is this
// same program started as a child (valgrind does not follow it), so reading the replies
// is not in the count. `make perf-counts` passes the program's own path as the
// argument; run by hand as `main <own path>`. Each guard's main.ms passes the request
// it sends.
import (
	Bytes from "@std/bytes.ms",
	HttpRequest,
	HttpResponse,
	HttpServerOptions,
	buffered,
	headers from "@std/net/http.ms",
	connect, serve from "@std/net/net.ms",
	arguments from "@std/os/env.ms",
	RunOptions, run from "@std/os/process.ms",
	seconds from "@std/time.ms",
)

REQUESTS := 10000

fn handle(request HttpRequest) HttpResponse:
	return HttpResponse(
		status: 200,
		headers: headers(),
		body: "{\"ok\":true,\"items\":[1,2,3,4,5,6,7,8,9,10]}".to_bytes(),
	)

fn client(address String, request String) Int!:
	var connection = connect(address, timeout: seconds(5)).wait()?
	var answered = 0

	for i in 0..REQUESTS:
		connection.output.write(request.to_bytes())?
		connection.output.flush()?

		reply := connection.input.next()?
		if (reply or Bytes([])).length() > 0: answered += 1

	return ok(answered)

fn drive(own_path String, request String) Int!:
	server := serve(
		address: "127.0.0.1:0",
		handler: buffered(handle),
		options: HttpServerOptions(cores: 1),
	)?
	out := run(
		own_path,
		["client", server.address(), request.clone()],
		RunOptions(timeout: seconds(600)),
	).wait()?
	return ok((out.stdout.decode_utf8() or "").trim().parse_int() or 0)

// The guard's exit status: 0 when every request was answered. `request` is the whole
// request text, sent on each pass.
export fn guard(request String) Int:
	args := arguments()

	if args.length() == 3 and args[0] == "client":
		print(client(args[1].clone(), args[2].clone()).get_or(0))
		return 0

	if args.length() == 0 or args.length() > 2:
		print("usage: main <own path>")
		return 1

	answered := drive(args[0].clone(), request).get_or(0)
	print(answered)
	if answered != REQUESTS: return 1

	return 0
