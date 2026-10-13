# Canonical standard-library declarations. Implementations are native.

import List from "@std/collections.ms"

# Errors returned for malformed URL text, components, or query limits.
export type UrlError:
    case InvalidInput
    case InvalidData
    case LimitExceeded

# One decoded key and value in a URL query string.
export type QueryEntry:
    key: String
    value: String

# Parsed URL components. A missing port is represented by `none`.
export type Url:
    scheme: String
    host: String
    port: Optional[Int]
    path: String
    query: String
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
    fn message() -> String:
