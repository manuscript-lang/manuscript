import (
	Data from "@std/core.ms",

	msstd_net_cidr_text,
	msstd_net_contains_ip,
	msstd_net_ip_address_family,
	msstd_net_ip_address_text,
	msstd_net_parse_cidr,
	msstd_net_parse_ip from "@std/internal/net.ms",
)

// Supported DNS query categories; unknown spellings are rejected by checking.
export enum DnsKind:
	A  // IPv4 address records for the queried name.
	AAAA  // IPv6 address records for the queried name.
	CNAME  // Canonical name alias records for the queried name.
	MX  // Mail exchange records with priority values.
	NS  // Name server records for the queried zone.
	TXT  // Text records returned as string values.
	PTR  // Reverse address pointer records for an IP.
	SRV  // Service location records with priority, weight and port.

impl DnsKind:
	// Returns the uppercase wire category.
	fn text() String:
		match self:
			A: return "A"
			AAAA: return "AAAA"
			CNAME: return "CNAME"
			MX: return "MX"
			NS: return "NS"
			TXT: return "TXT"
			PTR: return "PTR"
			SRV: return "SRV"

// Numeric address families reported by IP values and host interfaces.
export enum IpFamily:
	IPv4  // A four-byte numeric address.
	IPv6  // A sixteen-byte numeric address.

impl IpFamily:
	// Returns IPv4 or IPv6.
	fn text() String:
		match self:
			IPv4: return "IPv4"
			IPv6: return "IPv6"

// A validated numeric IPv4/IPv6 address without a port or zone.
export extern type IpAddress

impl Data for IpAddress:

impl IpAddress:
	// Returns canonical text; mapped IPv6 input is normalized to IPv4.
	fn text() String:
		return msstd_net_ip_address_text(self)

	// Returns the normalized address family.
	fn family() IpFamily:
		if msstd_net_ip_address_family(self): return IPv6
		return IPv4

// A validated, masked numeric CIDR range.
export extern type Cidr

impl Data for Cidr:

impl Cidr:
	// Returns the canonical masked prefix without reparsing.
	fn text() String:
		return msstd_net_cidr_text(self)

// DNS record data returned by a typed lookup.
export type DnsRecord:
	// The same typed category used by the query.
	kind: DnsKind
	// The record's answer: an IP address for A and AAAA, the target host name for
	// CNAME, MX, NS, PTR, and SRV, or the text for TXT.
	value: String
	// The preference of an MX record or the priority of an SRV record, where lower
	// values are tried first; 0 for other kinds.
	priority: Int
	// The relative weight of an SRV record among targets with the same priority; 0 for
	// other kinds.
	weight: Int
	// The service port of an SRV record; 0 for other kinds.
	port: Int

// Reports whether an IP address belongs to a CIDR range.
export fn contains_ip(cidr: Cidr, address: IpAddress) Bool!:
	return msstd_net_contains_ip(cidr, address)

// Validates and canonicalizes an IPv4 or IPv6 CIDR range.
export fn parse_cidr(text: String) Cidr!:
	return msstd_net_parse_cidr(text)

// Validates and canonicalizes an IPv4 or IPv6 address.
export fn parse_ip(text: String) IpAddress!:
	return msstd_net_parse_ip(text)
