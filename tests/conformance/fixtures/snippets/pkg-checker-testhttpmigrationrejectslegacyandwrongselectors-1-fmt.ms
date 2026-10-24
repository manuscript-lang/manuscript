# conform: tags=formatter,modules,parser,stdlib-http,stdlib-net,tier-io
# conform: phase=parse
# conform: origin=pkg/checker/http_migration_test.go:9 TestHTTPMigrationRejectsLegacyAndWrongSelectors
from "@std/http.ms" import HttpMethod, HttpHeaders, headers
from "@std/net.ms" import network, DnsKind, IpFamily, IpAddress, Cidr
