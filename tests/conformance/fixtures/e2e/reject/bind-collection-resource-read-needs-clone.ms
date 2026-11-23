// conform: tags=diagnostics,ownership,tier-core
// conform: phase=check
// A binding of `xs.get(i)` or `m.get(k)` over a resource would own what the collection keeps: read it in place.
import bind_datagram, DatagramSocket from "@std/net/net.ms"

fn from_list(var sockets: List[DatagramSocket]) Int:
	first := sockets.get(0)
	return first.address.length()

fn from_map(var sockets: Map[String, DatagramSocket]) Bool:
	found := sockets.get("a")
	return found.is_some()

fn in_place(var sockets: Map[String, DatagramSocket]) Int:
	if found := sockets.get("a"):
		return found.address.length()
	return 0
