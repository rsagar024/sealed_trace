// TEST-ONLY KEYS. Generated with OpenSSL for this repository's tests and the
// golden vectors. The private key is public by design: it must never be used
// to protect real data.

/// RSA-2048 public key in SPKI form (`BEGIN PUBLIC KEY`).
const String testPublicKeySpki = '''
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqLwVJtCCEmYZsJqGL+an
ZgvZpj8/r5VlpSMrOvlwomrG+sNKfMFPjPYuodAXGpoF+D8nj9HerAVsTVBPgt+7
ZmhVnCPCzVavDctGPKANMswcl5Aq30tmdAdVXmMmS6kVjJJNolh/Rijq9fiCAI7p
/cuVoCqaeUk3b9m1vQqwZk00RjSaHkxX+PeUm2bQFmlQT1Ndb+D3PCGXWRJ/lNB7
oommc7hhcxmQJ+mtpuITUMkK+UYHJV4GLV9U030t2cItEUe+FOobMcE65+oMvJar
LMj/ZkFDQ4+5H6tsrYXyIKpkNY4JViGaLzqXzNnXDj/sumpR43h2uJGktRI24YOo
ewIDAQAB
-----END PUBLIC KEY-----
''';

/// The same key in PKCS#1 form (`BEGIN RSA PUBLIC KEY`).
const String testPublicKeyPkcs1 = '''
-----BEGIN RSA PUBLIC KEY-----
MIIBCgKCAQEAqLwVJtCCEmYZsJqGL+anZgvZpj8/r5VlpSMrOvlwomrG+sNKfMFP
jPYuodAXGpoF+D8nj9HerAVsTVBPgt+7ZmhVnCPCzVavDctGPKANMswcl5Aq30tm
dAdVXmMmS6kVjJJNolh/Rijq9fiCAI7p/cuVoCqaeUk3b9m1vQqwZk00RjSaHkxX
+PeUm2bQFmlQT1Ndb+D3PCGXWRJ/lNB7oommc7hhcxmQJ+mtpuITUMkK+UYHJV4G
LV9U030t2cItEUe+FOobMcE65+oMvJarLMj/ZkFDQ4+5H6tsrYXyIKpkNY4JViGa
LzqXzNnXDj/sumpR43h2uJGktRI24YOoewIDAQAB
-----END RSA PUBLIC KEY-----
''';

/// The matching private key in PKCS#8 form. TEST ONLY.
const String testPrivateKeyPkcs8 = '''
-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQCovBUm0IISZhmw
moYv5qdmC9mmPz+vlWWlIys6+XCiasb6w0p8wU+M9i6h0BcamgX4PyeP0d6sBWxN
UE+C37tmaFWcI8LNVq8Ny0Y8oA0yzByXkCrfS2Z0B1VeYyZLqRWMkk2iWH9GKOr1
+IIAjun9y5WgKpp5STdv2bW9CrBmTTRGNJoeTFf495SbZtAWaVBPU11v4Pc8IZdZ
En+U0HuiiaZzuGFzGZAn6a2m4hNQyQr5RgclXgYtX1TTfS3Zwi0RR74U6hsxwTrn
6gy8lqssyP9mQUNDj7kfq2ythfIgqmQ1jglWIZovOpfM2dcOP+y6alHjeHa4kaS1
Ejbhg6h7AgMBAAECggEAHc3bDpgV4ZoXP5KL0To0p1nAgBT78s+4vIqRwED/HDEw
JGsKZS7gFk4Fvp869X/vPgIpwsWXR1tN3fopkTxjpZsYRBQs/IgrM4yMQ3kh268h
/cOBTx/KYQRKl/l7cjHTlJjjDaIEGShxGDFlBSQ5QJMNQtVDo9jC6gbSiymwLuF6
mPDaarric9TVv1aJ2zG3xxTKn+hH8Ne2kMj2egzGDaTzLb2nua8Pj+nVeuv/lcYN
aTq+DbrZ8F0g9yYHPVJqCIexcGSsdau+x06QYMDfi/WbBj5FMwD6lu8x8EAuK87u
5Eb3ocU68lcQHxJEqR73eA5mGRN+dRkqn1NmTR//QQKBgQDevwcLfDSZW5XbBuB4
iAz88jxjDM2MeXp5Q1TKwGHabcSkdik5dJOq/xFx1QR9aQMtU1w1WJ/ATiyPhczw
lbugmhL1fuXNsueax33/V/Yl+tXVNPCU9Gp88eqdVicnObxd0Ah+vQ5npHBa38bM
FI/78pa4lHEzVxmehRZO7PgXrwKBgQDB7NRQ/I6yFP5wa70o/Qg5VsvtXjwcibFk
T205oOCP/dvP3PzmuefhSkBRpwTOTY2JGOgQ8u/+gL6u6tBMDX+TH5f9qM/T5rJA
WL2eTcbnoaXfzVP3WRfXsPyWvWesYk41Yr0B0v8Z9cfiNWGDBw2EWgH9/IyrZTFD
Y91aDjxi9QKBgFbOEyzCpqztKCVHNMtEGeupayceoiwQW05OkwjAmGHLTUraUY52
g+WrqVy3KxzEg9xyFAkmFHuY+3yjJA7OC2S3JpRNc7kJ84A6JjwQR3jdm9+O1gL2
jVlL3aabIH8E3QeiPu1FOAvj5XVEp/B4QvRowZwFHWholS9Vpi/z4Ws5AoGALmBt
8iREF/CPXOFXLos8wUGxqUWlCIohY0TfcS25JpZmUBKgZKlG/Aje0ugnbRL86zGK
pisDHBE8CObdA6MixFOE7MPHV/zO2jaeulINZG2zFo+rKfcjjZClB4OqXH5yB7Bi
VSJZoaK2t7FebZBtOh6wZUZVedPMcTpbwGKxLFUCgYB9anN2IhoK1dJzx5XSHOPp
nkSgEXtZILKQpTB5/XraJxfp1f5BbH4jDvPDZSvDUV2QJlLsVvHIOxtBuARTXmFk
qa01/Il+uCP4F9o+WphnMvfq4wN8ZmHHYgULK9gLrb6qIx+j15vqEYweq/2JbYDW
o91eiopLcaqdsOVX+bs7Cg==
-----END PRIVATE KEY-----
''';

