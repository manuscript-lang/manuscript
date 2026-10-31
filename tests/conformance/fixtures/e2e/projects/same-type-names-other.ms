# conform: tags=alternatives,diagnostics,match,records,tier-core
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/same_type_names/other.ms
export type Point:
    x: Int

export type Mode:
    case Off
    case On

export fn shifted() Int:
    return Point(10).x + 1

export fn flip() Int:
    match Mode.Off:
        Mode.Off: return 2
        _: return 0
