//go:build !ms_lean

package msruntime

func (e *libraryHTTPExchange) ReadAccessor(ctx *Execution, name string) Value {
	switch name {
	case "headers":
		return HttpExchangeHeadersRead(ctx, e)
	case "method":
		return HttpExchangeMethodRead(ctx, e)
	case "path":
		return HttpExchangePathRead(ctx, e)
	case "query":
		return HttpExchangeQueryRead(ctx, e)
	}
	return Panic("unknown HttpExchange accessor")
}
func (b *libraryResponseBody) ReadAccessor(ctx *Execution, name string) Value {
	switch name {
	case "metadata":
		return ResponseBodyMetadataRead(ctx, b)
	}
	return Panic("unknown ResponseBody accessor")
}
func (w *libraryWebSocket) ReadAccessor(ctx *Execution, name string) Value {
	switch name {
	case "subprotocol":
		return WebSocketSubprotocolRead(ctx, w)
	}
	return Panic("unknown WebSocket accessor")
}
func (c *libraryConnection) ReadAccessor(ctx *Execution, name string) Value {
	switch name {
	case "local_address":
		return ConnectionLocalAddressRead(ctx, c)
	case "peer_address":
		return ConnectionPeerAddressRead(ctx, c)
	}
	return Panic("unknown Connection accessor")
}
func (l *libraryListener) ReadAccessor(ctx *Execution, name string) Value {
	switch name {
	case "address":
		return ListenerAddressRead(ctx, l)
	}
	return Panic("unknown Listener accessor")
}
func (d *libraryDatagram) ReadAccessor(ctx *Execution, name string) Value {
	switch name {
	case "address":
		return DatagramSocketAddressRead(ctx, d)
	}
	return Panic("unknown DatagramSocket accessor")
}
func (s *httpService) ReadAccessor(ctx *Execution, name string) Value {
	switch name {
	case "address":
		return HttpServerAddressRead(ctx, s)
	}
	return Panic("unknown HttpServer accessor")
}

func (*libraryHTTPExchange) accessorKind() string { return "HttpExchange" }

func (*libraryResponseBody) accessorKind() string { return "ResponseBody" }

func (*libraryWebSocket) accessorKind() string { return "WebSocket" }

func (*libraryConnection) accessorKind() string { return "Connection" }

func (*libraryListener) accessorKind() string { return "Listener" }

func (*libraryDatagram) accessorKind() string { return "DatagramSocket" }

func (*httpService) accessorKind() string { return "HttpServer" }

func HttpExchangeHeadersRead(ctx *Execution, receiver Value) Value {
	CheckCancelled(ctx)
	v := ContractReceiver(receiver).(*libraryHTTPExchange).headers
	CheckCancelled(ctx)
	return v
}

func HttpExchangeMethodRead(ctx *Execution, receiver Value) Value {
	CheckCancelled(ctx)
	v := libraryHTTPMethod(ContractReceiver(receiver).(*libraryHTTPExchange).request.Method)
	CheckCancelled(ctx)
	return v
}

func HttpExchangePathRead(ctx *Execution, receiver Value) string {
	CheckCancelled(ctx)
	v := ContractReceiver(receiver).(*libraryHTTPExchange).request.URL.Path
	CheckCancelled(ctx)
	return v
}

func HttpExchangeQueryRead(ctx *Execution, receiver Value) string {
	CheckCancelled(ctx)
	v := ContractReceiver(receiver).(*libraryHTTPExchange).request.URL.RawQuery
	CheckCancelled(ctx)
	return v
}

func ResponseBodyMetadataRead(ctx *Execution, receiver Value) Value {
	CheckCancelled(ctx)
	v := ContractReceiver(receiver).(*libraryResponseBody).metadata
	CheckCancelled(ctx)
	return v
}

func WebSocketSubprotocolRead(ctx *Execution, receiver Value) string {
	CheckCancelled(ctx)
	v := ContractReceiver(receiver).(*libraryWebSocket).conn.Subprotocol()
	CheckCancelled(ctx)
	return v
}

func ConnectionLocalAddressRead(ctx *Execution, receiver Value) string {
	CheckCancelled(ctx)
	v := ContractReceiver(receiver).(*libraryConnection).conn.LocalAddr().String()
	CheckCancelled(ctx)
	return v
}

func ConnectionPeerAddressRead(ctx *Execution, receiver Value) string {
	CheckCancelled(ctx)
	v := ContractReceiver(receiver).(*libraryConnection).conn.RemoteAddr().String()
	CheckCancelled(ctx)
	return v
}

func ListenerAddressRead(ctx *Execution, receiver Value) string {
	CheckCancelled(ctx)
	v := ContractReceiver(receiver).(*libraryListener).listener.Addr().String()
	CheckCancelled(ctx)
	return v
}

func DatagramSocketAddressRead(ctx *Execution, receiver Value) string {
	CheckCancelled(ctx)
	v := ContractReceiver(receiver).(*libraryDatagram).conn.LocalAddr().String()
	CheckCancelled(ctx)
	return v
}

func HttpServerAddressRead(ctx *Execution, receiver Value) string {
	CheckCancelled(ctx)
	v := ContractReceiver(receiver).(*httpService).listener.Addr().String()
	CheckCancelled(ctx)
	return v
}
