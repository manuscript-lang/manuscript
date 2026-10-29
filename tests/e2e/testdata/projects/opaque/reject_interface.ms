import {Approved, Mode, approve, safe} from "./gate.ms"
import {parse, stringify} from "@std/json.ms"

interface Named:
    fn name() String

impl Named for Approved:
    fn name() String:
        return "x"

export fn main() Int:
    return 0
