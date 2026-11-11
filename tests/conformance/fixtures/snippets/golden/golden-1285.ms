// conform: tags=diagnostics
// conform: phase=check
fn entries(values: List[Int]) List[ListEntry[Int]]: values.entries()
fn pairs(values: Map[String, Int]) List[MapEntry[String, Int]]: values.entries()
fn cut(values: List[Int]) Result[List[Int], CollectionError]: values.slice(0, 1)
