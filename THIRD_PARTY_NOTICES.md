# Third-party software

The application source and original icon in this repository are MIT licensed.
The SSH transport and device-identity approach is adapted from the author's
[Exocortex phone client](https://github.com/Yeyito777/exocortex-phone-client).

Swift Package Manager downloads the dependencies below; their source is not
vendored here. They retain their own copyright notices and licenses. The app's
MIT license does not replace those terms. Include the relevant upstream notices
when distributing compiled builds.

| Dependency | Upstream |
| --- | --- |
| Citadel | https://github.com/orlandos-nl/Citadel |
| Swift Crypto (including BoringSSL components) | https://github.com/apple/swift-crypto |
| SwiftNIO | https://github.com/apple/swift-nio |
| SwiftNIO SSH fork | https://github.com/Wellz26/swift-nio-ssh |
| BigInt | https://github.com/attaswift/BigInt |
| Swift Atomics | https://github.com/apple/swift-atomics |
| Swift Collections | https://github.com/apple/swift-collections |
| Swift System | https://github.com/apple/swift-system |
| Swift ASN.1 | https://github.com/apple/swift-asn1 |
| Swift Log | https://github.com/apple/swift-log |

Exact dependency versions/revisions are recorded in the committed SwiftPM
`Package.resolved`. Consult each resolved checkout's license files for its terms.
