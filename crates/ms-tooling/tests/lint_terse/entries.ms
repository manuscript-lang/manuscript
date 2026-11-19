type Item:
    sku: String
    qty: Int

fn apply(var stock: Map[String, Int], items: List[Item]) Void:
    for item in items:
        stock[item.sku.clone()] = stock.get(item.sku).get() - item.qty
    for item in items:
        stock[item.sku.clone()] = stock.get_or(item.sku, 0) + item.qty

export fn main() Int:
    var stock = Map[String, Int]()
    apply(stock, [])
    return 0
