import (
    Bytes from "@std/bytes.ms",
    Datagram,
    NativeConnection,
    NativeDatagramSocket,
    NativeListener,
    NativeNetwork,
    Listener,
    Network from "@std/net/net.ms",
    Cidr, DnsKind, DnsRecord, IpAddress from "@std/net/ip.ms",
    CertificateInfo, TlsInfo, TlsOptions from "@std/net/tls.ms",
    QueryEntry, Url from "@std/net/url.ms",
    NativeWebSocket, RawWebSocketMessage, WebSocketWire from "@std/net/websocket.ms",
    ClientResponse, HttpClient, HttpClientOptions, HttpHeaders from "@std/net/http.ms",
    Duration, Timestamp from "@std/time.ms",
)

export extern fn msstd_url_encode_component(text: String) String

export extern fn msstd_net_ip_address_text(value: IpAddress) String

export extern fn msstd_net_ip_address_family(value: IpAddress) Bool

export extern fn msstd_net_cidr_text(value: Cidr) String

export extern fn msstd_net_contains_ip(cidr: Cidr, address: IpAddress) Bool!

export extern fn msstd_net_parse_cidr(text: String) Cidr!

export extern fn msstd_net_parse_ip(text: String) IpAddress!

export extern fn msstd_net_network() NativeNetwork

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

export extern fn msstd_net_connection_share(handle: NativeConnection) NativeConnection

export extern fn msstd_net_connection_close_if_last(handle: NativeConnection) Unit

export extern fn msstd_net_connection_local_address(handle: NativeConnection) String

export extern fn msstd_net_connection_peer_address(handle: NativeConnection) String

export extern fn msstd_net_connection_read(
    handle: NativeConnection,
    max_bytes: Int?,
    timeout: Duration?
) Bytes?!

export extern fn msstd_net_connection_shutdown_write(handle: NativeConnection) Unit!

export extern fn msstd_net_connection_tls_info(handle: NativeConnection) TlsInfo!

export extern fn msstd_net_connection_write_bytes(
    handle: NativeConnection,
    data: Bytes,
    timeout: Duration?
) Unit!

export extern fn msstd_net_datagram_address(handle: NativeDatagramSocket) String

export extern fn msstd_net_datagram_close(handle: NativeDatagramSocket) Unit

export extern fn msstd_net_datagram_share(
    handle: NativeDatagramSocket
) NativeDatagramSocket

export extern fn msstd_net_datagram_close_if_last(handle: NativeDatagramSocket) Unit

export extern fn msstd_net_datagram_receive(
    handle: NativeDatagramSocket,
    max_bytes: Int?,
    timeout: Duration?
) Datagram!

export extern fn msstd_net_datagram_send_bytes(
    handle: NativeDatagramSocket,
    data: Bytes,
    address: String,
    timeout: Duration?
) Unit!

export extern fn msstd_net_listener_accept(
    handle: NativeListener,
    timeout: Duration?
) NativeConnection!

// Another handle on the same listener, for a promise that accepts on it; dropping it leaves the listener open.
export extern fn msstd_net_listener_share(handle: NativeListener) NativeListener

export extern fn msstd_net_listener_address(handle: NativeListener) String

export extern fn msstd_net_listener_close(handle: NativeListener) Unit

export extern fn msstd_websocket_close(handle: NativeWebSocket) Unit

export extern fn msstd_websocket_share(handle: NativeWebSocket) NativeWebSocket

export extern fn msstd_websocket_close_if_last(handle: NativeWebSocket) Unit

export extern fn msstd_websocket_ping(handle: NativeWebSocket, data: String) Unit!

export extern fn msstd_websocket_ping_bytes(handle: NativeWebSocket, data: Bytes) Unit!

export extern fn msstd_websocket_receive(handle: NativeWebSocket) RawWebSocketMessage?!

export extern fn msstd_websocket_send_bytes(
    handle: NativeWebSocket,
    data: Bytes,
    text: Bool
) Unit!

export extern fn msstd_websocket_subprotocol(handle: NativeWebSocket) String

export extern fn msstd_net_network_bind_datagram(
    net: NativeNetwork,
    address: String
) NativeDatagramSocket!

export extern fn msstd_net_network_close(net: NativeNetwork) Unit

export extern fn msstd_net_network_connect(
    net: NativeNetwork,
    address: String,
    timeout: Duration?
) NativeConnection!

export extern fn msstd_net_network_connect_tls_config(
    net: NativeNetwork,
    address: String,
    options: TlsOptions,
    timeout: Duration?
) NativeConnection!

export extern fn msstd_net_network_connect_unix(
    net: NativeNetwork,
    path: String,
    timeout: Duration?
) NativeConnection!

export extern fn msstd_net_network_http_client(
    net: NativeNetwork,
    options: HttpClientOptions
) HttpClient!

export extern fn msstd_net_network_listen(net: NativeNetwork, address: String) Listener!

export extern fn msstd_net_network_listen_tls(
    net: NativeNetwork,
    address: String,
    options: TlsOptions,
    handshake_timeout: Duration?
) Listener!

export extern fn msstd_net_network_listen_unix(
    net: NativeNetwork,
    path: String
) Listener!

export extern fn msstd_net_network_lookup(
    net: NativeNetwork,
    name: String,
    max_records: Int?,
    timeout: Duration?
) List[String]!

export extern fn msstd_net_network_request_bytes(
    net: NativeNetwork,
    method: String,
    url: String,
    headers: HttpHeaders,
    body: Bytes,
    max_response_bytes: Int?,
    timeout: Duration?
) ClientResponse!

export extern fn msstd_net_network_resolve(
    net: NativeNetwork,
    name: String,
    kind: DnsKind,
    max_records: Int?,
    timeout: Duration?
) List[DnsRecord]!

export extern fn msstd_net_network_restrict(
    net: NativeNetwork,
    hosts: List[String],
    cidrs: List[String],
    allow_listen: Bool
) Network!

export extern fn msstd_net_network_web_socket(
    net: NativeNetwork,
    url: String,
    headers: HttpHeaders,
    subprotocols: List[String],
    options: WebSocketWire
) NativeWebSocket!

export extern fn msstd_net_network_with_resolver(
    net: NativeNetwork,
    address: String
) Network!
