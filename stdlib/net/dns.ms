import (
	DnsKind, DnsRecord, IpAddress, parse_ip from "@std/net/ip.ms",
	Policy, host_allowed from "@std/net/policy.ms",
	Deadline, Duration, deadline_after from "@std/time.ms",

	msstd_dns_config, msstd_dns_query, msstd_net_lookup from "@std/internal/net.ms",
)

// Name resolution for a `Network`: the system resolver, or one DNS server, with the
// host's search list and `ndots` for names that are not absolute. The runtime answers
// one query to one server; the order of servers and candidate names, the limits and the
// policy checks live here.

// The host's resolver settings, as `msstd_dns_config` reports them.
export type DnsConfig:
	// The servers as `ip:53` text; the loopback pair when the host names none.
	servers: List[String]
	// The search suffixes, without a final dot.
	search: List[String]
	// The dots a name needs before it is tried as written ahead of the search list.
	ndots: Int

fn invalid() Error:
	return Error("network: invalid input", kind: "EINVAL")

fn denied() Error:
	return Error("network: permission denied", kind: "EACCES")

fn timed_out() Error:
	return Error("network: operation timed out", kind: "ETIMEDOUT")

fn cannot_resolve(name: String) Error:
	return Error(f"cannot resolve host \"{name}\"", kind: "EIO")

// The time budget of a call: none without a timeout, EINVAL for a negative one.
fn budget(timeout: Duration?) Deadline?!:
	if limit := timeout:
		if limit.to_nanoseconds() < 0: return error(invalid())
		return ok(deadline_after(limit))

	return ok(none)

fn time_left(deadline: Deadline?) Duration?:
	if found := deadline: return found.remaining()
	return none

fn expired(deadline: Deadline?) Bool:
	if found := deadline: return found.expired()
	return false

// The record limit of a call: none sets no limit, a negative one is EINVAL.
fn record_limit(max_records: Int?) Int?!:
	if count := max_records:
		if count < 0: return error(invalid())
	return ok(max_records)

fn over_limit(count: Int, max_records: Int?) Bool:
	if limit := max_records: return count > limit
	return false

// Names to try for `name`: an absolute name is exact; the others follow the search
// list, as written first when they have at least `ndots` dots.
fn candidates(name: String, config: DnsConfig) List[String]:
	if name.ends_with("."): return [name.clone()]

	absolute := name + "."
	var searched: List[String] = []
	for suffix in config.search: searched.append(f"{name}.{suffix}.")

	if name.split(".").length() - 1 >= config.ndots:
		var ordered = [absolute]
		for item in searched: ordered.append(item)
		return ordered

	searched.append(absolute)
	return searched

// The sixteen nibbles of an IPv6 address as text, from its canonical form.
fn v6_digits(text: String) String:
	var head: List[String] = []
	var tail: List[String] = []

	if parts := text.split_once("::"):
		if not parts.before.is_empty(): head = parts.before.split(":").clone()
		if not parts.after.is_empty(): tail = parts.after.split(":").clone()
	else:
		head = text.split(":").clone()

	var digits = ""
	for group in head: digits += group.pad_start(4, "0")
	for missing in 0..(8 - head.length() - tail.length()): digits += "0000"
	for group in tail: digits += group.pad_start(4, "0")
	return digits

// The reverse-lookup name of an address (`4.3.2.1.in-addr.arpa.`).
fn reverse_name(address: IpAddress) String:
	text := address.to_string()

	if not text.contains(":"):
		var octets = text.split(".").clone()
		octets.reverse()
		return octets.join(".") + ".in-addr.arpa."

	var nibbles: List[String] = []
	for digit in v6_digits(text).chars(): nibbles.append(digit.to_string())
	nibbles.reverse()
	return nibbles.join(".") + ".ip6.arpa."

// Tries the candidates in order, each against the servers in order, and returns the
// first answer. A server that does not answer is skipped; one that says the name has no
// such data ends that candidate.
fn query_servers(
	servers: List[String],
	names: List[String],
	kind: DnsKind,
	original: String,
	deadline: Deadline?,
) List[DnsRecord]!:
	var last = cannot_resolve(original)

	for name in names:
		var answered = false

		for server in servers:
			if answered: continue

			found := msstd_dns_query(
				server.clone(),
				name.clone(),
				kind,
				time_left(deadline),
			)

			if found.is_error():
				failure := found.err()
				if failure.kind == "ETIMEDOUT" and expired(deadline): return error(
					failure
				)

				last = failure
				continue

			if records := found.get(): return ok(records)

			answered = true

		if answered: last = cannot_resolve(original)

	return error(last)

// `localhost` and every name under it name the loopback interface (RFC 6761), so they
// need no lookup.
fn is_localhost(name: String) Bool:
	folded := name.lower().cut_suffix(".").get_or(name.lower())
	return folded == "localhost" or folded.ends_with(".localhost")

