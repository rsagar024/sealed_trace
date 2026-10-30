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

for (const c of doc.envelopes) {
  const e = c.envelope;
  const wire = ['v', 'batchId', 'projectId', 'createdAt', 'eventCount', 'alg',
    'wrappedKey', 'iv', 'tag', 'ciphertext'];
  check(`${c.name}: wire keys`, JSON.stringify(Object.keys(e)) === JSON.stringify(wire));
  check(`${c.name}: v and alg`, e.v === 1 && e.alg === 'RSA-OAEP-2048-SHA256+AES-256-GCM');

  const iv = Buffer.from(e.iv, 'base64');
  const tag = Buffer.from(e.tag, 'base64');
  const wrapped = Buffer.from(e.wrappedKey, 'base64');
  check(`${c.name}: sizes`, iv.length === 12 && tag.length === 16 && wrapped.length === 256);

  let key;
  try {
    key = crypto.privateDecrypt(
      { key: privateKey, padding: crypto.constants.RSA_PKCS1_OAEP_PADDING, oaepHash: 'sha256' },
      wrapped,
    );
  } catch (err) {
    check(`${c.name}: unwrap key`, false, err.message);
    continue;
  }
  check(`${c.name}: unwrap key`, key.toString('base64') === c.aesKeyBase64);

  try {
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
    decipher.setAuthTag(tag);
    const plain = Buffer.concat([
      decipher.update(Buffer.from(e.ciphertext, 'base64')),
      decipher.final(),
    ]).toString('utf8');
    check(`${c.name}: decrypt`, plain === c.plaintextJson);
    check(`${c.name}: plaintext is a JSON array of ${e.eventCount}`,
      Array.isArray(JSON.parse(plain)) && JSON.parse(plain).length === e.eventCount);
  } catch (err) {
    check(`${c.name}: decrypt`, false, err.message);
  }
}

console.log(failures === 0 ? '\nAll vectors verified.' : `\n${failures} check(s) failed.`);
process.exit(failures === 0 ? 0 : 1);
