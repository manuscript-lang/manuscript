//go:build ms_lean

package msruntime

func HttpExchangeHeadersRead(ctx *Execution, receiver Value) Value {
	Panic(leanUnavailable)
	return Panic(leanUnavailable)
}

func HttpExchangeMethodRead(ctx *Execution, receiver Value) Value {
	Panic(leanUnavailable)
	return Panic(leanUnavailable)
}

func HttpExchangePathRead(ctx *Execution, receiver Value) string { Panic(leanUnavailable); return "" }

func HttpExchangeQueryRead(ctx *Execution, receiver Value) string { Panic(leanUnavailable); return "" }

func ResponseBodyMetadataRead(ctx *Execution, receiver Value) Value {
	Panic(leanUnavailable)
	return Panic(leanUnavailable)
}

func WebSocketSubprotocolRead(ctx *Execution, receiver Value) string {
	Panic(leanUnavailable)
	return ""
}

func ConnectionLocalAddressRead(ctx *Execution, receiver Value) string {
	Panic(leanUnavailable)
	return ""
}

func ConnectionPeerAddressRead(ctx *Execution, receiver Value) string {
	Panic(leanUnavailable)
	return ""
}

func ListenerAddressRead(ctx *Execution, receiver Value) string { Panic(leanUnavailable); return "" }

func DatagramSocketAddressRead(ctx *Execution, receiver Value) string {
	Panic(leanUnavailable)
	return ""
}

func HttpServerAddressRead(ctx *Execution, receiver Value) string { Panic(leanUnavailable); return "" }
