+++
title = "net"
+++

# @std/net.ms

Import each required symbol with `import Name from "@std/net.ms"`.

## Connection

Kind: interface.

```manuscript
Connection: Connection
operation close: fn()->Unit
operation local_address: fn()->String
operation peer_address: fn()->String
operation read: fn(max_bytes: Int)->Result[Optional[Bytes], IoError]
operation read_timeout: fn(max_bytes: Int, timeout: Duration)->Result[Optional[Bytes], IoError]
operation shutdown_write: fn()->Result[Unit, LibraryError]
operation tls_info: fn()->Result[TlsInfo, LibraryError]
operation write: fn(data: Bytes)->Result[Unit, IoError]
operation write_timeout: fn(data: Bytes, timeout: Duration)->Result[Unit, IoError]
```

## Datagram

Kind: record.

```manuscript
Datagram: Datagram
field data: Bytes
field sender: String
```

## DatagramSocket

Kind: interface.

```manuscript
DatagramSocket: DatagramSocket
operation address: fn()->String
operation close: fn()->Unit
operation receive: fn(max_bytes: Int)->Result[Datagram, LibraryError]
operation receive_timeout: fn(max_bytes: Int, timeout: Duration)->Result[Datagram, LibraryError]
operation send: fn(data: Bytes, address: String)->Result[Unit, LibraryError]
operation send_timeout: fn(data: Bytes, address: String, timeout: Duration)->Result[Unit, LibraryError]
```

## DnsRecord

Kind: record.

```manuscript
DnsRecord: DnsRecord
field kind: String
field value: String
field priority: Int
field weight: Int
field port: Int
```

## Listener

Kind: interface.

```manuscript
Listener: Listener
operation accept: fn()->Result[Connection & Shareable, LibraryError]
operation accept_timeout: fn(timeout: Duration)->Result[Connection & Shareable, LibraryError]
operation address: fn()->String
operation close: fn()->Unit
```

## contains_ip

Kind: fn.

```manuscript
contains_ip: fn(cidr: String, address: String)->Result[Bool, LibraryError]
```

## parse_cidr

Kind: fn.

```manuscript
parse_cidr: fn(text: String)->Result[String, LibraryError]
```

## parse_ip

Kind: fn.

```manuscript
parse_ip: fn(text: String)->Result[String, LibraryError]
```

