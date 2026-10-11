# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"
import Duration from "@std/time.ms"
import IoError from "@std/io.ms"
import LibraryError from "@std/errors.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"
import TlsInfo from "@std/tls.ms"

export interface Connection:
    fn close() -> Unit
    fn local_address() -> String
    fn peer_address() -> String
    fn read(max_bytes: Int) -> Result[Optional[Bytes], IoError]
    fn read_timeout(max_bytes: Int, timeout: Duration) -> Result[Optional[Bytes], IoError]
    fn shutdown_write() -> Result[Unit, LibraryError]
    fn tls_info() -> Result[TlsInfo, LibraryError]
    fn write(data: Bytes) -> Result[Unit, IoError]
    fn write_timeout(data: Bytes, timeout: Duration) -> Result[Unit, IoError]

export type Datagram:
    data: Bytes
    sender: String

export interface DatagramSocket:
    fn address() -> String
    fn close() -> Unit
    fn receive(max_bytes: Int) -> Result[Datagram, LibraryError]
    fn receive_timeout(max_bytes: Int, timeout: Duration) -> Result[Datagram, LibraryError]
    fn send(data: Bytes, address: String) -> Result[Unit, LibraryError]
    fn send_timeout(data: Bytes, address: String, timeout: Duration) -> Result[Unit, LibraryError]

export type DnsRecord:
    kind: String
    value: String
    priority: Int
    weight: Int
    port: Int

export interface Listener:
    fn accept() -> Result[Connection & Shareable, LibraryError]
    fn accept_timeout(timeout: Duration) -> Result[Connection & Shareable, LibraryError]
    fn address() -> String
    fn close() -> Unit

export fn contains_ip(cidr: String, address: String) -> Result[Bool, LibraryError]

export fn parse_cidr(text: String) -> Result[String, LibraryError]

export fn parse_ip(text: String) -> Result[String, LibraryError]
