# Canonical standard-library declarations. Implementations are native.

import Error from "@std/errors.ms"
import List from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"

export type UrlError:
    case InvalidInput
    case InvalidData
    case LimitExceeded

export type QueryEntry:
    key: String
    value: String

export type Url:
    scheme: String
    host: String
    port: Optional[Int]
    path: String
    query: String
    fragment: String

export fn decode_component(text: String) -> Result[String, UrlError]

export fn encode_component(text: String) -> String

export fn format(value: Url) -> Result[String, UrlError]

export fn format_query(entries: List[QueryEntry]) -> String

export fn parse(text: String) -> Result[Url, UrlError]

export fn parse_query(text: String, max_entries: Optional[Int] = none) -> Result[List[QueryEntry], UrlError]

export fn resolve(base: Url, reference: String) -> Result[Url, UrlError]

impl Error for UrlError:
    fn message() -> String
