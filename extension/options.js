const api = typeof browser !== 'undefined' ? browser : chrome;
const DEFAULTS = self.DEFAULT_PUBLISHERS || [];

function get(keys) {
  return new Promise((r) => {
    const p = api.storage.local.get(keys, r);
    if (p && typeof p.then === 'function') p.then(r);
  });
}
function set(obj) {
  return new Promise((r) => {
    const p = api.storage.local.set(obj, r);
    if (p && typeof p.then === 'function') p.then(r);
  });
}

async function render() {
  const { domains = {} } = await get({ domains: {} });
  const names = new Set([...DEFAULTS, ...Object.keys(domains)]);
  const list = document.getElementById('list');
  list.innerHTML = '';

  [...names].sort().forEach((host) => {
    const explicit = Object.prototype.hasOwnProperty.call(domains, host);
    const on = explicit ? domains[host] === true : true;

    const li = document.createElement('li');
    if (!on) li.className = 'off';

    const name = document.createElement('span');
    name.className = 'name';
    name.textContent = host;
    li.appendChild(name);

    if (explicit && !DEFAULTS.includes(host)) {
      const badge = document.createElement('span');
      badge.className = 'badge';
      badge.textContent = 'added';
      li.appendChild(badge);
    }

    const toggle = document.createElement('input');
    toggle.type = 'checkbox';
    toggle.checked = on;
    toggle.addEventListener('change', async () => {
      const current = (await get({ domains: {} })).domains || {};
      if (toggle.checked && DEFAULTS.includes(host)) {
        delete current[host];            // back to the built-in default
      } else {
        current[host] = toggle.checked;
      }
      await set({ domains: current });
      render();
    });
    li.appendChild(toggle);
    list.appendChild(li);
  });
}

document.getElementById('add').addEventListener('click', async () => {
  const input = document.getElementById('newDomain');
  const host = input.value.trim().toLowerCase()
    .replace(/^https?:\/\//, '').replace(/^www\./, '').replace(/\/.*$/, '');
  if (!host || !host.includes('.')) return;
  const current = (await get({ domains: {} })).domains || {};
  current[host] = true;
  await set({ domains: current });
  input.value = '';
  render();
});

document.getElementById('newDomain').addEventListener('keydown', (e) => {
  if (e.key === 'Enter') document.getElementById('add').click();
});

render();
