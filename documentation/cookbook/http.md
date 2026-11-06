+++
title = "HTTP requests"
weight = 4
+++

# HTTP requests

Make an HTTP GET request and read the response. Each program is a complete `.ms` file: save it under the shown name and run the command from that directory ([getting started](../learn/getting-started.md)). `main` returns the exit status.

## Make an HTTP GET request

Save as `get.ms`. `fetch` buffers the body, `check_status()` rejects statuses outside 200–299, and `text()` decodes UTF-8.

<!-- manuscript-example: {"mode":"run","args":["$HTTP_URL"],"http":{"status":200,"body":"hello from HTTP\n"},"stdout":"hello from HTTP\n","cases":[{"args":["$HTTP_URL"],"http":{"status":404,"body":"missing"},"exit_code":1},{"args":["invalid URL"],"exit_code":1},{"exit_code":1}]} -->
```manuscript
import arguments from "@std/os/env.ms"
import fetch, FetchOptions from "@std/net/fetch.ms"
import stdout from "@std/io/io.ms"

fn run() Result[Unit, Error]:
    let url = try arguments().first().ok_or(Error("missing URL", kind: "EINVAL"))
    let response = try fetch(url, FetchOptions(max_response_bytes: 1048576)).wait()
    try response.check_status()
    let text = try response.text()
    try stdout().write(text)
    return stdout().flush()

export fn main() Int:
    if run().is_error():
        return 1
    return 0
```

```sh
# In another terminal, serve notes.txt from the current directory:
python3 -m http.server 8000 --bind 127.0.0.1

# In your program's terminal:
ms run get.ms -- http://127.0.0.1:8000/notes.txt
```

The program prints the contents served from `notes.txt`:

```text
hello from a file
```

The server needs Python 3 and a `notes.txt` (from the file-reading recipe). Transport failures, non-success statuses and invalid UTF-8 exit 1; the body is capped at one mebibyte (1,048,576 bytes). Other `FetchOptions` fields keep their defaults, including the 30-second deadline.

For a JSON response, `try response.json[Config]()` decodes into a type such as the `Config` above. Call `check_status()` first when an error status should fail the operation: `fetch` itself returns error statuses as ordinary responses. For repeated requests, bind a pooled `Fetcher` with `let client = try fetcher()`; see the [fetch API](../standard-library/reference/net/fetch.ms.md).

Next: the [cookbook](_index.md), [testing](../learn/testing.md) and [counting loops](../core-language/control-flow/loops.md#counting-loops).
