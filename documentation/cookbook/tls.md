+++
title = "HTTPS and certificates"
weight = 15
+++

# HTTPS and certificates

Serve HTTPS from your own certificate, call a server that uses a private authority, and warn before a certificate expires. Clients use the system's trusted roots by default, so calling a public HTTPS site needs no setup.

The programs below read PEM files as text. Each one carries the same small helper:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import read_file from "@std/os/fs.ms"

fn read_text(path String) String!:
    bytes := read_file(path).wait()?
    return ok_or(bytes.decode_utf8(), Error("not UTF-8", kind: "EBADMSG"))
```

For a local test, create a certificate and key with `openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -keyout server.key -out server.pem -days 30 -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost"`.

## Serve HTTPS

Save as `serve_tls.ms` and run `ms run serve_tls.ms -- server.pem server.key`. Giving `HttpServerOptions` a `tls` value serves HTTPS and negotiates HTTP/2 or HTTP/1.1.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import arguments from "@std/os/env.ms"
import read_file from "@std/os/fs.ms"
import HttpExchange, HttpServerOptions, reply, text from "@std/net/http.ms"
import serve from "@std/net/net.ms"
import TlsOptions from "@std/net/tls.ms"

fn read_text(path String) String!:
    bytes := read_file(path).wait()?
    return ok_or(bytes.decode_utf8(), Error("not UTF-8", kind: "EBADMSG"))

fn hello(var exchange HttpExchange) Void!:
    return reply(exchange, text(200, "hello over TLS"))

fn main() Void!:
    args := arguments()
    certificate := read_text(args.get_or(0, "server.pem"))?
    key := read_text(args.get_or(1, "server.key"))?
    tls := TlsOptions(certificate_pem: certificate, private_key_pem: key)
    var server = serve("127.0.0.1:8443", hello, HttpServerOptions(tls: tls))?
    print(f"listening on https://{server.address()}/")
    server.wait()?
```

## Trust a private authority

Save as `call_tls.ms` and run `ms run call_tls.ms -- server.pem` while the server runs. `roots_pem` replaces the system roots for this client, so only certificates that chain to it are accepted. The host name in the URL must match the certificate.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import arguments from "@std/os/env.ms"
import read_file from "@std/os/fs.ms"
import HttpClientOptions, HttpMethod, headers from "@std/net/http.ms"
import http_client from "@std/net/net.ms"
import TlsOptions from "@std/net/tls.ms"

fn read_text(path String) String!:
    bytes := read_file(path).wait()?
    return ok_or(bytes.decode_utf8(), Error("not UTF-8", kind: "EBADMSG"))

fn main() Void!:
    ca := read_text(arguments().get_or(0, "ca.pem"))?
    client := http_client(HttpClientOptions(tls: TlsOptions(roots_pem: ca)))?
    response := client.request(HttpMethod.Get, "https://localhost:8443/", headers())?
    print(response.metadata.status)
```

## Warn before a certificate expires

Save as `expiry.ms`. `parse_certificates` reads every certificate in a PEM file; `not_after` is a `Timestamp`, and `difference` gives the time left as a `Duration`.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import arguments from "@std/os/env.ms"
import read_file from "@std/os/fs.ms"
import parse_certificates from "@std/net/tls.ms"
import now from "@std/time.ms"

fn read_text(path String) String!:
    bytes := read_file(path).wait()?
    return ok_or(bytes.decode_utf8(), Error("not UTF-8", kind: "EBADMSG"))

fn main() Void!:
    pem := read_text(arguments().get_or(0, "server.pem"))?
    for certificate in parse_certificates(pem, null)?:
        left := certificate.not_after.difference(now())?
        print(f"{certificate.subject} expires {certificate.not_after}, in {left}")
```

- `verify_certificates(chain_pem, roots_pem, server_name, now)` checks a chain against roots without opening a connection.
- `require_client_certificate: true` on a server asks clients for a certificate that verifies against `roots_pem` (mutual TLS).
