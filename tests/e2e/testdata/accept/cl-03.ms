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
    let customer = Customer(CustomerId("c1"), "Ada")
    if not (customer_name(customer) == "c1: Ada"):
        return panic("check failed")
