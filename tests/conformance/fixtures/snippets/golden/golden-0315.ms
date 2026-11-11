// conform: tags=diagnostics
// conform: phase=check
interface Shape:
    fn area() Int
type Sq:
    s: Int
impl Shape for Sq:
    fn area() Int: self.s * self.s
