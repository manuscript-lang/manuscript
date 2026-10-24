# conform: tags=diagnostics,modules,stdlib-http,stdlib-net,tier-io
# conform: phase=check
# conform: origin=pkg/checker/http_migration_test.go:9 TestHTTPMigrationRejectsLegacyAndWrongSelectors
from "@std/http.ms" import HttpMethod, HttpHeaders, headers
from "@std/net.ms" import network, DnsKind, IpFamily, IpAddress, Cidr
