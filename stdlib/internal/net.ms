import Bytes from "@std/bytes.ms"
import IoError from "@std/io/io.ms"
import (
    CertificateInfo,
    Cidr,
    Connection,
    Datagram,
    IpAddress,
    NativeConnection,
    NativeDatagramSocket,
    NativeListener,
    NativeWebSocket,
    Network,
    NetworkError,
    QueryEntry,
    TlsError,
    TlsInfo,
    Url,
    UrlError,
    WebSocketError,
    WebSocketMessage
) from "@std/net/net.ms"
import Duration, Timestamp from "@std/os/time.ms"

export extern fn msrt_url_encode_component(text: String) String

export extern fn msrt_net_ip_address_text(value: IpAddress) String

export extern fn msrt_net_ip_address_family(value: IpAddress) Bool

export extern fn msrt_net_cidr_text(value: Cidr) String

export extern fn msrt_net_contains_ip(cidr: Cidr, address: IpAddress) Bool!NetworkError

export extern fn msrt_net_parse_cidr(text: String) Cidr!NetworkError

export extern fn msrt_net_parse_ip(text: String) IpAddress!NetworkError

export extern fn msrt_net_network() Network

export extern fn msrt_tls_parse_certificates(
    pem: String,
    max_certificates: Int?
) List[CertificateInfo]!TlsError

export extern fn msrt_tls_verify_certificates(
    chain_pem: String,
    roots_pem: String,
    server_name: String,
    now: Timestamp
) Unit!TlsError

export extern fn msrt_url_decode_component(text: String) String!UrlError

export extern fn msrt_url_format(value: Url) String!UrlError

export extern fn msrt_url_format_query(entries: List[QueryEntry]) String

export extern fn msrt_url_parse(text: String) Url!UrlError

export extern fn msrt_url_parse_query(
    text: String,
    max_entries: Int?
) List[QueryEntry]!UrlError

export extern fn msrt_url_resolve(base: Url, reference: String) Url!UrlError

export extern fn msrt_net_connection_close(handle: NativeConnection) Unit

export extern fn msrt_net_connection_local_address(handle: NativeConnection) String

export extern fn msrt_net_connection_peer_address(handle: NativeConnection) String

export extern fn msrt_net_connection_read(
    handle: NativeConnection,
    max_bytes: Int?,
    timeout: Duration?
) Bytes?!IoError

export extern fn msrt_net_connection_clone(
    handle: NativeConnection
) Connection!NetworkError

export extern fn msrt_net_connection_shutdown_write(
    handle: NativeConnection
) Unit!NetworkError

export extern fn msrt_net_connection_tls_info(handle: NativeConnection) TlsInfo!TlsError

export extern fn msrt_net_connection_write(
    handle: NativeConnection,
    data: String,
    timeout: Duration?
) Unit!IoError

export extern fn msrt_net_connection_write_bytes(
    handle: NativeConnection,
    data: Bytes,
    timeout: Duration?
) Unit!IoError

export extern fn msrt_net_datagram_address(handle: NativeDatagramSocket) String

export extern fn msrt_net_datagram_close(handle: NativeDatagramSocket) Unit

export extern fn msrt_net_datagram_receive(
    handle: NativeDatagramSocket,
    max_bytes: Int?,
    timeout: Duration?
) Datagram!NetworkError

export extern fn msrt_net_datagram_send(
    handle: NativeDatagramSocket,
    data: String,
    address: String,
    timeout: Duration?
) Unit!NetworkError

export extern fn msrt_net_datagram_send_bytes(
    handle: NativeDatagramSocket,
    data: Bytes,
    address: String,
    timeout: Duration?
) Unit!NetworkError

export extern fn msrt_net_listener_accept(
    handle: NativeListener,
    timeout: Duration?
) Connection!NetworkError

export extern fn msrt_net_listener_accept_raw(
    handle: NativeListener,
    timeout: Duration?
) Int!NetworkError

export extern fn msrt_net_listener_address(handle: NativeListener) String

export extern fn msrt_net_listener_close(handle: NativeListener) Unit

export extern fn msrt_websocket_close(handle: NativeWebSocket) Unit

export extern fn msrt_websocket_ping(
    handle: NativeWebSocket,
    data: String
) Unit!WebSocketError

export extern fn msrt_websocket_ping_bytes(
    handle: NativeWebSocket,
    data: Bytes
) Unit!WebSocketError

export extern fn msrt_websocket_receive(
    handle: NativeWebSocket
) WebSocketMessage?!WebSocketError

export extern fn msrt_websocket_send(
    handle: NativeWebSocket,
    data: String
) Unit!WebSocketError

export extern fn msrt_websocket_send_bytes(
    handle: NativeWebSocket,
    data: Bytes,
    text: Bool
) Unit!WebSocketError

export extern fn msrt_websocket_subprotocol(handle: NativeWebSocket) String
