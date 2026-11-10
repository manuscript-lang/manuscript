// conform: tags=maps,assignment,tier-core
// conform: phase=run
// conform: origin=compound assignment on a Map with a name or field key borrows the key for the read

type Stock:
    levels: Map[String, Int]

type Line:
    sku: String
    qty: Int

export fn main() Int:
    var stock = Stock(levels: {"a": 10, "b": 1})
    let lines = [Line(sku: "a", qty: 2), Line(sku: "b", qty: 3), Line(sku: "a", qty: 1)]
    for line in lines:
        stock.levels[line.sku] -= line.qty
    let key = "a".clone()
    stock.levels[key] *= 2
    stock.levels[key] += 1
    var counts = {1: 0}
    let slot = 1
    counts[slot] += 4
    counts[slot] -= 1
    print("{stock.levels["a"]} {stock.levels["b"]} {counts[1]} {key}")
    return 0
