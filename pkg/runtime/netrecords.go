package msruntime

// Constructors the lowerer calls for standard records: fields in declaration
// order, omitted fields already defaulted by the caller.

// NewDatagram builds a Datagram.
func NewDatagram(data *Bytes, sender string) *Datagram {
	return &Datagram{Data: data, Sender: sender}
}

// NewDnsRecord builds a DnsRecord.
func NewDnsRecord(kind DnsKind, value string, priority int, weight int, port int) *DnsRecord {
	return &DnsRecord{Kind: kind, Value: value, Priority: priority, Weight: weight, Port: port}
}

// NewHttpResponseMetadata builds a HttpResponseMetadata.
func NewHttpResponseMetadata(status int, headers *HttpHeaders, protocol string) *HttpResponseMetadata {
	return &HttpResponseMetadata{Status: status, Headers: headers, Protocol: protocol}
}

// NewClientResponse builds a ClientResponse.
func NewClientResponse(head *HttpResponseMetadata, body *Bytes) *ClientResponse {
	return &ClientResponse{Head: head, Body: body}
}

// NewHttpClientOptions builds a HttpClientOptions.
func NewHttpClientOptions(maxRedirects Option[int], maxIdleConnections Option[int], maxHeaderBytes Option[int], idleTimeout Option[Duration], decompress bool, cookies bool, tls *TlsOptions) *HttpClientOptions {
	return &HttpClientOptions{MaxRedirects: maxRedirects, MaxIdleConnections: maxIdleConnections, MaxHeaderBytes: maxHeaderBytes, IdleTimeout: idleTimeout, Decompress: decompress, Cookies: cookies, Tls: tls}
}

// NewHttpRequest builds a HttpRequest.
func NewHttpRequest(method HttpMethod, path string, query string, headers *HttpHeaders, body *Bytes, protocol string) *HttpRequest {
	return &HttpRequest{Method: method, Path: path, Query: query, Headers: headers, Body: body, Protocol: protocol}
}

// NewHttpResponse builds a HttpResponse.
func NewHttpResponse(status int, headers *HttpHeaders, body *Bytes) *HttpResponse {
	return &HttpResponse{Status: status, Headers: headers, Body: body}
}

// NewHttpServerOptions builds a HttpServerOptions.
func NewHttpServerOptions(maxRequests Option[int], maxBodyBytes Option[int], maxResponseBytes Option[int], maxHeaderBytes Option[int], timeout Option[Duration], grace Option[Duration], tls Option[*TlsOptions]) *HttpServerOptions {
	return &HttpServerOptions{MaxRequests: maxRequests, MaxBodyBytes: maxBodyBytes, MaxResponseBytes: maxResponseBytes, MaxHeaderBytes: maxHeaderBytes, Timeout: timeout, Grace: grace, Tls: tls}
}

// NewCertificateInfo builds a CertificateInfo.
func NewCertificateInfo(subject string, issuer string, dnsNames *List[string], notBefore Timestamp, notAfter Timestamp, der *Bytes) *CertificateInfo {
	return &CertificateInfo{Subject: subject, Issuer: issuer, DnsNames: dnsNames, NotBefore: notBefore, NotAfter: notAfter, Der: der}
}

// NewTlsInfo builds a TlsInfo.
func NewTlsInfo(version int, cipherSuite int, alpn string, peerCertificates *List[*Bytes], verified bool) *TlsInfo {
	return &TlsInfo{Version: version, CipherSuite: cipherSuite, Alpn: alpn, PeerCertificates: peerCertificates, Verified: verified}
}

// NewTlsOptions builds a TlsOptions.
func NewTlsOptions(serverName string, rootsPem string, certificatePem string, privateKeyPem string, alpn *List[string], requireClientCertificate bool) *TlsOptions {
	return &TlsOptions{ServerName: serverName, RootsPem: rootsPem, CertificatePem: certificatePem, PrivateKeyPem: privateKeyPem, Alpn: alpn, RequireClientCertificate: requireClientCertificate}
}

// NewQueryEntry builds a QueryEntry.
func NewQueryEntry(key string, value string) *QueryEntry {
	return &QueryEntry{Key: key, Value: value}
}

// NewUrl builds a Url.
func NewUrl(scheme string, host string, port Option[int], path string, query string, fragment string) *Url {
	return &Url{Scheme: scheme, Host: host, Port: port, Path: path, Query: query, Fragment: fragment}
}

// NewWebSocketMessage builds a WebSocketMessage.
func NewWebSocketMessage(data *Bytes, text bool) *WebSocketMessage {
	return &WebSocketMessage{Data: data, Text: text}
}

// NewWebSocketOptions builds a WebSocketOptions.
func NewWebSocketOptions(maxMessageBytes Option[int], timeout Option[Duration], tls *TlsOptions, compression bool) *WebSocketOptions {
	return &WebSocketOptions{MaxMessageBytes: maxMessageBytes, Timeout: timeout, Tls: tls, Compression: compression}
}
