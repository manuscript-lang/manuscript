import approve, Approved from "./gate.ms"

interface Named:
    fn name() String

impl Named for Approved:
    fn name() String:
        return "x"

fn main() Unit:
    return
