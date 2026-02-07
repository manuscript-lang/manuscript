import { ceil } from "std/math"
import { race, resolve, sleep } from "std/concurrency"

type Person
    name: string
    age: number

    fn say_hello(): string
        "Hello, {name}"

type Hello[T]
    name: T
    age: number = 10
    p: Person = Person("John", 20)

    // Say hello to the user from a method
    fn say_hello(): string
        "Hello, {name}" 

    fn say_hello_to_person(person: string): string
        "Hello, {person} from {name}"

fn hello(name: string): string
    "Hello, " + name

let user = Hello[string]("World")
print(user.name)
print(user.age)
print(user.say_hello())
print(user.p.say_hello())

let p = Person("John", 20)
hello("asda")
let a  = [1,2,3]
let i = 1

ceil(0.1)

fn make_stream2(): Stream[number]
    yield 100
    sleep(1000)
    yield 200

fn sub_main()
    let p2 = spawn make_stream2()
    var out2: list[number] = []
    for x in s
        print(x)

fn main()
  sub_main()
  
main()