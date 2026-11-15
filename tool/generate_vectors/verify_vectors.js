// Independent check of test/vectors/envelope_vectors.json using Node's crypto.
// Run from the package root:  node tool/generate_vectors/verify_vectors.js
//
// It uses no Dart code: if this passes, the envelopes can be opened by a
// non-Dart implementation of the documented format.
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, '..', '..', 'test', 'vectors', 'envelope_vectors.json');
const doc = JSON.parse(fs.readFileSync(file, 'utf8'));
const privateKey = crypto.createPrivateKey(doc.testOnlyKeys.privateKeyPkcs8);

// I3: kid = first 16 bytes of SHA-256(DER SubjectPublicKeyInfo), base64url.
// Computed here by Node/OpenSSL, independently of the Dart code.
function kidOf(key) {
  const spki = crypto.createPublicKey(key).export({ type: 'spki', format: 'der' });
  return crypto.createHash('sha256').update(spki).digest().subarray(0, 16).toString('base64url');
}

// The server's key ring: private keys by kid. v2 envelopes (no kid) were
// always sealed to the RSA-2048 key.
const keyRing = new Map();
for (const pem of [doc.testOnlyKeys.privateKeyPkcs8, doc.testOnlyKeys.privateKey3072Pkcs8]) {
  const key = crypto.createPrivateKey(pem);
  keyRing.set(kidOf(key), key);
}

let failures = 0;
function check(name, ok, detail) {
  if (ok) {
    console.log(`PASS  ${name}`);
  } else {
    failures++;
    console.log(`FAIL  ${name}${detail ? ' - ' + detail : ''}`);
  }
}

function gcmEncrypt(key, iv, plaintext) {
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return { ciphertext, tag: cipher.getAuthTag() };
}

for (const c of doc.aesGcmCases) {
  const out = gcmEncrypt(
    Buffer.from(c.keyBase64, 'base64'),
    Buffer.from(c.ivBase64, 'base64'),
    Buffer.from(c.plaintextBase64, 'base64'),
  );
  check(
    `aes-gcm ${c.name}`,
    out.ciphertext.toString('base64') === c.ciphertextBase64 &&
      out.tag.toString('base64') === c.tagBase64,
  );
}

for (const c of doc.rsaOaepWrapCases || []) {
  try {
    const out = crypto.privateDecrypt(
      { key: privateKey, padding: crypto.constants.RSA_PKCS1_OAEP_PADDING, oaepHash: 'sha256' },
      Buffer.from(c.ciphertextBase64, 'base64'),
    );
    check(`rsa-oaep ${c.name}`, out.toString('base64') === c.messageBase64);
  } catch (err) {
    check(`rsa-oaep ${c.name}`, false, err.message);
  }
}

// The additional authenticated data, rebuilt from the clear header fields
// exactly as a server would (see specification.aad).
function envelopeAad(e) {
  const lines = e.kid === undefined
    ? ['sealed_trace.envelope.v2', e.alg, e.projectId, e.batchId, e.createdAt,
      String(e.eventCount)]
    : ['sealed_trace.envelope.v3', e.alg, e.projectId, e.batchId, e.createdAt,
      String(e.eventCount), e.kid];
  return Buffer.from(lines.join('\n'), 'utf8');
}

function openEnvelope(e, key, aad) {
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(e.iv, 'base64'));
  decipher.setAAD(aad);
  decipher.setAuthTag(Buffer.from(e.tag, 'base64'));
  return Buffer.concat([
    decipher.update(Buffer.from(e.ciphertext, 'base64')),
    decipher.final(),
  ]).toString('utf8');
}

// Padme (Nikitin et al., PETS 2019), at least 256 bytes.
function padme(length) {
  if (length <= 256) return 256;
  const e = Math.floor(Math.log2(length));
  const s = Math.floor(Math.log2(e)) + 1;
  const mask = 2 ** (e - s) - 1;
  return Math.ceil(length / (mask + 1)) * (mask + 1);
}

