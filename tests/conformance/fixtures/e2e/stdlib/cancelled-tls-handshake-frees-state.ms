// conform: tags=scope-cleanup,stdlib-net,tier-io
// conform: phase=run
// A TLS handshake, dial or accept cancelled while it waits unwinds out of its native, which owns the TLS context
// and a connection it has not handed over yet. Both must be released on the way, or every cancelled handshake leaks
// them (the leak check runs this fixture with the process-exit frees kept).
import (
	PromiseOptions, cancel_switch, promise from "@std/concurrency/promise.ms",
	Listener, accept_tls, connect, listen, start_tls from "@std/net/net.ms",
	TlsOptions from "@std/net/tls.ms",
	milliseconds, seconds, sleep from "@std/time.ms",
)

// The fixed test identity of support/certificates.ms, inlined so the leak check can run this file alone.
fn certificate() String:
	return "-----BEGIN CERTIFICATE-----\nMIIBUjCCAQSgAwIBAgIBATAFBgMrZXAwFjEUMBIGA1UEAxMLc3RkbGliLnRlc3Qw\nIBcNMjAwMTAxMDAwMDAwWhgPMjEwMDAxMDEwMDAwMDBaMBYxFDASBgNVBAMTC3N0\nZGxpYi50ZXN0MCowBQYDK2VwAyEAe8MHlRjtEdoDNghb9pYpIP+H+zxNYwqbWMth\nU2dPXdajdTBzMA4GA1UdDwEB/wQEAwIChDATBgNVHSUEDDAKBggrBgEFBQcDATAP\nBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBSXj3k9f25C8HSLlIZ2z/wi62CYtDAc\nBgNVHREEFTATggtzdGRsaWIudGVzdIcEfwAAATAFBgMrZXADQQCy10RiI9QU8YqP\nfHjTXEQP3dcOGFmJe/XvuCKA7zvgv1bryG9K95Hh1ci9ZlIuTYmx/LyutoNFvr82\nncADBsAL\n-----END CERTIFICATE-----\n"

fn private_key() String:
	return "-----BEGIN PRIVATE KEY-----\nMC4CAQAwBQYDK2VwBCIEIDAxMjM0NTY3ODkwMTIzNDU2Nzg5MDEyMzQ1Njc4OTAx\n-----END PRIVATE KEY-----\n"

// Connects and upgrades to TLS against a peer that never answers the hello.
fn upgrade_silent(address: String) Void!:
	var plain = connect(address, timeout: seconds(5)).wait()?
	options := TlsOptions(server_name: "stdlib.test", roots_pem: certificate())
	void start_tls(plain, options, seconds(30))?

// Accepts a connection and waits for a hello that never comes.
fn serve_silent(listener: Listener) Void!:
	var plain = listener.accept(seconds(5)).wait()?
	options := TlsOptions(certificate_pem: certificate(), private_key_pem: private_key())
	void accept_tls(plain, options, seconds(30))?

fn main() Void!:
	silent := listen("127.0.0.1:0")?
	address := silent.address()

	for round in 0..6:
		stop := cancel_switch()
		client := promise(fn: upgrade_silent(address.clone()), options: PromiseOptions(cancel: stop.signal()))
		void sleep(milliseconds(20 + round * 5)).wait()?
		stop.cancel()
		void client.wait()

	other := listen("127.0.0.1:0")?
	where := other.address()
	for round in 0..6:
		stop := cancel_switch()
		server := promise(fn: serve_silent(other), options: PromiseOptions(cancel: stop.signal()))
		var raw = connect(where.clone(), timeout: seconds(5)).wait()?
		void sleep(milliseconds(20 + round * 5)).wait()?
		stop.cancel()
		void server.wait()
		raw.close()?

	print("done")
