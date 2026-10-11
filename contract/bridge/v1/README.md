# Bridge contract v1

`spec.json` describes the HTTP contract currently shared by the macOS app and
the Safari/Chromium/Firefox WebExtension. `fixtures.json` contains synthetic,
non-secret examples used by compatibility tests and future implementations.

The contract intentionally records current behavior; it does not claim that an
extension marker is strong authentication. Security hardening that changes the
wire format must be introduced as a new contract version or through a backward-
compatible negotiation period.

Run the dependency-free contract suite from the repository root:

```sh
npm test
```

Future bridge implementations must consume these fixtures in their native test
suite in addition to the repository-level compatibility checks.
