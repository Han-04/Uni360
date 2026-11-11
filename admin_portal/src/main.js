import { createClient } from '@supabase/supabase-js';
import { escape } from './html.js';
import { mountWorkforce } from './workforce.js';
import { mountTaskApprovals } from './task-approvals.js';
import { mountPreventiveCatalog } from './preventive-catalog.js';
import './style.css';
import './workforce.css';

const app = document.querySelector('#app');
const dialog = document.querySelector('#account-dialog');
let client;
let supabaseUrl;
let supabaseKey;
const mark = `<span class="mark" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none"><path d="M12 3 5 6v5c0 4.4 2.8 7.8 7 10 4.2-2.2 7-5.6 7-10V6l-7-3Z" stroke="currentColor" stroke-width="1.7"/><path d="m9 12 2 2 4-4" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg></span>`;
let accountView;
let search = '';
let page = 0;
let busy = false;

class RequestError extends Error {
  constructor(message, status) { super(message); this.status = status; }
}

async function request(action, parameters = {}) {
  const { data: { session } } = await client.auth.getSession();
  if (!session) throw new RequestError('Sign in to continue.', 401);
  const response = await fetch(`${supabaseUrl.replace(/\/$/, '')}/functions/v1/manage-accounts`, {
    method: 'POST',
    headers: { apikey: supabaseKey, Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ action, ...parameters }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new RequestError(data.error || 'The account service is unavailable. Try again.', response.status);
  return data;
}

function login(message = '') {
  accountView = null;
  search = '';
  page = 0;
  if (dialog.open) dialog.close();
  app.innerHTML = `<div class="login-layout">
    <aside class="login-cover"><div class="brand">${mark} Uni360</div>
      <div><p class="eyebrow">CAMPUS OPERATIONS</p><h1>Administration<br>workspace</h1>
      <p>Manage access for the people who keep campus running.</p></div>
      <span class="cover-footer">UNI360 · ACCOUNT MANAGEMENT</span>
    </aside>
    <section class="login-panel"><form id="login-form">
      <p class="eyebrow">DESKTOP PORTAL</p><h2>Administrator sign-in</h2>
      <p class="muted">Use your Uni360 Administrator or Super Administrator account.</p>
      <label>Email<input name="email" type="email" autocomplete="username" required></label>
      <label>Password<input name="password" type="password" autocomplete="current-password" required></label>
      <p id="login-error" class="error" role="alert">${escape(message || (!client ? 'The portal needs its Supabase project settings.' : ''))}</p>
      <button class="primary" ${client ? '' : 'disabled'}>Sign in</button>
    </form></section></div>`;
  app.querySelector('form').addEventListener('submit', async event => {
    event.preventDefault();
    const form = event.currentTarget;
    const button = form.querySelector('button');
    const errorBox = form.querySelector('[role=alert]');
    button.disabled = true;
    button.textContent = 'Signing in…';
    errorBox.textContent = '';
    const values = Object.fromEntries(new FormData(form));
    form.elements.password.value = '';
    try {
      const { error } = await client.auth.signInWithPassword({ email: values.email.trim(), password: values.password });
      if (error) throw new Error('Sign-in failed. Check your email and password.');
      accountView = await request('list');
      dashboard();
    } catch (error) {
      await client.auth.signOut({ scope: 'local' }).catch(() => {});
      errorBox.textContent = error.message;
      button.disabled = false;
      button.textContent = 'Sign in';
    }
  });
}

function workspace(section) {
  const superAdmin = accountView.targetRole === 'administrator';
  app.innerHTML = `<div class="workspace"><aside class="sidebar">
    <div class="brand">${mark} Uni360</div><p class="eyebrow">ADMINISTRATION</p>
    <nav class="dashboard-nav" aria-label="Administration">
      <button id="accounts-nav" class="nav-item" ${section === 'accounts' ? 'aria-current="page"' : ''}>Account management</button>
      <button id="workforce-nav" class="nav-item" ${section === 'workforce' ? 'aria-current="page"' : ''}>Workforce management</button>
      <button id="facilities-nav" class="nav-item" ${section === 'facilities' ? 'aria-current="page"' : ''}>Facilities</button>
      <button id="tasks-nav" class="nav-item" ${section === 'tasks' ? 'aria-current="page"' : ''}>Schedule Task</button>
      <button id="approvals-nav" class="nav-item" ${section === 'approvals' ? 'aria-current="page"' : ''}>Task approvals</button>
    </nav>
    <div class="identity"><strong>${escape(accountView.actor.full_name)}</strong><span>${superAdmin ? 'Super Administrator' : 'Administrator'}</span></div>
    <button id="logout" class="secondary">Sign out</button>
  </aside><section class="content"></section></div>`;
  app.querySelector('#logout').onclick = async () => {
    if (busy) return;
    await client.auth.signOut({ scope: 'local' }).catch(() => {});
    login();
  };
  app.querySelector('#accounts-nav').onclick = () => {
    if (!busy && section !== 'accounts') dashboard();
  };
  app.querySelector('#workforce-nav').onclick = () => {
    if (!busy && section !== 'workforce') mountWorkforce(workspace('workforce'), client);
  };
  app.querySelector('#approvals-nav').onclick = () => {
    if (!busy && section !== 'approvals') mountTaskApprovals(workspace('approvals'), client);
  };
  for (const kind of ['facilities', 'tasks']) {
    app.querySelector(`#${kind}-nav`).onclick = () => {
      if (!busy && section !== kind) mountPreventiveCatalog(workspace(kind), client, kind, superAdmin);
    };
  }
  return app.querySelector('.content');
}

function dashboard(message = '') {
  const role = accountView.targetRole === 'administrator' ? 'Administrator' : 'Worker';
  const rows = accountView.rows;
  workspace('accounts').innerHTML = `<header class="section-head"><div><p class="eyebrow">UNI360 / ACCOUNTS</p><h1>${role} accounts</h1>
    <p class="muted">Create, update and deactivate ${role.toLowerCase()} access.</p></div>
    <button id="create" class="primary">＋ Create ${role.toLowerCase()}</button></header>
    <div class="card"><form id="search-form" class="toolbar"><label><span class="sr-only">Search by name or employee ID</span>
      <input name="search" type="search" maxlength="120" placeholder="Search by name or employee ID" value="${escape(search)}"></label><button class="secondary">Search</button></form>
      <p id="status" class="feedback" role="status">${escape(message)}</p>
      <div class="table-scroll"><table><thead><tr><th>Name</th><th>Employee ID</th><th>Phone</th><th>Status</th><th>Actions</th></tr></thead>
      <tbody>${rows.length ? rows.map(row => `<tr><td><strong>${escape(row.full_name)}</strong></td><td>${escape(row.employee_id)}</td>
      <td>${escape(row.phone || '—')}</td><td><span class="badge ${row.is_active ? 'active' : ''}">${row.is_active ? 'Active' : 'Inactive'}</span></td>
      <td class="actions"><button class="text-button" data-edit="${escape(row.user_id)}">Edit</button>${row.is_active ? `<button class="text-button danger" data-deactivate="${escape(row.user_id)}">Deactivate</button>` : ''}</td></tr>`).join('')
      : '<tr><td colspan="5" class="empty">No matching accounts.</td></tr>'}</tbody></table></div>
      <footer class="pagination"><span>Page ${page + 1}</span><button id="previous" class="secondary" ${page === 0 ? 'disabled' : ''}>Previous</button>
      <button id="next" class="secondary" ${accountView.hasNext ? '' : 'disabled'}>Next</button></footer>
    </div>`;
  app.querySelector('#search-form').onsubmit = event => {
    event.preventDefault();
    reload(String(new FormData(event.currentTarget).get('search')).trim(), 0);
  };
  app.querySelector('#previous').onclick = () => reload(search, page - 1);
  app.querySelector('#next').onclick = () => reload(search, page + 1);
  app.querySelector('#create').onclick = () => { if (!busy) openEditor(role); };
  app.querySelectorAll('[data-edit]').forEach(button => {
    button.onclick = () => { if (!busy) openEditor(role, rows.find(row => row.user_id === button.dataset.edit)); };
  });
  app.querySelectorAll('[data-deactivate]').forEach(button => {
    button.onclick = () => { if (!busy) openDeactivate(rows.find(row => row.user_id === button.dataset.deactivate)); };
  });
}

async function reload(nextSearch, nextPage, message = '') {
  if (busy) return;
  busy = true;
  const status = app.querySelector('#status');
  status.textContent = 'Loading accounts…';
  try {
    accountView = await request('list', { search: nextSearch, page: nextPage });
    search = nextSearch;
    page = nextPage;
    dashboard(message);
  } catch (error) {
    if (error.status === 401 || error.status === 403) {
      await client.auth.signOut({ scope: 'local' }).catch(() => {});
      login(error.message);
    } else {
      status.textContent = error.message;
    }
  } finally { busy = false; }
}

function openEditor(role, row) {
  dialog.innerHTML = `<form><h2 id="dialog-title">${row ? 'Edit' : 'Create'} ${role.toLowerCase()}</h2>
    <label>Full name<input name="name" required minlength="2" maxlength="120" value="${escape(row?.full_name)}"></label>
    <label>Employee ID<input name="employeeId" required maxlength="40" value="${escape(row?.employee_id)}"></label>
    <label>Phone <span class="muted">(optional)</span><input name="phone" type="tel" maxlength="21" value="${escape(row?.phone)}"></label>
    ${row ? '' : '<label>Email<input name="email" type="email" required maxlength="254"></label><label>Temporary password<input name="password" type="password" required minlength="12" maxlength="72" autocomplete="new-password"></label>'}
    <p class="error" role="alert"></p><div class="dialog-actions"><button type="button" class="secondary" data-cancel>Cancel</button>
    <button class="primary">${row ? 'Save changes' : 'Create account'}</button></div></form>`;
  submitDialog(row ? 'edit' : 'create', row?.user_id, row ? 'Account updated.' : 'Account created.');
}

function openDeactivate(row) {
  dialog.innerHTML = `<form><h2 id="dialog-title">Deactivate account?</h2>
    <p><strong>${escape(row.full_name)}</strong> will lose Uni360 access. Their account record will be retained.</p>
    <p class="error" role="alert"></p><div class="dialog-actions"><button type="button" class="secondary" data-cancel>Cancel</button>
    <button class="danger-button">Deactivate account</button></div></form>`;
  submitDialog('deactivate', row.user_id, 'Account deactivated.');
}

function submitDialog(action, id, message) {
  const form = dialog.querySelector('form');
  form.querySelector('[data-cancel]').onclick = () => dialog.close();
  form.onsubmit = async event => {
    event.preventDefault();
    if (busy) return;
    const values = Object.fromEntries(new FormData(form));
    busy = true;
    const controls = [...form.elements];
    controls.forEach(control => { control.disabled = true; });
    const errorBox = form.querySelector('[role=alert]');
    errorBox.textContent = '';
    try {
      await request(action, { ...values, id });
      form.reset();
      dialog.close();
      busy = false;
      await reload(action === 'create' ? '' : search, action === 'create' ? 0 : page, message);
    } catch (error) {
      controls.forEach(control => { control.disabled = false; });
      if (form.elements.password) form.elements.password.value = '';
      errorBox.textContent = error.message;
    } finally { busy = false; }
  };
  dialog.showModal();
}

dialog.addEventListener('cancel', event => { if (busy) event.preventDefault(); });
dialog.addEventListener('close', () => { dialog.innerHTML = ''; });
function start(url, key) {
  supabaseUrl = url;
  supabaseKey = key;
  if (url && typeof key === 'string' && key.startsWith('sb_publishable_')) {
    client = createClient(url, key, { auth: { persistSession: false, detectSessionInUrl: false } });
  }
  login();
}

if (window.parent !== window) {
  login('Connecting to Uni360…');
  const configure = event => {
    if (event.source !== window.parent || event.origin !== window.location.origin ||
        event.data?.type !== 'uni360-admin-config') return;
    window.removeEventListener('message', configure);
    start(event.data.url, event.data.key);
  };
  window.addEventListener('message', configure);
} else {
  start(__SUPABASE_URL__, __SUPABASE_KEY__);
}
