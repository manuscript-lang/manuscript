// conform: tags=control-flow,diagnostics,tier-core
// conform: phase=check
// conform: origin=range operator a..b
export fn main() Int {
    for i in 0..2..4 {
        return i
    }
    return 0
}
// expect-error: MS1000 5:18-5:20 a range cannot chain; write one 'start..end', or use range_by for a step from "@std/collections/collections.ms"
