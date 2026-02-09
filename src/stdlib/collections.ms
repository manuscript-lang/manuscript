// std/collections - Collection operations

extern fn sort[T](list: list[T]): list[T]
extern fn keys[K, V](m: map[K, V]): list[K]
extern fn values[K, V](m: map[K, V]): list[V]
extern fn entries[K, V](m: map[K, V]): list[list[unknown]]

fn _min(a: number, b: number): number
  if a < b then a else b

fn first[T](list: list[T]): T?
  if len(list) > 0 then list[0] else null

fn last[T](list: list[T]): T?
  if len(list) > 0 then list[len(list) - 1] else null

fn take[T](list: list[T], n: number): list[T]
  let result: list[T] = []
  for i in 0.._min(n, len(list))
    result.push(list[i])
  result

fn drop[T](list: list[T], n: number): list[T]
  let result: list[T] = []
  for i in n..len(list)
    result.push(list[i])
  result

fn reverse[T](list: list[T]): list[T]
  let result: list[T] = []
  for i in 0..len(list)
    result.push(list[len(list) - 1 - i])
  result

fn contains[T](list: list[T], item: T): bool
  for x in list
    if x == item
      return true
  false

fn unique[T](list: list[T]): list[T]
  let seen = {}
  let result: list[T] = []
  for item in list
    let key = to_str(item)
    if not seen[key]
      seen[key] = true
      result.push(item)
  result

fn flatten[T](lists: list[list[T]]): list[T]
  let result: list[T] = []
  for list in lists
    for item in list
      result.push(item)
  result

fn zip[T, U](a: list[T], b: list[U]): list[list[unknown]]
  let result: list[list[unknown]] = []
  let n = _min(len(a), len(b))
  for i in 0..n
    result.push([a[i], b[i]])
  result

fn concat[T](...lists: list[list[T]]): list[T]
  let result: list[T] = []
  for list in lists
    for item in list
      result.push(item)
  result

fn range(start: number, end: number): list[number]
  let result: list[number] = []
  for i in start..end
    result.push(i)
  result

fn slice[T](list: list[T], start: number, end?: number): list[T]
  let e = end ?? len(list)
  let result: list[T] = []
  for i in start..e
    result.push(list[i])
  result

fn map[T, U](list: list[T], f: fn(T): U): list[U]
  let result: list[U] = []
  for item in list
    result.push(f(item))
  result

fn each[T](list: list[T], f: fn(T): void): void
  for item in list
    f(item)

fn filter[T](list: list[T], pred: fn(T): bool): list[T]
  let result: list[T] = []
  for item in list
    if pred(item)
      result.push(item)
  result

fn reduce[T, U](list: list[T], init: U, f: fn(U, T): U): U
  var acc = init
  for item in list
    acc = f(acc, item)
  acc

fn find[T](list: list[T], pred: fn(T): bool): T?
  for item in list
    if pred(item)
      return item
  null

fn any[T](list: list[T], pred: fn(T): bool): bool
  for item in list
    if pred(item)
      return true
  false

fn all[T](list: list[T], pred: fn(T): bool): bool
  for item in list
    if not pred(item)
      return false
  true

fn group_by[T, K](list: list[T], f: fn(T): K): map[K, list[T]]
  var result: map[K, list[T]] = {}
  for item in list
    let key = f(item)
    if not result[key]
      let newList: list[T] = []
      result[key] = newList
    result[key].push(item)
  result

type _By[K, T]
  key: K
  value: T

fn sort_by[T, K](list: list[T], f: fn(T): K): list[T]
  let pairs: list[_By[K, T]] = map(list, (item) => _By(key: f(item), value: item))
  let sorted = sort(pairs, (a, b) => if to_str(a.key) < to_str(b.key) then -1 else if to_str(a.key) > to_str(b.key) then 1 else 0)
  map(sorted, (p) => p.value)
