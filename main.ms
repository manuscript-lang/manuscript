type Person
    name: string
    age: number

    fn say_hello(): string
        "Hello, {name}"

type Hello[T]
    name: T
    age: number = 10
    p: Person = Person("John", 20)

    fn say_hello(): string
        """
        Say hello to the user from a method
        """
        "Hello, {name}" 

    fn say_hello_to_person(person: string): string
        """
        Say hello to the person
        """
        "Hello, {person} from {name}"

fn hello(name: string): string
    """
    Say hello to the user
    """
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
