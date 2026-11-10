import (
	msstd_url_encode_component,
	msstd_url_decode_component,
	msstd_url_format,
	msstd_url_format_query,
	msstd_url_parse,
	msstd_url_parse_query,
	msstd_url_resolve
) from "@std/internal/net.ms"

// One decoded key and value in a URL query string.
export type QueryEntry:
	// Decoded query key; duplicate keys retain separate entries in input order.
	key: String
	// Decoded query value; a bare key has an empty value and plus decodes as a space.
	value: String

// Parsed URL components. A missing port is represented by `none`.
export type Url:
	// URL scheme, lowercased during parsing; native parse rejects missing schemes and opaque URLs.
	scheme: String
	// Lowercased hostname, excluding the port and IPv6 brackets; user information is rejected.
	host: String
	// Explicit numeric port in 0..65535, or none when the input has no port.
	port: Int?
	// Escaped path text, retaining escaped separators; format validates its percent escapes and UTF-8.
	path: String
	// Encoded query contents without the leading question mark; parse_query decodes individual entries.
	query: String
	// Decoded fragment contents without the leading hash mark.
	fragment: String

// Decodes one percent-encoded URL component. `+` is not treated as a space.
export fn decode_component(text: String) String!:
	return msstd_url_decode_component(text)

// Percent-encodes one URL component using UTF-8 bytes.
export fn encode_component(text: String) String:
	return msstd_url_encode_component(text)

// Formats URL components as an absolute hierarchical URL.
// Missing or malformed schemes and hostless relative paths return EINVAL, as do other invalid components.
export fn format(value: Url) String!:
	return msstd_url_format(value)

// Encodes query entries as a query string.
export fn format_query(entries: List[QueryEntry]) String:
	return msstd_url_format_query(entries)

// Parses an absolute URL into its components.
export fn parse(text: String) Url!:
	return msstd_url_parse(text)

// Parses a query string, preserving duplicate keys and their input order.
export fn parse_query(text: String, max_entries: Int?) List[QueryEntry]!:
	return msstd_url_parse_query(text, max_entries)

// Resolves a relative reference against a base URL.
export fn resolve(base: Url, reference: String) Url!:
	return msstd_url_resolve(base, reference)
