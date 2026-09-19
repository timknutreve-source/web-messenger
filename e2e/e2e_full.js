const path = require('path');
// Files the browser is asked to upload. A snap-packaged Chromium can only read files under
// your home directory, so point FIXTURE_DIR there in that case (see e2e/README.md).
const FIXTURES = process.env.FIXTURE_DIR || path.join(__dirname, 'fixtures');
const { launch, newPage, snapshot, typeInto, enableSemantics, API } = require('./lib');
const { createUser, befriend, call, login, PASSWORD, unique } = require('./api');

const results = [];
let currentPage = null;
async function step(name, fn) {
  const t = Date.now();
  try {
    await fn();
    results.push({ ok: true, name });
    console.log(`PASS  ${name}  (${Date.now() - t}ms)`);
  } catch (e) {
    const lines = e.message.split('\n').filter(l => l.trim()).slice(0, 3).join(' | ');
    results.push({ ok: false, name, err: lines });
    console.log(`FAIL  ${name}  -> ${lines}`);
    try { await currentPage.screenshot({ path: `fail_${results.length}.png` }); } catch {}
  }
}
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const LIVE_LIMIT_MS = 2000;

async function webLogin(page, username) {
  await page.waitForTimeout(1000);
  await typeInto(page, page.getByRole('textbox', { name: 'Username or email' }), username);
  await typeInto(page, page.getByRole('textbox', { name: 'Password' }), PASSWORD);
  await page.getByRole('button', { name: 'Log in', exact: true }).click();
  await page.getByRole('button', { name: 'Log out' }).waitFor({ timeout: 15000 });
}
// Flutter exposes some text as text nodes and some as aria-labels of groups/buttons; match any.
function patch(page) {
  const orig = page.getByText.bind(page);
  page.getByText = (t, o) => {
    let loc = orig(t, o);
    if (typeof t === 'string') loc = loc.or(page.getByRole('group', { name: t, exact: o && o.exact })).or(page.getByRole('button', { name: t, exact: o && o.exact }));
    return loc.first();
  };
  return page;
}
const tile = (page, username) => page.getByRole('button', { name: new RegExp('^' + username) }).first();

