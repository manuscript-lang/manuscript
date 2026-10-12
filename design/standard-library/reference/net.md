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
    fn shutdown_write() -> Result[Unit, NetworkError]
    fn tls_info() -> Result[TlsInfo, TlsError]
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
    fn receive(max_bytes: Int) -> Result[Datagram, NetworkError]
    fn receive_timeout(max_bytes: Int, timeout: Duration) -> Result[Datagram, NetworkError]
    fn send(data: Bytes, address: String) -> Result[Unit, NetworkError]
    fn send_timeout(data: Bytes, address: String, timeout: Duration) -> Result[Unit, NetworkError]
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
    fn accept() -> Result[Connection, NetworkError]
    fn accept_timeout(timeout: Duration) -> Result[Connection, NetworkError]
    fn address() -> String
    fn close() -> Unit
```

## NetworkError {data-api-kind="Alternative"}

```manuscript
type NetworkError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case PermissionDenied
    case Unsupported
    case Closed
    case Timeout
    case Failed(message: String)
```

```manuscript
impl Error for NetworkError:
    fn message() -> String
```

## contains_ip {data-api-kind="Function"}

```manuscript
fn contains_ip(cidr: String, address: String) -> Result[Bool, NetworkError]
```

## parse_cidr {data-api-kind="Function"}

```manuscript
fn parse_cidr(text: String) -> Result[String, NetworkError]
```

## parse_ip {data-api-kind="Function"}

```manuscript
fn parse_ip(text: String) -> Result[String, NetworkError]
```

