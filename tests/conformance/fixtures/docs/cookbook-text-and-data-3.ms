// conform: tags=control-flow,diagnostics,modules,stdlib-http,stdlib-io,stdlib-net,stdlib-process,tier-io,try-result
// conform: phase=check
// conform: origin=documentation/learn/common-tasks.md:240
import arguments from "@std/os/env.ms"
import HttpMethod, headers from "@std/net/http.ms"
import RequestOptions, request from "@std/net/net.ms"
import stdout from "@std/io/io.ms"

fn run() Result[Unit, Error]:
    url := arguments().first().ok_or(
        Error("HTTP: invalid input", kind: "EINVAL")
    )?
    response := request(
        HttpMethod.Get, url,
        options: RequestOptions(headers: headers(), max_bytes: 1048576)
    )?
    if response.metadata().status != 200:
        return error(Error("HTTP: invalid data", kind: "EBADMSG"))

    text := response.body.decode_utf8().ok_or(
        Error("HTTP: invalid data", kind: "EBADMSG")
    )?
    stdout().write(text)?
    return stdout().flush()

fn main() Unit!:
    run()?
