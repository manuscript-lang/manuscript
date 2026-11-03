import Bytes from "@std/bytes.ms"
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
    QueryEntry,
    TlsInfo,
    Url,
    WebSocketMessage
) from "@std/net/net.ms"
import Duration, Timestamp from "@std/os/time.ms"

export extern fn msstd_url_encode_component(text: String) String

export extern fn msstd_net_ip_address_text(value: IpAddress) String

export extern fn msstd_net_ip_address_family(value: IpAddress) Bool

export extern fn msstd_net_cidr_text(value: Cidr) String

export extern fn msstd_net_contains_ip(cidr: Cidr, address: IpAddress) Bool!

export extern fn msstd_net_parse_cidr(text: String) Cidr!

export extern fn msstd_net_parse_ip(text: String) IpAddress!

export extern fn msstd_net_network() Network

export extern fn msstd_tls_parse_certificates(
    pem: String,
    max_certificates: Int?
) List[CertificateInfo]!

export extern fn msstd_tls_verify_certificates(
    chain_pem: String,
    roots_pem: String,
    server_name: String,
    now: Timestamp
) Unit!

export extern fn msstd_url_decode_component(text: String) String!

export extern fn msstd_url_format(value: Url) String!

export extern fn msstd_url_format_query(entries: List[QueryEntry]) String

export extern fn msstd_url_parse(text: String) Url!

export extern fn msstd_url_parse_query(
    text: String,
    max_entries: Int?
) List[QueryEntry]!

export extern fn msstd_url_resolve(base: Url, reference: String) Url!

export extern fn msstd_net_connection_close(handle: NativeConnection) Unit

export extern fn msstd_net_connection_local_address(handle: NativeConnection) String

export extern fn msstd_net_connection_peer_address(handle: NativeConnection) String

export extern fn msstd_net_connection_read(
    handle: NativeConnection,
    max_bytes: Int?,
    timeout: Duration?
) Bytes?!

export extern fn msstd_net_connection_clone(handle: NativeConnection) Connection!

export extern fn msstd_net_connection_shutdown_write(handle: NativeConnection) Unit!

export extern fn msstd_net_connection_tls_info(handle: NativeConnection) TlsInfo!

export extern fn msstd_net_connection_write(
    handle: NativeConnection,
    data: String,
    timeout: Duration?
) Unit!

export extern fn msstd_net_connection_write_bytes(
    handle: NativeConnection,
    data: Bytes,
    timeout: Duration?
) Unit!

export extern fn msstd_net_datagram_address(handle: NativeDatagramSocket) String

export extern fn msstd_net_datagram_close(handle: NativeDatagramSocket) Unit

export extern fn msstd_net_datagram_receive(
    handle: NativeDatagramSocket,
    max_bytes: Int?,
    timeout: Duration?
) Datagram!

export extern fn msstd_net_datagram_send(
    handle: NativeDatagramSocket,
    data: String,
    address: String,
    timeout: Duration?
) Unit!

export extern fn msstd_net_datagram_send_bytes(
    handle: NativeDatagramSocket,
    data: Bytes,
    address: String,
    timeout: Duration?
) Unit!

export extern fn msstd_net_listener_accept(
    handle: NativeListener,
    timeout: Duration?
) Connection!

export extern fn msstd_net_listener_accept_raw(
    handle: NativeListener,
    timeout: Duration?
) Int!

export extern fn msstd_net_listener_raw_owner(handle: NativeListener) Int

export extern fn msstd_net_release_unadopted(owner: Int) Unit

export extern fn msstd_net_listener_address(handle: NativeListener) String

export extern fn msstd_net_listener_close(handle: NativeListener) Unit

export extern fn msstd_websocket_close(handle: NativeWebSocket) Unit

export extern fn msstd_websocket_ping(handle: NativeWebSocket, data: String) Unit!

export extern fn msstd_websocket_ping_bytes(handle: NativeWebSocket, data: Bytes) Unit!

export extern fn msstd_websocket_receive(handle: NativeWebSocket) WebSocketMessage?!

export extern fn msstd_websocket_send(handle: NativeWebSocket, data: String) Unit!

export extern fn msstd_websocket_send_bytes(
    handle: NativeWebSocket,
    data: Bytes,
    text: Bool
) Unit!

export extern fn msstd_websocket_subprotocol(handle: NativeWebSocket) String
