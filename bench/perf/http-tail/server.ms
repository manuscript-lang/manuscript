import (
	HttpRequest,
	HttpResponse,
	HttpServerOptions,
	buffered,
	text from "@std/net/http.ms",
	serve from "@std/net/net.ms",
	TlsOptions from "@std/net/tls.ms",
	environment from "@std/os/env.ms",
	read_file from "@std/os/fs.ms",
)

fn handle(request: HttpRequest) HttpResponse:
	var spun = 0

	if request.path.starts_with("/slow"):
		var x = 1
		for i in 0..1000000:
			x = (x * 31 + i) % 1000003
		spun = x

	var out = f"\{\"path\":\"{request.path}\",\"spun\":{spun},\"items\":["
	var count = 64
	if request.path.starts_with("/big"): count = 4096

	for i in 0..count:
		if i > 0: out += ","
		out += f"\{\"id\":{i},\"name\":\"item-{i}\"\}"

	out += "]}"
	return text(200, out)

// HTTP_TAIL_CORES limits the threads that serve (one has no connections to take).
// HTTP_TAIL_TLS names a directory holding cert.pem and key.pem: serve HTTPS, offering
// HTTP/2 and HTTP/1.1 through ALPN. Unset, the server speaks plain HTTP/1.1.
fn main() Void!:
	var options = HttpServerOptions()
	env := environment()?
	directory := env.get("HTTP_TAIL_TLS")

	if directory != null:
		certificate := (read_file(f"{directory}/cert.pem").wait()?).decode_utf8() or ""
		key := (read_file(f"{directory}/key.pem").wait()?).decode_utf8() or ""
		options = HttpServerOptions(
			tls: TlsOptions(
				certificate_pem: certificate,
				private_key_pem: key,
				alpn: ["h2", "http/1.1"],
			)
		)

	cores := env.get("HTTP_TAIL_CORES")
	if cores != null: options.cores = cores.parse_int()

	server := serve(
		address: "127.0.0.1:8081",
		handler: buffered(handle),
		options: options,
	)?
	server.wait()?
