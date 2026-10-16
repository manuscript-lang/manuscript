# Errors returned for malformed URL text, components, or query limits.
export type UrlError:
    # Constructed URL components or a supplied query-entry budget are invalid.
    case InvalidInput
    # URL text, escaped bytes, port syntax or a relative reference is invalid or unsupported.
    case InvalidData
    # The decoded query has more entries than its supplied budget permits.
    case LimitExceeded

# One decoded key and value in a URL query string.
export type QueryEntry:
    # Decoded query key; duplicate keys retain separate entries in input order.
    key: String
    # Decoded query value; a bare key has an empty value and plus decodes as a space.
    value: String

# Parsed URL components. A missing port is represented by `none`.
export type Url:
    # URL scheme, lowercased during parsing; native parse rejects missing schemes and opaque URLs.
    scheme: String
    # Lowercased hostname, excluding the port and IPv6 brackets; user information is rejected.
    host: String
    # Explicit numeric port in 0..65535, or none when the input has no port.
    port: Optional[Int]
    # Escaped path text, retaining escaped separators; format validates its percent escapes and UTF-8.
    path: String
    # Encoded query contents without the leading question mark; parse_query decodes individual entries.
    query: String
    # Decoded fragment contents without the leading hash mark.
    fragment: String

# Decodes one percent-encoded URL component. `+` is not treated as a space.
export fn decode_component(text: String) -> Result[String, UrlError]:

# Percent-encodes one URL component using UTF-8 bytes.
export fn encode_component(text: String) -> String:

# Formats URL components as an absolute or relative URL.
export fn format(value: Url) -> Result[String, UrlError]:

# Encodes query entries as a query string.
export fn format_query(entries: List[QueryEntry]) -> String:

# Parses an absolute URL into its components.
export fn parse(text: String) -> Result[Url, UrlError]:

# Parses a query string, preserving duplicate keys and their input order.
export fn parse_query(
    text: String,
    max_entries: Optional[Int] = none
) -> Result[List[QueryEntry], UrlError]:

# Resolves a relative reference against a base URL.
export fn resolve(base: Url, reference: String) -> Result[Url, UrlError]:

impl Error for UrlError:
    # Returns a URL-prefixed diagnostic without echoing addresses, query values or credentials.
    fn message() -> String:
