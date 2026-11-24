+++
title = "Logging"
weight = 17
+++

# Logging

Write structured records, one JSON object per line, to standard output or a file that rotates by size.

## Log structured records

Save as `logs.ms`. Each record has a level, a message and optional fields of any data type. `child` binds fields that appear on every record from that logger.

<!-- manuscript-example: {"mode":"run","stdout":"{\"level\":30,\"msg\":\"started\",\"data\":{\"port\":8080}}\n{\"level\":40,\"msg\":\"slow request\",\"context\":{\"request\":7},\"data\":{\"ms\":950}}\n"} -->
```manuscript
import LoggerOptions, create, stdout_transport from "@std/log.ms"

type Started:
    port Int

type Slow:
    ms Int

type Request:
    request Int

fn main() Void!:
    log := create(stdout_transport(), LoggerOptions(timestamp: false))?
    log.info("started", Started(port: 8080))?
    log.debug("not shown at the default level")?
    handler := log.child(Request(request: 7))?
    handler.warn("slow request", Slow(ms: 950))?
    return ok()
```

```sh
ms run logs.ms
```

- The default level is `Info`; `LoggerOptions(level: LogLevel.Debug)` lowers it. Records below the level are not encoded.
- Timestamps are on by default. This example turns them off so the output is the same on every run.
- A record is one line, so `grep`, `jq` and log shippers read it without extra parsing.

## Write to a rotating file

Save as `rotate.ms`. `rotating_file_transport(path, max_bytes, keep)` moves the file aside to `app.log.1`, `app.log.2` and so on once it would pass `max_bytes`, and keeps `keep` old files.

<!-- manuscript-example: {"mode":"run","stdout":"ok\n"} -->
```manuscript
import LoggerOptions, create, rotating_file_transport from "@std/log.ms"

fn main() Void!:
    var log = create(rotating_file_transport("app.log", 200, 2)?, LoggerOptions(timestamp: false))?
    for i in 0..20:
        log.info(f"record {i}")?
    log.close()?
    print("ok")
```
