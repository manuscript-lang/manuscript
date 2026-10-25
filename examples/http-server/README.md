# HTTP service example

Build from the repository root, then choose local, worker or process execution:

```sh
ms build examples/http-server/main.ms -o /tmp/manuscript-server
API_TOKEN=development-token-change-me /tmp/manuscript-server local 1 127.0.0.1:8080
API_TOKEN=development-token-change-me /tmp/manuscript-server workers 4 127.0.0.1:8080
API_TOKEN=development-token-change-me /tmp/manuscript-server processes 4 127.0.0.1:8080
```

Run one command at a time. Set a private token of at least 16 bytes for deployment.
Each worker/process runs the complete application and owns its routes and scoped
resources. All members share one listening address; persistent connections stay
with their owning member. Limits apply per member.

```sh
curl http://127.0.0.1:8080/health
curl -H 'Authorization: Bearer development-token-change-me' \
  -H 'Content-Type: application/json' \
  -d '{"name":"Ada"}' http://127.0.0.1:8080/api/greeting
curl -N -H 'Authorization: Bearer development-token-change-me' \
  http://127.0.0.1:8080/api/events
```

`main.ms` shows parent and mounted-router middleware, typed JSON, validation,
SSE, a WebSocket echo route at `/api/socket`, HTML, readiness, bounded observation
logging, and explicit transport budgets. `/api/stats` reports the member handling
that connection. SIGTERM starts the configured drain.

The static-build example invokes an ordinary page handler and publishes its
staged output to a new directory:

```sh
ms run examples/http-server/build.ms -- /tmp/manuscript-site
```

The destination must not already exist. See the [proposal](../../proposals/http-server.md)
for the capability matrix and [validation harnesses](../../bench/http-server/README.md)
for reproducible lifecycle, reference-application and scaling checks.
