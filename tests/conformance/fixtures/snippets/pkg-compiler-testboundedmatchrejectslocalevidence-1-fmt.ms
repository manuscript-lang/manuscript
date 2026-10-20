# conform: tags=control-flow,formatter,interfaces,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/match_bounds_test.go:146 TestBoundedMatchRejectsLocalEvidence
import {Shape, Tag} from "./domain.ms"
impl Tag for Shape:
    fn tag() Int: return 0
