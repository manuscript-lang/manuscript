import panic from "@std/faults.ms"

type CustomerId:
    value: String

type OrderId:
    value: String

type Customer:
    id: CustomerId
    name: String

fn customer_name(customer: Customer) String:
    let {id: {value}, name: display_name} = customer
    return "{value}: {display_name}"

test "nominal record and nested binding":
    let customer = Customer(id: CustomerId("c1"), name: "Ada")
    if not (customer_name(customer: customer) == "c1: Ada"):
        return panic(message: "check failed")
