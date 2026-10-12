+++
title = "net"
+++

# @std/net.ms

Import each required symbol with `import Name from "@std/net.ms"`.

## Connection {data-api-kind="Interface"}

```manuscript
interface Connection:
    fn close() -> Unit
    fn local_address() -> String
    fn peer_address() -> String
    fn read(max_bytes: Int) -> Result[Optional[Bytes], IoError]
    fn read_timeout(max_bytes: Int, timeout: Duration) -> Result[Optional[Bytes], IoError]
    fn shutdown_write() -> Result[Unit, LibraryError]
    fn tls_info() -> Result[TlsInfo, LibraryError]
    fn write(data: Bytes) -> Result[Unit, IoError]
    fn write_timeout(data: Bytes, timeout: Duration) -> Result[Unit, IoError]
```

## Datagram {data-api-kind="Record"}

```manuscript
type Datagram:
    data: Bytes
    sender: String
```

## DatagramSocket {data-api-kind="Interface"}

```manuscript
interface DatagramSocket:
    fn address() -> String
    fn close() -> Unit
    fn receive(max_bytes: Int) -> Result[Datagram, LibraryError]
    fn receive_timeout(max_bytes: Int, timeout: Duration) -> Result[Datagram, LibraryError]
    fn send(data: Bytes, address: String) -> Result[Unit, LibraryError]
    fn send_timeout(data: Bytes, address: String, timeout: Duration) -> Result[Unit, LibraryError]
```

## DnsRecord {data-api-kind="Record"}

```manuscript
type DnsRecord:
    kind: String
    value: String
    priority: Int
    weight: Int
    port: Int
```

## Listener {data-api-kind="Interface"}

```manuscript
interface Listener:
    fn accept() -> Result[Connection, LibraryError]
    fn accept_timeout(timeout: Duration) -> Result[Connection, LibraryError]
    fn address() -> String
    fn close() -> Unit
```

## contains_ip {data-api-kind="Function"}

```manuscript
fn contains_ip(cidr: String, address: String) -> Result[Bool, LibraryError]
```

## parse_cidr {data-api-kind="Function"}

```manuscript
fn parse_cidr(text: String) -> Result[String, LibraryError]
```

## parse_ip {data-api-kind="Function"}

```manuscript
fn parse_ip(text: String) -> Result[String, LibraryError]
```