/// A 1024-bit RSA public key, which the SDK must reject.
const String testPublicKey1024 = '''
-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC+AyA27QS2vxML80x1BVmfTTY8
tg9BKWAjDy1Va9ypm76jPRBFqhvD8tri32ldAvFJ5HkK1WqeK6erqAILD+En5Nc1
dHCZTnfk2fKAg3hG9pmExzIqmyF7P/rrCe/7PGDFdAXXVNbvv07a7BbON3ZUfcJb
wICTj/WaDhYB+CneFwIDAQAB
-----END PUBLIC KEY-----
''';

/// A 3072-bit RSA public key, which the SDK must reject.
const String testPublicKey3072 = '''
-----BEGIN PUBLIC KEY-----
MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAvHnoV4kLX/HFGl/9VDHG
FxJCfq/epd3MqlfILr8FC5fdjlNHiST4EDxuzTc4ICAluCo018+20Bq5T2MOy9aJ
oxVmG6AJuZfv21zk97SIp6NNMfsG+9vNwXpFH0pXgK8QWQUYD6pjin1hHVW0J1uj
ixKxfisXOs8bGrm1glNjZgsZzwLdM7MF5iCsXyPTVWSDeu6M1ywIamd53hARp3i5
PiyQqmYX8mRMaXP2KoH9AR0CnI6YgX2uIzHXj4V1lMHAqgRBGzo2sBAa7M6pV5wH
zzwweIU9yIoxoJrs4j5kVvr0XdrEhyd7QA1d/FA61vJHbfS9S0/fQn6X2qK0kVsU
bp1pQ+4PpAUu7Y4PPjuZtR8/Xj84UQQ9JWbvNWdXXBa72aQSrPn9Z1OwNa2ZeO/N
F/2Mp9OaS2NMFMRtuwGsCpXcP6tnDJW3CDT35SLuhLQuwGa254YPg/TY/YaQYFlj
dZEELKQBX2K5+oDQuou6rA3cxH+yWRJTpGI1LW7I2mr5AgMBAAE=
-----END PUBLIC KEY-----
''';

/// A P-256 elliptic-curve public key, which the SDK must reject.
const String testPublicKeyEc = '''
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE8daJJ/rwPKkOmI6jo6zmXvcnoOoy
50EIe5Xqh1DUtxADrcravyP9eqACDk60dwKXAPZ6w4Do/lVgjtxXuEVvVQ==
-----END PUBLIC KEY-----
''';
