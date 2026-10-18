package checker_test

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"testing"
)

func TestHTTPMigrationRejectsLegacyAndWrongSelectors(t *testing.T) {
	prefix := `import {HttpMethod, HttpHeaders, headers} from "@std/http.ms"
import {network, DnsKind, IpFamily, IpAddress, Cidr} from "@std/net.ms"
`
	for name, body := range map[string]string{
		"method String":              `network().request(method: "GET", url: "http://127.0.0.1:1", headers: headers(), body: "".to_bytes())`,
		"header Map":                 `network().request(method: HttpMethod.Get, url: "http://127.0.0.1:1", headers: Map[String, String](), body: "".to_bytes())`,
		"DNS String":                 `network().resolve(name: "localhost", kind: "A")`,
		"DNS wrong family":           `network().resolve(name: "localhost", kind: IpFamily.IPv4)`,
		"invalid method case":        `let method = HttpMethod.GTE`,
		"invalid DNS case":           `let kind = DnsKind.ANY`,
		"opaque header constructor":  `let fields = HttpHeaders()`,
		"opaque address constructor": `let address = IpAddress()`,
		"opaque prefix constructor":  `let prefix = Cidr()`,
	} {
		t.Run(name, func(t *testing.T) {
			result := compiler.CompileSource("migration.ms", prefix+"fn check() Unit:\n    "+body+"\n", compiler.Options{})
			if result.Success() {
				t.Fatal("legacy or malformed migration input accepted")
			}
		})
	}
}
