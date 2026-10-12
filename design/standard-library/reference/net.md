+++
title = "net"
+++

# @std/net.ms

Import each required symbol with `import Name from "@std/net.ms"`.

## Connection

Kind: interface.

```text
Connection: Connection
operation close: fn()->Unit
operation local_address: fn()->String
operation peer_address: fn()->String
operation read: fn(max_bytes: Int)->Result[Optional[Bytes], IoError]
operation read_timeout: fn(max_bytes: Int, timeout: Duration)->Result[Optional[Bytes], IoError]
operation shutdown_write: fn()->Result[Unit, NetworkError]
operation tls_info: fn()->Result[TlsInfo, TlsError]
operation write: fn(data: Bytes)->Result[Unit, IoError]
operation write_timeout: fn(data: Bytes, timeout: Duration)->Result[Unit, IoError]
```

## Datagram

Kind: record.

```text
Datagram: Datagram
field data: Bytes
field sender: String
```

## DatagramSocket

Kind: interface.

```text
DatagramSocket: DatagramSocket
operation address: fn()->String
operation close: fn()->Unit
operation receive: fn(max_bytes: Int)->Result[Datagram, NetworkError]
operation receive_timeout: fn(max_bytes: Int, timeout: Duration)->Result[Datagram, NetworkError]
operation send: fn(data: Bytes, address: String)->Result[Unit, NetworkError]
operation send_timeout: fn(data: Bytes, address: String, timeout: Duration)->Result[Unit, NetworkError]
```

## DnsRecord

Kind: record.

```text
DnsRecord: DnsRecord
field kind: String
field value: String
field priority: Int
field weight: Int
field port: Int
```

## Listener

Kind: interface.

```text
Listener: Listener
operation accept: fn()->Result[Connection & Shareable, NetworkError]
operation accept_timeout: fn(timeout: Duration)->Result[Connection & Shareable, NetworkError]
operation address: fn()->String
operation close: fn()->Unit
```

## NetworkError

Kind: alternative.

```text
NetworkError: NetworkError
implements: Error
case InvalidInput
case InvalidData
case LimitExceeded
case PermissionDenied
case Unsupported
case Closed
case Timeout
case Failed(message: String)
operation message: fn()->String
```

## contains_ip

Kind: fn.

```text
contains_ip: fn(cidr: String, address: String)->Result[Bool, NetworkError]
```

## parse_cidr

Kind: fn.

```text
parse_cidr: fn(text: String)->Result[String, NetworkError]
```

## parse_ip

Kind: fn.

```text
parse_ip: fn(text: String)->Result[String, NetworkError]
```

