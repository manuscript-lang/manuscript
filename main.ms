type Hello
    name: string

    fn say_hello(): string
        "Hello, {name}" 

fn hello(name: string): string
    "Hello, " + name

let user = Hello(name: "World")
print(user.name)
print(user.say_hello())

let a  = [1,2,3]
