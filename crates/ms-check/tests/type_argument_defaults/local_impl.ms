interface Mark:
    fn mark() Int

type Value:
    number: Int

fn read[T: Mark = Value](value: T) Int: return value.mark()

type Holder[T: Mark = Value]:
    value: T

interface Factory:
    fn create[T: Mark = Value](value: T) Int

impl Mark for Value:
    fn mark() Int: return self.number

impl Value:
    fn read[T: Mark = Value](value: T) Int: return value.mark()

interface Relation[T]:
    fn relation(value: T) Int

impl Relation[Value] for Value:
    fn relation(value: Value) Int: return value.number

fn related[T: Relation[T] = Value](value: T) Int:
    return value.relation(value)

interface KeyReader[A: Hashable]:
    fn read[B = Map[A, Int]](value: B) Int

fn keys[T = Map[String, Value]](value: T) T: return value
