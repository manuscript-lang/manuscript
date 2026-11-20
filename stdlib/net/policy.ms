import Cidr, IpAddress, contains_ip, parse_cidr, parse_ip from "@std/net/ip.ms"

// Network restriction policy: which hosts, addresses and listeners a derived network
// may reach. Every decision is a pure function of the policy and the text it is given,
// so a client can ask it before each connection, including every redirect hop. An empty
// policy (no levels) allows everything.

// One `restrict` call: the host names and CIDR ranges it allows, and whether it permits
// listening.
export type Level:
	hosts: List[String]
	prefixes: List[String]
	listen: Bool

// The restrictions of a derived network. A request must pass every level, so a derived
// network can only narrow its parent.
export type Policy:
	levels: List[Level]

// Returns the policy that allows everything.
export fn unrestricted() Policy:
	return Policy(levels: [])

// Lower-cases a host name and drops one trailing dot.
export fn fold_host(name: String) String:
	folded := name.lower()
	if folded.ends_with("."): return folded.cut_suffix(".").get_or(folded)

	return folded

// Returns `parent` narrowed to `hosts` and `cidrs`; invalid CIDR text is an error. With
// `allow_listen`, the network may listen inside the CIDRs, provided every ancestor
// allows it too.
export fn narrow(
	parent: Policy,
	hosts: List[String],
	cidrs: List[String],
	allow_listen: Bool,
) Policy!:
	var prefixes: List[String] = []
	for text in cidrs: prefixes.append(parse_cidr(text)?.to_string())

	var folded: List[String] = []
	for name in hosts: folded.append(fold_host(name))

	var levels = parent.levels.clone()
	levels.append(Level(hosts: folded, prefixes: prefixes, listen: allow_listen))
	return ok(Policy(levels: levels))

// Prefixes are stored as the canonical text of a validated range.
fn in_prefix(prefix: String, address: IpAddress) Bool:
	parsed := parse_cidr(prefix)
	if parsed.is_error(): return false

	return contains_ip(parsed.get(), address).get_or(false)

fn Level.allows_host(name: String) Bool:
	var allowed = self.hosts.contains(name)
	parsed := parse_ip(name)
	if parsed.is_ok():
		for prefix in self.prefixes:
			if in_prefix(prefix, parsed.get()): allowed = true
	return allowed

fn Level.allows_address(address: IpAddress) Bool:
	var allowed = self.prefixes.is_empty() and not self.hosts.is_empty()
	for prefix in self.prefixes:
		if in_prefix(prefix, address): allowed = true
	return allowed

// Reports whether a host name or literal address may be dialed.
export fn host_allowed(policy: Policy, name: String) Bool:
	folded := fold_host(name)
	for level in policy.levels:
		if not level.allows_host(folded): return false
	return true

// Reports whether a resolved address, as IP text, may be used. Text that is not an IP
// address is refused.
export fn address_allowed(policy: Policy, text: String) Bool:
	if policy.levels.is_empty(): return true

	parsed := parse_ip(text)
	if parsed.is_error(): return false

	for level in policy.levels:
		if not level.allows_address(parsed.get()): return false
	return true

// Reports whether `address` (`host:port`) may be listened on: every level must permit
// listening, and the host must be an IP literal inside the allowed ranges.
export fn listen_allowed(policy: Policy, host: String) Bool:
	if policy.levels.is_empty(): return true

	for level in policy.levels:
		if not level.listen: return false
	return address_allowed(policy, host)
