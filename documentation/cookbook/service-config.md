+++
title = "Service configuration"
weight = 16
+++

# Service configuration

Read settings for a service from a JSON file, let environment variables override them, and fail at startup with a clear message when a value is wrong.

## Load settings with defaults and overrides

Save as `settings.ms`. The file supplies the defaults, `PORT` and `LOG_LEVEL` override it, and a missing file means the built-in defaults. Any other read failure, such as a directory or a permission error, stops startup.

<!-- manuscript-example: {"mode":"run","stdout":"listening on 0.0.0.0:8080, level info\n","cases":[{"files":{"settings.json":"{\"host\":\"127.0.0.1\",\"port\":9000}"},"stdout":"listening on 127.0.0.1:9000, level info\n"},{"files":{"settings.json":"{\"port\":\"abc\"}"},"exit_code":1}]} -->
```manuscript
import parse from "@std/data/json.ms"
import environment from "@std/os/env.ms"
import read_file from "@std/os/fs.ms"

type Settings:
    host: String = "0.0.0.0"
    port: Int = 8080
    level: String = "info"

fn from_file(path: String) Settings!:
    bytes := read_file(path).wait()
    if bytes.is_error() and bytes.err().kind == "ENOENT":
        return ok(Settings())
    text := ok_or((bytes?).decode_utf8(), Error("not UTF-8", kind: "EBADMSG"))?
    return parse[Settings](text)

fn apply_environment(var settings: Settings) Void!:
    env := environment()?
    if value := env.get("PORT"):
        settings.port = ok_or(value.parse_int(), Error("PORT is not a number", kind: "EINVAL"))?
    if value := env.get("LOG_LEVEL"):
        settings.level = value.clone()
    return ok()

fn main() Void!:
    var settings = from_file("settings.json")?
    apply_environment(settings)?
    print(f"listening on {settings.host}:{settings.port}, level {settings.level}")
```

```sh
ms run settings.ms
PORT=9001 ms run settings.ms
```

- Missing fields take the defaults declared on `Settings`; a field of the wrong type is an error that names it.
- `main` returns the error, so the process prints it and exits with a failure status instead of starting with a half-read configuration.
