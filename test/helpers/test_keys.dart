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

/// The `kid` of [testPublicKeySpki] (I3), as computed by OpenSSL:
/// `openssl pkey -pubin -outform der | openssl dgst -sha256 -binary |
/// head -c 16 | base64url`.
const String testKeyId = 'i5AhdjEFUP1jG9OUOECv9Q';

/// A 1024-bit RSA public key, which the SDK must reject.
const String testPublicKey1024 = '''
-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC+AyA27QS2vxML80x1BVmfTTY8
tg9BKWAjDy1Va9ypm76jPRBFqhvD8tri32ldAvFJ5HkK1WqeK6erqAILD+En5Nc1
dHCZTnfk2fKAg3hG9pmExzIqmyF7P/rrCe/7PGDFdAXXVNbvv07a7BbON3ZUfcJb
wICTj/WaDhYB+CneFwIDAQAB
-----END PUBLIC KEY-----
''';

/// A 3072-bit RSA public key (I3: accepted since envelope v3).
const String testPublicKey3072 = '''
-----BEGIN PUBLIC KEY-----
MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAtoTAXIUEJnQEy5JlvlCd
Fi5sCh4PKVk8hKDs64r1KjRRF48O3c46XuQHgKDREL262YX1wHnttjUm0LpA7KBq
+uvwLbgX0i5K9qXUmqt9t4WtrRmJ+D90U0bDp5nVkphSxQG/9XFH0f6O8dQ87l9t
E8qOuUX2KwQFjkiLqaD8jBXLz7xm6FVG/Tcp/10tcd2pAvjprqJcIvjZzImF/8x5
aqN+rI5TIWJwygmhNmlEDfK863kMkLP19kbYuaydxHXW62kVqhmOsQhBo9cFcwu9
E/CIgeJS9woDg/Yp8kS/MvNI8fhW8qZCKXTU6vPrYaiS0FoM1RMYx/KMilj6XV0a
a6q/f3orpFkQSeQQnS0GN4Hq8D89UzIKjDhkytjdbSX5ycILIyukHUAFFvFcKTZR
de14ST112OryE1MMiHc4IUJvWZvIKG66psG/osW1ZESNzjtEm7zyFlkVcFruUIAR
2b+QGJ6xLEYggvZhyuTo5S5GLF+q/Qh+ftj1In1/pWeDAgMBAAE=
-----END PUBLIC KEY-----
''';

/// The private key matching [testPublicKey3072], PKCS#8. TEST ONLY.
const String testPrivateKey3072Pkcs8 = '''
-----BEGIN PRIVATE KEY-----
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
q9/zFRBcJ9JseavRNsRpTsGG
-----END PRIVATE KEY-----
''';

/// A 4096-bit RSA public key (accepted since envelope v3). Its private key
/// was discarded.
const String testPublicKey4096 = '''
-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA8jsYWJ2uTolPmZrBGS47
pGRjFqZlZZzfs9MF+DgzYksB/Yp2GK86MLbcnQYV4LFPsUBocSBvVb31usckpRJv
SCIJ1xE7pvcMaRvNbGlQKvjgtl8jW6qWVhZVroomMveXt47BRN0iWzeEEJvev1gY
e7fCOPTC025PGxoXbmFww1jZ4kdf2bkvDa2e+uYWDd0O9bPkWa385Uu9Ng0AzbMI
fcYjx6ifUGqmAaTiw00gtj8tv0+DIX3BD+B45VbN1xcI6R+PsvOca/Ld4v79J6V4
pFA3UAp6pF8PGz7RCitbNZLlFbNLT4agZO6+wu+q5i/ymVogxqOTBNTsYDIDVOMv
9GH87A6lgSm0L/I3CbWl6KodnG5YtF1U81hiLGRQys9tQkgIFovkXgTibEhL0We+
myJW9E3ZEOvEL5+PXIY+UIkd2+1ZRvmOnQ+wkhAZnvUNK5bnZ/zkIbcSb6+Di/db
LKxZABQc4QcPfxi/unfP1n1Q6N9puDgnzuYD0+VVawsldUOfMbc2y3jpfdAKgA5p
yF0YSRNk6giPzozr6jWq3gDdsgA078dHCPZF8St8hwWAQwIGXz4Y3gaFqxa73ju8
0/XLTPZ79pn/aRZNzEX5GZvxhoO6y1sgbUztNiUBPnrCyIpCgtdORlQWaygIUCAJ
QM3/xTRlV+mo33xoVtsTK2UCAwEAAQ==
-----END PUBLIC KEY-----
''';

/// A 2560-bit RSA public key: a size the SDK does not support.
const String testPublicKey2560 = '''
-----BEGIN PUBLIC KEY-----
MIIBYjANBgkqhkiG9w0BAQEFAAOCAU8AMIIBSgKCAUEAyyYnFisisw0VBKQdOp/9
WHnpsTD0ZykIcMuW4/U8daTI7WYDqIsP9wmfGxaO02ekPbx9Cc/sB5nNGDC50mOJ
wI+ItPdmmSIcOjDneprwsthI87kuxI8BszRvGZ6eLhFLg4tR0GAg8GEpHbtEbDEr
ZnTutUlx9vZp10gw5FFMqAaNZZiEVH5UubpxgATDKdB7DoP7/+FXmyHAvKEYUWm1
BjTDccbXvsZ2APengUiZeThJx65LeJlSxnlaYWsHXvHU7dO/1O92kvp8G/Jz/TjV
ULvs237DsZzeM+L3KAMamZqMxMDrYbUTHW04oLzFwvB8auPAfQhtDifflN0U7iPT
uCANDihrvOKvx1/eHSeLg2+Je+OUMIeNNOYdsLnrVAfnTkSMmWUVo1Zvoi1hQj/B
8+1TNd3t+TS30zLIgwlsQiUCAwEAAQ==
-----END PUBLIC KEY-----
''';

/// A P-256 elliptic-curve public key, which the SDK must reject.
const String testPublicKeyEc = '''
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE8daJJ/rwPKkOmI6jo6zmXvcnoOoy
50EIe5Xqh1DUtxADrcravyP9eqACDk60dwKXAPZ6w4Do/lVgjtxXuEVvVQ==
-----END PUBLIC KEY-----
''';

/// Another RSA-2048 public key, not the test key above. Its private key was
/// discarded when it was generated. Used where a "real project key" is
/// needed, such as the release-mode test-key guard (I2).
const String otherPublicKeySpki = '''
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAzajUY1Y6eEreioLH3+sj
K7wZEJLl7KXYqyaZt8MPea2AXdGzItNG25vafZcN05Y/vW26eVBOIXryPeMsZoCx
NlS0vNWKriDRCBH2MF/v1TNSoosf7IYy6Ppd04PsoknBZuD6eedgqnNHEx5B9kua
klXcYDqNytKrbzM706U95Y7+JVMtDCyKvUSkKJ17r3ihCKfHDsIHMcnXLsu7eO/N
TtEGl8qSe2YneUPBCkWv4sFQlTx6tFUuwwo/YnuOmzNUMgmh+TwLTmVF5eGtXHh0
pgO99lmYpTh2cSZ1lmeGq9IMG/YepRggDdwqc3HTd5Zl9Q+c1oG1Le3+jfDUeu1q
hQIDAQAB
-----END PUBLIC KEY-----
''';
