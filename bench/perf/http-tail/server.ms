import (
	HttpRequest, HttpResponse, buffered, text from "@std/net/http.ms",
	serve from "@std/net/net.ms",
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

fn main() Void!:
	server := serve(address: "127.0.0.1:8081", handler: buffered(handle))?
	server.wait()?
