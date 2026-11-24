// conform: tags=formatter,modules,parser,stdlib-http,stdlib-net,tier-io
// conform: phase=parse
// conform: origin=pkg/checker/http_migration_test.go:9 TestHTTPMigrationRejectsLegacyAndWrongSelectors
import (
	HttpHeaders, HttpMethod, headers from "@std/net/http.ms",
	Cidr, DnsKind, IpAddress, IpFamily from "@std/net/ip.ms",
)
