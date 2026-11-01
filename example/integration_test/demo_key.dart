/// A demo-only RSA-2048 public key.
///
/// Its private key was never saved, so nothing sealed with it can ever be
/// opened, which is fine for a demo. In a real app, use your project's
/// public key from the SealedTrace console.
const String demoPublicKeyPem = '''
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAx6iP1pBdFBkr5okCe9mi
LzM8YzZBiSMpxMOPQMJleuOnFkAMdHp3hMzcUHyV96yY8eLKWaz8Lis0tEIpXwkC
QrKEu5SJCSvX5O9612QCxBpf7DaGmN3xO9S4DVEM1M1DfEviziRrIuqQT3oZiCAe
sBn23kRo84hKvrNN6Iir8uVSKCE/eSvyg5nOGygABojlkO6E7yd5cmdndiNwGl/x
Nt4k1QmluC1uv0Al5nJWo6NDlLzwHqqK2uFq746KJ1vcWzgQv9uzNNL0dKNaGlXl
bFzinWeIQiDPf93gnlGci+S+S2cDSO732l5Zf6gYDQ9JGGOAfWVHnxIQtdUGGUjl
aQIDAQAB
-----END PUBLIC KEY-----
''';
