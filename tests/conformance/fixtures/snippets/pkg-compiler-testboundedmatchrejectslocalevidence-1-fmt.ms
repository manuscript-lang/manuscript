# conform: tags=control-flow,formatter,interfaces,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/match_bounds_test.go:146 TestBoundedMatchRejectsLocalEvidence
from "./domain.ms" import Shape, Tag

impl Tag for Shape:
    def tag() -> Int: return 0