(async () => {
  const alice = await createUser(unique('ea'), 'Android');
  const bob = await createUser(unique('eb'), 'Android');
  const carol = await createUser(unique('ec'), 'Android');
  const chatBob = await befriend(alice, bob);
  const chatCarol = await befriend(alice, carol);
  console.log('users', alice.username, bob.username, carol.username);

  const browser = await launch();
  const page = patch(await newPage(browser, 'alice-web'));
  page.setDefaultTimeout(10000);
  currentPage = page;

  await step('desktop layout after login (left nav + centre)', async () => {
    await webLogin(page, alice.username);
    await page.getByRole('tab', { name: /^Chats/ }).waitFor();
    await page.getByRole('tab', { name: 'Contacts' }).waitFor();
    await page.getByRole('tab', { name: 'Invites' }).waitFor();
    await page.getByText('Select a chat to start messaging').waitFor();
  });

  await step('chat list shows both direct chats', async () => {
    await tile(page, bob.username).waitFor();
    await tile(page, carol.username).waitFor();
  });

  await step('open direct chat, mobile->web message arrives live (<2s)', async () => {
    await tile(page, bob.username).click();
    await page.getByRole('textbox', { name: 'Message' }).waitFor();
    const t0 = Date.now();
    await call('POST', `/api/chats/${chatBob}/messages`, bob.token, { content: 'live from mobile 1' });
    await page.getByText('live from mobile 1').waitFor({ timeout: 8000 });
    const ms = Date.now() - t0;
    console.log('      latency ms:', ms);
    if (ms > LIVE_LIMIT_MS) throw new Error('too slow: ' + ms);
  });

  await step('web recipient auto-acknowledges: message becomes READ for the sender within 2s', async () => {
    const sent = await call('POST', `/api/chats/${chatBob}/messages`, bob.token, { content: 'read me' });
    await page.getByText('read me').waitFor({ timeout: 8000 });
    const t0 = Date.now();
    let status = 'SENT';
    while (Date.now() - t0 < 4000) {
      const list = await call('GET', `/api/chats/${chatBob}/messages`, bob.token);
      status = list.body.messages.find(m => m.id === sent.body.id).status;
      if (status === 'READ') break;
      await sleep(150);
    }
    console.log('      final status', status, 'after', Date.now() - t0, 'ms');
    if (status !== 'READ') throw new Error('status ' + status);
  });

  await step('web -> mobile: message typed in the web composer reaches the other client', async () => {
    await page.getByRole('textbox', { name: 'Message' }).click();
    await typeInto(page, page.getByRole('textbox', { name: 'Message' }), 'hello from web');
    const t0 = Date.now();
    await page.getByRole('button', { name: 'Send message' }).click();
    await page.getByText('hello from web').waitFor();
    let got = false;
    while (Date.now() - t0 < 3000 && !got) {
      const list = await call('GET', `/api/chats/${chatBob}/messages`, bob.token);
      got = list.body.messages.some(m => m.content === 'hello from web');
      if (!got) await sleep(100);
    }
    if (!got) throw new Error('not received by other client');
    console.log('      web->api ms:', Date.now() - t0);
  });

  await step('web -> mobile: status reaches DELIVERED/READ once the other client acknowledges', async () => {
    const list = await call('GET', `/api/chats/${chatBob}/messages`, bob.token);
    const m = list.body.messages.find(x => x.content === 'hello from web');
    await call('POST', `/api/chats/${chatBob}/messages/${m.id}/delivered`, bob.token);
    await call('POST', `/api/chats/${chatBob}/messages/read`, bob.token);
    await page.getByRole('group', { name: /hello from web.*Read/ }).waitFor({ timeout: 6000 });
  });

  await step('edit and delete own message from the web', async () => {
    await page.getByRole('button', { name: 'Message actions' }).last().click();
    await page.getByText('Edit', { exact: true }).click();
    await page.waitForTimeout(500);
    await page.keyboard.press('Control+A');
    await page.keyboard.type('hello from web (edited)', { delay: 10 });
    await page.getByRole('button', { name: 'Save' }).click();
    await page.getByText('hello from web (edited)').waitFor({ timeout: 6000 });
    const list = await call('GET', `/api/chats/${chatBob}/messages`, bob.token);
    if (!list.body.messages.some(m => m.content === 'hello from web (edited)' && m.editedAt)) throw new Error('edit not persisted');
    await page.getByRole('button', { name: 'Message actions' }).last().click();
    await page.getByText('Delete', { exact: true }).click();
    await page.getByRole('button', { name: 'Delete' }).last().click();
    await page.getByText('This message was deleted').waitFor({ timeout: 6000 });
  });

  // ---------------- groups ----------------
  let groupId;
  await step('create a group from the web (name + choose contacts)', async () => {
    await page.getByRole('button', { name: 'New group' }).click();
    await typeInto(page, page.getByRole('textbox', { name: 'Group name' }), 'Weekend plans');
    await page.getByRole('checkbox', { name: new RegExp(bob.username) }).click();
    await page.getByRole('checkbox', { name: new RegExp(carol.username) }).click();
    await page.getByRole('button', { name: 'Create group' }).click();
    await page.getByText('Weekend plans').first().waitFor({ timeout: 8000 });
    const chats = await call('GET', '/api/chats', alice.token);
    const g = chats.body.find(c => c.type === 'GROUP');
    if (!g || g.name !== 'Weekend plans') throw new Error('group not in API chat list');
    groupId = g.id;
    const pendingBob = await call('GET', '/api/groups/invitations/pending', bob.token);
    if (pendingBob.body.length !== 1) throw new Error('bob has no pending group invitation');
  });

  await step('invitees accept on mobile; web shows members live', async () => {
    await page.getByRole('button', { name: 'Chat info' }).click();
    await page.getByText('Invited (2)').waitFor({ timeout: 8000 });
    for (const u of [bob, carol]) {
      const pend = await call('GET', '/api/groups/invitations/pending', u.token);
      const acc = await call('POST', `/api/groups/invitations/${pend.body[0].id}/accept`, u.token);
      if (acc.status !== 200) throw new Error('accept failed');
    }
    await page.getByText('Members (3)').waitFor({ timeout: 8000 });
    await page.getByText('3 members').first().waitFor({ timeout: 8000 });
  });

  await step('group message web -> members; member -> web live (<2s)', async () => {
    await typeInto(page, page.getByRole('textbox', { name: 'Message' }), 'hello group');
    await page.getByRole('button', { name: 'Send message' }).click();
    await page.getByText('hello group').first().waitFor();
    for (const u of [bob, carol]) {
      const list = await call('GET', `/api/chats/${groupId}/messages`, u.token);
      if (!list.body.messages.some(m => m.content === 'hello group')) throw new Error('member did not get it');
    }
    const t0 = Date.now();
    await call('POST', `/api/chats/${groupId}/messages`, carol.token, { content: 'carol says hi' });
    await page.getByText('carol says hi').waitFor({ timeout: 8000 });
    const ms = Date.now() - t0;
    console.log('      group latency ms:', ms);
    if (ms > LIVE_LIMIT_MS) throw new Error('too slow ' + ms);
  });

  await step('group delivered/read aggregate (needs every member)', async () => {
    const sent = await call('POST', `/api/chats/${groupId}/messages`, alice.token, { content: 'agg check' });
    await call('POST', `/api/chats/${groupId}/messages/${sent.body.id}/delivered`, bob.token);
    let list = await call('GET', `/api/chats/${groupId}/messages`, alice.token);
    if (list.body.messages.find(m => m.id === sent.body.id).status !== 'SENT') throw new Error('became delivered too early');
    await call('POST', `/api/chats/${groupId}/messages/${sent.body.id}/delivered`, carol.token);
    list = await call('GET', `/api/chats/${groupId}/messages`, alice.token);
    if (list.body.messages.find(m => m.id === sent.body.id).status !== 'DELIVERED') throw new Error('not delivered');
  });

  // ---------------- polls ----------------
  await step('create a public poll on the web; a mobile vote appears live; web vote works', async () => {
    await page.getByRole('button', { name: 'Create poll' }).click();
    await typeInto(page, page.getByRole('textbox', { name: 'Question' }), 'Where should we eat?');
    await typeInto(page, page.getByRole('textbox', { name: 'Option 1' }), 'Pizza');
    await typeInto(page, page.getByRole('textbox', { name: 'Option 2' }), 'Sushi');
    await page.getByRole('button', { name: 'Create', exact: true }).click();
    await page.getByText('Public poll').waitFor({ timeout: 8000 });
    const msgs = await call('GET', `/api/chats/${groupId}/messages`, bob.token);
    const pollMsg = msgs.body.messages.find(m => m.poll);
    if (!pollMsg) throw new Error('poll not visible to a member');
    const poll = pollMsg.poll;
    const t0 = Date.now();
    await call('PUT', `/api/chats/${groupId}/polls/${poll.id}/vote`, bob.token, { optionId: poll.options[0].id });
    await page.getByRole('button', { name: /^Pizza, 1 vote/ }).waitFor({ timeout: 8000 });
    console.log('      poll update latency ms:', Date.now() - t0);
    await page.getByRole('button', { name: /^Sushi, 0 votes/ }).click();
    await page.getByRole('button', { name: /^Sushi, 1 vote, your vote/ }).waitFor({ timeout: 8000 });
    // change vote
    await page.getByRole('button', { name: /^Pizza, 1 vote/ }).click();
    await page.getByRole('button', { name: /^Pizza, 2 votes, your vote/ }).waitFor({ timeout: 8000 });
    // retract
    await page.getByRole('button', { name: 'Retract vote' }).click();
    await page.getByRole('button', { name: /^Pizza, 1 vote$/ }).waitFor({ timeout: 8000 });
    const after = await call('GET', `/api/chats/${groupId}/polls/${poll.id}`, alice.token);
    if (after.body.myOptionId !== null) throw new Error('retract not persisted');
  });

  await step('anonymous poll hides voters (API view of another member)', async () => {
    await page.getByRole('button', { name: 'Create poll' }).click();
    await typeInto(page, page.getByRole('textbox', { name: 'Question' }), 'Secret ballot?');
    await typeInto(page, page.getByRole('textbox', { name: 'Option 1' }), 'Yes');
    await typeInto(page, page.getByRole('textbox', { name: 'Option 2' }), 'No');
    const sw = page.getByRole('switch');
    if (await sw.count()) await sw.first().click(); else await page.getByText('Anonymous poll').first().click();
    await page.getByRole('button', { name: 'Create', exact: true }).click();
    await page.getByText('Anonymous poll').last().waitFor({ timeout: 8000 });
    const msgs = await call('GET', `/api/chats/${groupId}/messages`, carol.token);
    const poll = msgs.body.messages.filter(m => m.poll).pop().poll;
    if (!poll.anonymous) throw new Error('not anonymous');
    await call('PUT', `/api/chats/${groupId}/polls/${poll.id}/vote`, carol.token, { optionId: poll.options[0].id });
    const seen = await call('GET', `/api/chats/${groupId}/polls/${poll.id}`, alice.token);
    if (seen.body.options.some(o => o.voters !== null)) throw new Error('voters leaked');
    await page.getByRole('button', { name: /^Yes, 1 vote/ }).waitFor({ timeout: 8000 });
  });

  // ---------------- search ----------------
  await step('search in a group chat: count, next/previous, none, clear, close (chat state kept)', async () => {
    await call('POST', `/api/chats/${groupId}/messages`, bob.token, { content: 'the picnic is on friday' });
    await call('POST', `/api/chats/${groupId}/messages`, carol.token, { content: 'FRIDAY works for me' });
    await page.getByText('FRIDAY works for me').waitFor({ timeout: 8000 });
    await page.getByRole('button', { name: 'Search in chat' }).click();
    const field = page.getByRole('textbox', { name: 'Search in this chat' });
    await typeInto(page, field, 'friday');
    await page.keyboard.press('Enter');
    await page.getByText('2 of 2').waitFor({ timeout: 8000 });
    await page.getByRole('button', { name: 'Previous match' }).click();
    await page.getByText('1 of 2').waitFor({ timeout: 4000 });
    await page.getByRole('button', { name: 'Next match' }).click();
    await page.getByText('2 of 2').waitFor({ timeout: 4000 });
    await typeInto(page, field, 'zzzz-nothing');
    await page.keyboard.press('Enter');
    await page.getByText('No matches').first().waitFor({ timeout: 8000 });
    await typeInto(page, field, '');
    await page.keyboard.press('Enter');
    await page.waitForTimeout(500);
    if (await page.getByText('No matches').count()) throw new Error('stale no-matches after clearing');
    await page.getByRole('button', { name: 'Close search', exact: true }).last().click();
    await page.getByText('FRIDAY works for me').waitFor();
    await page.getByText('hello group').first().waitFor();
  });

  await step('search in an individual chat', async () => {
    await tile(page, bob.username).click();
    await page.getByText('live from mobile 1').waitFor({ timeout: 8000 });
    await page.getByRole('button', { name: 'Search in chat' }).click();
    await typeInto(page, page.getByRole('textbox', { name: 'Search in this chat' }), 'mobile');
    await page.keyboard.press('Enter');
    await page.getByText('1 of 1').waitFor({ timeout: 8000 });
    await page.getByRole('button', { name: 'Close search', exact: true }).last().click();
  });

  // ---------------- two chats at once ----------------
  await step('two chats side by side; live message reaches only its own panel', async () => {
    await tile(page, 'Weekend plans').click();
    await page.getByRole('textbox', { name: 'Message' }).waitFor();
    await tile(page, bob.username).getByRole('button', { name: 'Open side by side' }).click();
    await page.waitForFunction(() => document.querySelectorAll('[role=textbox]').length >= 2 || true);
    await page.waitForTimeout(1200);
    const inputs = await page.getByRole('textbox', { name: 'Message' }).count();
    if (inputs !== 2) throw new Error('expected 2 composers, got ' + inputs);
    const t0 = Date.now();
    await call('POST', `/api/chats/${chatBob}/messages`, bob.token, { content: 'ping right panel' });
    await page.getByText('ping right panel').waitFor({ timeout: 8000 });
    console.log('      2nd panel latency ms:', Date.now() - t0);
    await call('POST', `/api/chats/${groupId}/messages`, carol.token, { content: 'ping left panel' });
    await page.getByText('ping left panel').waitFor({ timeout: 8000 });
    await page.screenshot({ path: 'two_panels.png' });
  });

  await step('send from the second panel goes to the second chat', async () => {
    const composers = page.getByRole('textbox', { name: 'Message' });
    await typeInto(page, composers.nth(1), 'typed in panel two');
    await page.getByRole('button', { name: 'Send message' }).nth(1).click();
    await page.getByText('typed in panel two').waitFor({ timeout: 6000 });
    const list = await call('GET', `/api/chats/${chatBob}/messages`, bob.token);
    if (!list.body.messages.some(m => m.content === 'typed in panel two')) throw new Error('went to wrong chat');
    const g = await call('GET', `/api/chats/${groupId}/messages`, bob.token);
    if (g.body.messages.some(m => m.content === 'typed in panel two')) throw new Error('leaked into other chat');
  });

  await step('close the second panel', async () => {
    await page.getByRole('button', { name: 'Close chat' }).last().click();
    await page.waitForTimeout(600);
    if ((await page.getByRole('textbox', { name: 'Message' }).count()) !== 1) throw new Error('panel not closed');
  });

  // ---------------- invitations ----------------
  await step('incoming group invitation appears live in Invites (badge) and can be accepted', async () => {
    const dave = await createUser(unique('ed'), 'Android');
    await befriend(dave, alice);
    await call('POST', '/api/groups', dave.token, { name: 'Book club', memberIds: [alice.id] });
    await page.getByRole('tab', { name: /^Invites 1/ }).waitFor({ timeout: 8000 });
    await page.getByRole('tab', { name: /^Invites/ }).click();
    await page.getByText('Book club').waitFor();
    await page.getByRole('button', { name: 'Join' }).click();
    await page.getByRole('tab', { name: /^Chats/ }).click();
    await page.getByRole('button', { name: /^Book club/ }).waitFor({ timeout: 8000 });
  });

  await step('incoming contact invitation: accept from the web, chat appears', async () => {
    const erin = await createUser(unique('ee'), 'Android');
    await call('POST', '/api/contacts/invitations', erin.token, { recipientId: alice.id });
    await page.getByRole('tab', { name: /^Invites 1/ }).waitFor({ timeout: 8000 });
    await page.getByRole('tab', { name: /^Invites/ }).click();
    await page.getByText(erin.username).first().waitFor();
    await page.getByRole('button', { name: 'Accept' }).click();
    await page.getByRole('tab', { name: /^Chats/ }).click();
    await tile(page, erin.username).waitFor({ timeout: 8000 });
  });

  await step('find people: search by username and send an invitation', async () => {
    const frank = await createUser(unique('ef'), 'Android');
    await page.getByRole('tab', { name: 'Find' }).click();
    await typeInto(page, page.getByRole('textbox', { name: /Search by username or email/ }), frank.username);
    await page.keyboard.press('Enter');
    await page.getByRole('button', { name: 'Send invitation' }).click();
    await page.getByText('Invitation sent').waitFor({ timeout: 6000 });
    const pend = await call('GET', '/api/contacts/invitations/pending', frank.token);
    if (pend.body.length !== 1) throw new Error('invitation not received');
    await page.getByRole('tab', { name: /^Chats/ }).click();
  });

  // ---------------- media ----------------
  await step('send an image from the web; it renders and the other client has the attachment', async () => {
    await tile(page, bob.username).click();
    await page.getByRole('button', { name: 'Attach photo or video' }).click();
    const [chooser] = await Promise.all([
      page.waitForEvent('filechooser'),
      page.getByText('Photo from gallery').click(),
    ]);
    await chooser.setFiles(path.join(FIXTURES, 'test.png'));
    await page.getByText('Ready to send').waitFor({ timeout: 10000 });
    await page.getByRole('button', { name: 'Send message' }).click();
    await page.waitForTimeout(1500);
    const list = await call('GET', `/api/chats/${chatBob}/messages`, bob.token);
    const withImage = list.body.messages.filter(m => m.attachments.some(a => a.type === 'IMAGE'));
    if (!withImage.length) throw new Error('no image attachment on the server');
  });

  await step('send a video from the web', async () => {
    await page.getByRole('button', { name: 'Attach photo or video' }).click();
    const [chooser] = await Promise.all([
      page.waitForEvent('filechooser'),
      page.getByText('Video from gallery').click(),
    ]);
    await chooser.setFiles(path.join(FIXTURES, 'test.mp4'));
    await page.getByText('Ready to send').waitFor({ timeout: 10000 });
    await page.getByRole('button', { name: 'Send message' }).click();
    await page.waitForTimeout(1500);
    const list = await call('GET', `/api/chats/${chatBob}/messages`, bob.token);
    if (!list.body.messages.some(m => m.attachments.some(a => a.type === 'VIDEO'))) throw new Error('no video attachment');
  });

  await step('record and send a voice message from the web (fake microphone)', async () => {
    await page.getByRole('button', { name: 'Record voice message' }).click();
    await page.getByText(/Recording\.\.\./).waitFor({ timeout: 6000 });
    await page.waitForTimeout(2200);
    await page.getByRole('button', { name: 'Stop recording' }).click();
    await page.getByText('Ready to send').waitFor({ timeout: 10000 });
    await page.getByRole('button', { name: 'Send message' }).click();
    await page.waitForTimeout(1500);
    const list = await call('GET', `/api/chats/${chatBob}/messages`, bob.token);
    if (!list.body.messages.some(m => m.attachments.some(a => a.type === 'AUDIO'))) throw new Error('no audio attachment');
  });

  await step('mobile -> web image arrives live', async () => {
    // upload via API as "mobile": multipart
    const fs = require('fs');
    const form = new FormData();
    form.append('file', new Blob([fs.readFileSync(path.join(FIXTURES, 'test.png'))], { type: 'image/png' }), 'p.png');
    const up = await fetch(`${API}/api/chats/${chatBob}/attachments`, { method: 'POST', headers: { Authorization: 'Bearer ' + bob.token }, body: form });
    if (up.status >= 300) throw new Error('upload failed ' + up.status + await up.text());
    const att = await up.json();
    const t0 = Date.now();
    await call('POST', `/api/chats/${chatBob}/messages`, bob.token, { content: 'photo for you', attachmentIds: [att.id] });
    await page.getByText('photo for you').waitFor({ timeout: 8000 });
    console.log('      image msg latency ms:', Date.now() - t0);
  });

  // ---------------- failure handling ----------------
  await step('failed delivery is shown, and retry succeeds once back online', async () => {
    try {
      await page.context().setOffline(true);
      await typeInto(page, page.getByRole('textbox', { name: 'Message' }), 'sent while offline');
      await page.getByRole('button', { name: 'Send message' }).click();
      await page.getByText('Failed, tap to retry').waitFor({ timeout: 12000 });
      await page.getByText(/Unable to send message/).waitFor({ timeout: 4000 });
    } finally {
      await page.context().setOffline(false);
    }
    await page.getByText('Failed, tap to retry').click();
    await page.waitForTimeout(2500);
    const list = await call('GET', `/api/chats/${chatBob}/messages`, bob.token);
    if (!list.body.messages.some(m => m.content === 'sent while offline')) throw new Error('retry did not deliver');
    if (await page.getByText('Failed, tap to retry').count()) throw new Error('still failed');
  });

  // ---------------- sessions / persistence ----------------
  await step('reload keeps the session, chat list and history', async () => {
    await page.reload();
    await page.waitForSelector('flt-glass-pane, flutter-view');
    await enableSemantics(page);
    await page.getByRole('button', { name: 'Log out' }).waitFor({ timeout: 15000 });
    await tile(page, bob.username).click();
    await page.getByText('photo for you').waitFor({ timeout: 10000 });
    await page.getByText('sent while offline').waitFor({ timeout: 10000 });
  });

  await step('independent sessions: 2nd browser + mobile at once; logging out one keeps the others', async () => {
    const page2 = patch(await newPage(browser, 'alice-web-2'));
    currentPage = page2;
    await webLogin(page2, alice.username);
    const apiToken2 = await login(alice.username, 'Android-2');
    let sessions = await call('GET', '/api/auth/sessions', alice.token);
    const before = sessions.body.length;
    if (before < 4) throw new Error('expected >=4 concurrent sessions, got ' + before);
    // both web sessions receive a live message
    await call('POST', `/api/chats/${chatBob}/messages`, bob.token, { content: 'to both sessions' });
    await tile(page2, bob.username).click();
    await page2.getByText('to both sessions').waitFor({ timeout: 8000 });
    await page.getByText('to both sessions').waitFor({ timeout: 8000 });
    // selective logout: page2 only
    await page2.getByRole('button', { name: 'Log out' }).click();
    await page2.getByRole('button', { name: 'Log in', exact: true }).waitFor({ timeout: 8000 });
    // The client drops the session locally at once and tells the server in the background.
    for (let i = 0; i < 30; i++) {
      sessions = await call('GET', '/api/auth/sessions', alice.token);
      if (sessions.body.length === before - 1) break;
      await sleep(200);
    }
    if (sessions.body.length !== before - 1) throw new Error(`sessions ${before} -> ${sessions.body.length}`);
    const me1 = await call('GET', '/api/auth/me', alice.token);
    const me2 = await call('GET', '/api/auth/me', apiToken2);
    if (me1.status !== 200 || me2.status !== 200) throw new Error('other sessions were logged out');
    currentPage = page;
    await call('POST', `/api/chats/${chatBob}/messages`, bob.token, { content: 'after other logout' });
    await page.getByText('after other logout').waitFor({ timeout: 8000 });
  });

  await step('a session revoked from another device is signed out with a message', async () => {
    const sessions = await call('GET', '/api/auth/sessions', alice.token);
    const webSession = sessions.body.find(s => s.deviceLabel === 'Web' && !s.current);
    if (!webSession) throw new Error('no web session listed: ' + JSON.stringify(sessions.body.map(s => s.deviceLabel)));
    await call('DELETE', `/api/auth/sessions/${webSession.id}`, alice.token);
    await call('POST', `/api/chats/${chatBob}/messages`, bob.token, { content: 'poke' });
    // The incoming message makes the client call the server (delivery ack), which now says 401.
    const expired = page.getByText(/session has expired/i);
    let seen = await expired.waitFor({ timeout: 6000 }).then(() => true, () => false);
    if (!seen) {
      // Otherwise the next thing the user does hits the 401.
      await typeInto(page, page.getByRole('textbox', { name: 'Message' }), 'am I still logged in?');
      await page.getByRole('button', { name: 'Send message' }).click();
      await expired.waitFor({ timeout: 15000 });
    }
    await page.getByRole('button', { name: 'Log in', exact: true }).waitFor({ timeout: 5000 });
  });

  console.log('\nconsole errors (page 1):', page.consoleErrors.filter(e => !/favicon|net::ERR_INTERNET_DISCONNECTED|Failed to load resource/.test(e)).slice(0, 8));
  await browser.close();
  const failed = results.filter(r => !r.ok);
  console.log(`\n${results.length - failed.length}/${results.length} steps passed`);
  failed.forEach(f => console.log(' FAILED:', f.name, '->', f.err));
  process.exit(failed.length ? 2 : 0);
})().catch(e => { console.error('FATAL', e); process.exit(1); });
