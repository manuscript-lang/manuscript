# conform: tags=control-flow,diagnostics,interfaces,modules,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/match_bounds_test.go:146 TestBoundedMatchRejectsLocalEvidence
import {Shape, Tag} from "./domain.ms"

impl Tag for Shape:
    fn tag() Int: return 0