function fails(fn) {
  try {
    fn();
    return false;
  } catch (_) {
    return true;
  }
}

for (const c of doc.envelopes) {
  const e = c.envelope;
  const legacy = e.v === 2;
  const wire = ['v', 'batchId', 'projectId', 'createdAt', 'eventCount', 'alg',
    ...(legacy ? [] : ['kid']), 'wrappedKey', 'iv', 'tag', 'ciphertext'];
  check(`${c.name}: wire keys`, JSON.stringify(Object.keys(e)) === JSON.stringify(wire));

  const iv = Buffer.from(e.iv, 'base64');
  const tag = Buffer.from(e.tag, 'base64');
  const wrapped = Buffer.from(e.wrappedKey, 'base64');
  const bits = wrapped.length * 8;
  check(`${c.name}: v, alg and key size`,
    (legacy ? bits === 2048 : e.v === 3 && [2048, 3072, 4096].includes(bits)) &&
      e.alg === `RSA-OAEP-${bits}-SHA256+AES-256-GCM`);
  check(`${c.name}: aadUtf8 matches the rebuilt AAD`, envelopeAad(e).toString('utf8') === c.aadUtf8);
  check(`${c.name}: sizes`, iv.length === 12 && tag.length === 16);

  // Pick the private key the way a server would: by kid, or the 2048 key for v2.
  const ringKey = legacy ? privateKey : keyRing.get(e.kid);
  check(`${c.name}: kid names a known key`, ringKey !== undefined, e.kid);
  if (ringKey === undefined) continue;

  let key;
  try {
    key = crypto.privateDecrypt(
      { key: ringKey, padding: crypto.constants.RSA_PKCS1_OAEP_PADDING, oaepHash: 'sha256' },
      wrapped,
    );
  } catch (err) {
    check(`${c.name}: unwrap key`, false, err.message);
    continue;
  }
  check(`${c.name}: unwrap key`, key.toString('base64') === c.aesKeyBase64);

  try {
    const plain = openEnvelope(e, key, envelopeAad(e));
    // L6: the JSON is followed by spaces up to its Padme length.
    const json = Buffer.byteLength(c.plaintextJson, 'utf8');
    check(`${c.name}: decrypt`, plain.slice(0, c.plaintextJson.length) === c.plaintextJson &&
      /^ *$/.test(plain.slice(c.plaintextJson.length)));
    check(`${c.name}: padded to the Padme length`,
      Buffer.byteLength(plain, 'utf8') === padme(json) && padme(json) === c.paddedLength);
    check(`${c.name}: plaintext is a JSON array of ${e.eventCount}`,
      Array.isArray(JSON.parse(plain)) && JSON.parse(plain).length === e.eventCount);
  } catch (err) {
    check(`${c.name}: decrypt`, false, err.message);
  }

  // M1: any change to the clear header must break decryption.
  check(`${c.name}: no AAD fails`, fails(() => openEnvelope(e, key, Buffer.alloc(0))));
  for (const [field, value] of [
    ['batchId', '00000000-0000-4000-8000-000000000000'],
    ['projectId', '11111111-1111-4111-8111-111111111111'],
    ['createdAt', '2020-01-01T00:00:00.000Z'],
    ['eventCount', e.eventCount + 1],
    // I3: kid is authenticated; adding one to a v2 envelope also fails.
    ['kid', legacy ? 'i5AhdjEFUP1jG9OUOECv9Q' : 'AAAAAAAAAAAAAAAAAAAAAA'],
  ]) {
    const forged = { ...e, [field]: value };
    check(`${c.name}: changed ${field} fails`,
      fails(() => openEnvelope(forged, key, envelopeAad(forged))));
  }
}

console.log(failures === 0 ? '\nAll vectors verified.' : `\n${failures} check(s) failed.`);
process.exit(failures === 0 ? 0 : 1);
