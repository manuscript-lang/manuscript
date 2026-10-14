package msruntime

import (
	"net"
	"net/netip"
)

// Immutable validated data; these contain no resource handle or reparsing work.
type libraryIPAddress struct{ address netip.Addr }
type libraryCidr struct{ prefix netip.Prefix }

func libraryParseIP(_ *Execution, result string, args []Value) Value {
	ip := net.ParseIP(args[0].(string))
	if ip == nil {
		return libraryError(result, "InvalidData", "")
	}
	if v4 := ip.To4(); v4 != nil {
		ip = v4
	}
	address, _ := netip.AddrFromSlice(ip)
	return libraryOK(result, libraryIPAddress{address})
}

func init() {
	libraryAdd("net", "ip_text", "String", []LibraryParam{{"address", "IpAddress"}}, func(_ *Execution, _ string, args []Value) Value { return args[0].(libraryIPAddress).address.String() })
	libraryAdd("net", "ip_family", "IpFamily", []LibraryParam{{"address", "IpAddress"}}, func(_ *Execution, _ string, args []Value) Value {
		family := "IPv6"
		if args[0].(libraryIPAddress).address.Is4() {
			family = "IPv4"
		}
		return Alternative{"@std/IpFamily", family, nil}
	})
	libraryAdd("net", "cidr_text", "String", []LibraryParam{{"cidr", "Cidr"}}, func(_ *Execution, _ string, args []Value) Value { return args[0].(libraryCidr).prefix.String() })
	libraryAdd("net", "dns_kind_text", "String", []LibraryParam{{"kind", "DnsKind"}}, func(_ *Execution, _ string, args []Value) Value { return args[0].(Alternative).Tag })
	libraryAdd("net", "ip_family_text", "String", []LibraryParam{{"family", "IpFamily"}}, func(_ *Execution, _ string, args []Value) Value { return args[0].(Alternative).Tag })
}
