# conform: tags=control-flow,diagnostics,interfaces,modules,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/match_bounds_test.go:146 TestBoundedMatchRejectsLocalEvidence
from "./domain.ms" import Shape, Tag

impl Tag for Shape:
    def tag() -> Int: return 0
