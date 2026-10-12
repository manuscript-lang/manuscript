# Canonical standard-library declarations. Implementations are native.

import List from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"
import Error from "@std/errors.ms"

export type HtmlError:
    case InvalidInput
    case InvalidData
    case LimitExceeded

export type HtmlLimits:
    max_bytes: Optional[Int] = none
    max_depth: Optional[Int] = none
    max_nodes: Optional[Int] = none

export type HtmlAttribute:
    name: String
    namespace: String
    value: String

export type HtmlNode:
    case Document(children: List[HtmlNode])
    case Element(tag: String, namespace: String, attributes: List[HtmlAttribute], children: List[HtmlNode])
    case Text(text: String)
    case Comment(text: String)
    case Doctype(name: String, public_id: String, system_id: String)

export fn escape(text: String) -> String

export fn parse(text: String, limits: Optional[HtmlLimits] = none) -> Result[HtmlNode, HtmlError]

impl Error for HtmlError:
    fn message() -> String
