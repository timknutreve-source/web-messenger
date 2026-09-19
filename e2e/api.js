const fs = require('fs');
const { API } = require('./lib');
// The backend must run with EMAIL_PROVIDER=log and its output tee'd to this file: the
// e-mail verification code is read from its log line (no real mailbox is involved).
const LOG = process.env.BACKEND_LOG || '/tmp/backend.log';
const PASSWORD = 'Str0ng!Pass';

async function call(method, path, token, body) {
  const res = await fetch(API + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json; try { json = text ? JSON.parse(text) : null; } catch { json = text; }
  return { status: res.status, body: json };
}

/** Latest emailed code of the given kind ('Verification'|'Password reset') for an email, from the dev backend's log. */
function latestCode(kind, email) {
  const lines = fs.readFileSync(LOG, 'utf8').split('\n').filter(l => l.includes(`${kind} code for`) && l.includes(`<${email}>`));
  if (!lines.length) return null;
  return lines[lines.length - 1].split(': ').pop().trim();
}

async function waitForCode(kind, email, timeoutMs = 10000) {
  const end = Date.now() + timeoutMs;
  while (Date.now() < end) {
    const c = latestCode(kind, email);
    if (c) return c;
    await new Promise(r => setTimeout(r, 300));
  }
  throw new Error(`no ${kind} code logged for ${email}`);
}

/** Registers + verifies a user entirely over REST; returns { token, id, username, email }. */
async function createUser(username, device = 'API') {
  const email = `${username}@example.com`;
  const reg = await call('POST', '/api/auth/register', null, { username, email, password: PASSWORD, deviceName: device });
  if (reg.status !== 201) throw new Error('register failed ' + JSON.stringify(reg));
  const code = await waitForCode('Verification', email);
  const ver = await call('POST', '/api/auth/verify-email', reg.body.token, { code });
  if (ver.status !== 200) throw new Error('verify failed ' + JSON.stringify(ver));
  return { token: reg.body.token, id: reg.body.user.id, username, email };
}

async function login(username, device = 'API') {
  const r = await call('POST', '/api/auth/login', null, { usernameOrEmail: username, password: PASSWORD, deviceName: device });
  if (r.status !== 200) throw new Error('login failed ' + JSON.stringify(r));
  return r.body.token;
}

/** Makes two existing users contacts (invitation + accept) and returns the direct chat id. */
async function befriend(a, b) {
  const inv = await call('POST', '/api/contacts/invitations', a.token, { recipientId: b.id });
  if (inv.status !== 201) throw new Error('invite failed ' + JSON.stringify(inv));
  const acc = await call('POST', `/api/contacts/invitations/${inv.body.id}/accept`, b.token);
  if (acc.status !== 200) throw new Error('accept failed ' + JSON.stringify(acc));
  const chats = await call('GET', '/api/chats', a.token);
  return chats.body.find(c => c.otherUser && c.otherUser.id === b.id).id;
}

const unique = (p) => `${p}${Date.now().toString(36).slice(-5)}${Math.floor(Math.random() * 90 + 10)}`;

module.exports = { call, latestCode, waitForCode, createUser, login, befriend, unique, PASSWORD };
