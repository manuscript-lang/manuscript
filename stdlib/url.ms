# Canonical standard-library declarations. Implementations are native.

import LibraryError from "@std/errors.ms"
import List from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"

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

export fn decode_component(text: String) -> Result[String, LibraryError]

export fn encode_component(text: String) -> String

export fn format(value: Url) -> Result[String, LibraryError]

export fn format_query(entries: List[QueryEntry]) -> String

export fn parse(text: String) -> Result[Url, LibraryError]

export fn parse_query(text: String, max_entries: Int) -> Result[List[QueryEntry], LibraryError]

export fn resolve(base: Url, reference: String) -> Result[Url, LibraryError]
