package msruntime

import (
	"testing"
)

func TestTypedIPAddressPolicy(t *testing.T) {
	for _, tc := range []struct{ input, text, family string }{
		{"192.0.2.1", "192.0.2.1", "IPv4"},
		{"2001:0db8::1", "2001:db8::1", "IPv6"},
		{"::ffff:192.0.2.1", "192.0.2.1", "IPv4"},
	} {
		address := librarySuccess(t, libraryCall(t, "net/parse_ip", tc.input))
		if got := httpTestCall("net/ip_text", address); got != tc.text {
			t.Fatal(got, tc)
		}
		if got := httpTestCall("net/ip_family", address).(Alternative); got.Tag != tc.family {
			t.Fatal(got, tc)
		}
	}
	for _, input := range []string{"", "999.1.1.1", "192.168.001.1", "fe80::1%eth0", "[::1]"} {
		libraryFailure(t, libraryCall(t, "net/parse_ip", input), "InvalidData")
	}
	if _, ok := nativeLibraryMember(Alternative{"local/IpFamily", "IPv4", nil}, "text", ""); ok {
		t.Fatal("local family acquired native member")
	}
}
