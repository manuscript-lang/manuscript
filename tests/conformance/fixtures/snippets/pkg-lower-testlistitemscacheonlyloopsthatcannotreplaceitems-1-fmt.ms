# conform: tags=aliasing,formatter,lists,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/lower/list_items_test.go:22 TestListItemsCacheOnlyLoopsThatCannotReplaceItems
def grow(values: List[Int]) -> Unit:
    values.append(0)

def work(other: List[Int]) -> Int:
    var values = [1, 2, 3, 4]
    var total = 0
