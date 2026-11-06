// conform: tags=control-flow,formatter,modules,parser,stdlib-http,stdlib-io,stdlib-net,stdlib-process,tier-io,try-result
// conform: phase=parse
// conform: origin=documentation/learn/common-tasks.md:240
import arguments from "@std/os/env.ms"
import HttpMethod, headers from "@std/net/http.ms"
import RequestOptions, request from "@std/net/net.ms"
import stdout from "@std/io/io.ms"

fn run() Result[Unit, Error]:
    let url = try arguments().first().ok_or(
        Error("HTTP: invalid input", kind: "EINVAL")
    )
    let response = try request(
        HttpMethod.Get, url,
        options: RequestOptions(headers: headers(), max_bytes: 1048576)
    )
    if response.metadata().status != 200:
        return error(Error("HTTP: invalid data", kind: "EBADMSG"))

    let text = try response.body.decode_utf8().ok_or(
        Error("HTTP: invalid data", kind: "EBADMSG")
    )
    try stdout().write(text)
    return stdout().flush()

export fn main() Int:
    if run().is_error():
        return 1

    return 0