// The canonical text of an address, or none for text that is not one.
fn canonical(text: String) String?:
	parsed := parse_ip(text)
	if parsed.is_error(): return none

	return parsed.get().to_string()

// Whether an address text is in the family: 4 or 6, or 0 for either.
fn in_family(text: String, family: Int) Bool:
	if family == 0: return true
	return text.contains(":") == (family == 6)

fn unique(items: List[String], family: Int) List[String]:
	var kept: List[String] = []
	for text in items:
		if in_family(text, family) and not kept.contains(text): kept.append(text)
	return kept

// The addresses of `name` (`family` 4 or 6, or 0 for both) through one DNS server.
fn server_addresses(
	server: String,
	name: String,
	family: Int,
	deadline: Deadline?,
) List[String]!:
	config := msstd_dns_config()?
	names := candidates(name, config)
	var found: List[String] = []
	var last = cannot_resolve(name)
	var kinds: List[DnsKind] = []
	if family != 6: kinds.append(DnsKind.A)
	if family != 4: kinds.append(DnsKind.AAAA)

	for kind in kinds:
		answer := query_servers([server.clone()], names, kind, name, deadline)

		if answer.is_error():
			if answer.err().kind == "ETIMEDOUT": return error(answer.err())

			last = answer.err()
			continue

		for record in answer.get():
			if text := canonical(record.value): found.append(text)

	if found.is_empty(): return error(last)

	return ok(found)

// The addresses of `name`: through `resolver` (an `ip:port` DNS server) when it is not
// empty, else through the system resolver.
fn addresses(
	resolver: String,
	name: String,
	family: Int,
	deadline: Deadline?,
) List[String]!:
	if not resolver.is_empty(): return server_addresses(
		resolver,
		name,
		family,
		deadline,
	)

	// A literal and `localhost` need no lookup, so they need no wait either.
	if literal := canonical(name): return ok(unique([literal], family))
	if is_localhost(name): return ok(unique(["127.0.0.1", "::1"], family))

	// The system resolver matches host names exactly on some platforms, so ask in lower
	// case.
	found := msstd_net_lookup(name.lower(), 0, time_left(deadline))

	if found.is_error():
		if found.err().kind == "EIO": return error(cannot_resolve(name))
		return error(found.err())

	var texts: List[String] = []

	for entry in found.get():
		if parts := entry.rsplit_once(":"):
			host := parts.before.cut_prefix("[").get_or(parts.before)
			if text := canonical(host.cut_suffix("]").get_or(host)): texts.append(text)

	return ok(unique(texts, family))

// Resolves a host name to the text of its IPv4 and IPv6 addresses: an IP literal
// answers as written, and more than `max_records` addresses is EOVERFLOW.
export fn dns_lookup(
	policy: Policy,
	resolver: String,
	name: String,
	max_records: Int?,
	timeout: Duration?,
) List[String]!:
	limit := record_limit(max_records)?
	deadline := budget(timeout)?
	if not host_allowed(policy, name): return error(denied())

	var found: List[String] = [name.clone()]

	if parse_ip(name).is_error():
		found = addresses(resolver, name, 0, deadline)?
		if found.is_empty(): return error(cannot_resolve(name))

	if over_limit(found.length(), limit):
		return error(Error("network: limit exceeded", kind: "EOVERFLOW"))

	return ok(found)

// Looks up the records of one `kind` for `name`; address kinds follow `dns_lookup`, and
// the others ask `resolver` or the host's servers, a PTR for the reverse name of an IP
// literal.
export fn dns_resolve(
	policy: Policy,
	resolver: String,
	name: String,
	kind: DnsKind,
	max_records: Int?,
	timeout: Duration?,
) List[DnsRecord]!:
	limit := record_limit(max_records)?
	deadline := budget(timeout)?
	if not host_allowed(policy, name): return error(denied())

	var records: List[DnsRecord] = []

	if kind == DnsKind.A or kind == DnsKind.AAAA:
		var family = 4
		if kind == DnsKind.AAAA: family = 6
		for text in addresses(resolver, name, family, deadline)?:
			records.append(
				DnsRecord(
					kind: kind,
					value: text,
					priority: 0,
					weight: 0,
					port: 0,
				)
			)
	else:
		config := msstd_dns_config()?
		var servers = config.servers.clone()
		if not resolver.is_empty(): servers = [resolver]

		var names = candidates(name, config)

		if kind == DnsKind.PTR:
			address := parse_ip(name)
			if address.is_error(): return error(
				Error("unrecognized address", kind: "EIO")
			)

			names = [reverse_name(address.get())]

		records = query_servers(servers, names, kind, name, deadline)?

	if over_limit(records.length(), limit):
		return error(Error("network: limit exceeded", kind: "EOVERFLOW"))

	return ok(records)
