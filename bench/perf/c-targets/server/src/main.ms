// Idle-connection server for the C rewrite baselines: main <port> <ws|tls> [cert.pem key.pem].
// `ws` serves plain HTTP and, at /ws, upgrades to a WebSocket whose handler then waits for
// messages (an idle connection is a parked handler). `tls` serves HTTPS with /health; the
// handler returns, so the connection idles in the server's keep-alive state.
import (
	HttpExchange,
	HttpRequest,
	HttpResponse,
	HttpServerOptions,
	buffered from "@std/net/http.ms",
	serve from "@std/net/net.ms",
	TlsOptions from "@std/net/tls.ms",
	arguments from "@std/os/env.ms",
	read_file from "@std/os/fs.ms",
)

fn ws_handler(var exchange: HttpExchange) Void!:
	var socket = exchange.upgrade(
		allowed_origins: [],
		subprotocols: [],
		max_message_bytes: 65536,
	)?

	while true:
		message := socket.input.next()?
		if message.is_none(): break

	socket.close()?
	return ok()

fn health(request: HttpRequest) HttpResponse:
	return HttpResponse(200, "ok\n".to_bytes())

fn read_text(path: String) String:
	if bytes := read_file(path).wait():
		return bytes.decode_utf8().get_or("")
	return ""

fn main() Int:
	args := arguments()
	if args.length() < 2: return 2

	var options = HttpServerOptions(cores: 1)
	var handler = ws_handler
	if args.get(1) == "tls":
		if args.length() != 4: return 2
		options = HttpServerOptions(
			cores: 1,
			tls: TlsOptions(
				certificate_pem: read_text(args.get(2)),
				private_key_pem: read_text(args.get(3)),
			),
		)
		handler = buffered(health)

	if acquired := serve(address: f"127.0.0.1:{args.get(0)}", handler: handler, options: options):
		_ignored := acquired.wait()
		return 0
	return 1
