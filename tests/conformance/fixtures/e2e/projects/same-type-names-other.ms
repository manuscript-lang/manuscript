# conform: tags=alternatives,diagnostics,match,records,tier-core
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/same_type_names/other.ms
export type Point:
    x: Int

export type Mode:
    case Off
    case On

export def shifted() -> Int:
    return Point(10).x + 1

export def flip() -> Int:
    match Mode.Off:
        case Mode.Off: return 2
        case _: return 0
