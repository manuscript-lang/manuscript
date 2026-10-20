# conform: tags=diagnostics,modules,stdlib-http,stdlib-net,tier-io
# conform: phase=check
# conform: origin=pkg/checker/http_migration_test.go:9 TestHTTPMigrationRejectsLegacyAndWrongSelectors
import {HttpMethod, HttpHeaders, headers} from "@std/http.ms"
import {network, DnsKind, IpFamily, IpAddress, Cidr} from "@std/net.ms"
