+++
title = "Typed intermediate representation"
weight = 91
+++

# Typed intermediate representation

Inspect checked types and positions to review an agent’s compiler-query change (repository root).

```sh
target/release/ms inspect examples/hello/ms.toml -o inspection.json
sed -n '3,14p' inspection.json
```

```text
    {
      "checker_id": "local3_message",
      "name": "message",
      "type": "String",
      "span": {
        "file": "src/main.ms",
        "start": 109,
        "end": 156,
        "line": 5,
        "column": 9
      }
    },
```

- The JSON excerpt identifies a local’s checked type and source span.
- Alpha: query APIs may change.


Next: [HIR queries](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/HIR.md) and [ownership facts](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md).
