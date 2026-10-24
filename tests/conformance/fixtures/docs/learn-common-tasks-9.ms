# conform: tags=control-flow,diagnostics,modules,stdlib-http,stdlib-io,stdlib-net,stdlib-process,tier-io,try-result
# conform: phase=check
# conform: origin=documentation/learn/common-tasks.md:240
from "@std/process.ms" import arguments
from "@std/http.ms" import HttpError, HttpMethod, headers
from "@std/net.ms" import network
from "@std/io.ms" import stdout

def run() -> Result[Unit, Error]:
    let url = try arguments().first().ok_or(HttpError.InvalidInput)
    let response = try network().request(
        HttpMethod.Get, url, headers(), "", max_response_bytes: 1048576
    )
    if response.metadata().status != 200:
        return error(HttpError.InvalidData)

    let text = try response.body.decode_utf8().ok_or(HttpError.InvalidData)
    try stdout().write(text)
    return stdout().flush()

export def main() -> Int:
    if run().is_error():
        return 1

    return 0
