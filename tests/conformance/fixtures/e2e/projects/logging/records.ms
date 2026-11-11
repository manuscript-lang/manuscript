import Logger from "@std/log.ms"

type Request:
	request: String

type Payload:
	count: Int
	ok: Bool
	nested: List[Bool?]
	service: String
	level: Int
	msg: String
	time: Int

export fn emit(logger: Logger) Unit!:
	child := logger.child(Request("req-1"))?
	fields := Payload(
		count: 9007199254740993,
		ok: true,
		nested: [none, false],
		service: "worker",
		level: 0,
		msg: "spoofed",
		time: 0,
	)
	child.debug("filtered")?
	child.info("received \"payload\"\nnext", fields)?
	logger.warn("complete")?
