# conform: tags=alternatives,closures,formatter,generics,interfaces,optional,parser,records,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/checker/documentation_test.go:89 TestDocumentationUsesManuscriptDeclarations
type Optional[T]:
    case some(value: T)
    case none

impl Optional[T]:
    fn is_some() Bool:
    fn is_none() Bool:
    fn get(default: Optional[T] = none) T:
    fn map[U](transform: fn(value: T) U) Optional[U]:
    fn and_then[U](transform: fn(value: T) Optional[U]) Optional[U]:
    fn or_else(create: fn() Optional[T]) Optional[T]:
    fn ok_or[E: Error = MissingValue](cause: Optional[E] = none) Result[T, E]:
    fn ok_or_else[E: Error](create: fn() E) Result[T, E]:
