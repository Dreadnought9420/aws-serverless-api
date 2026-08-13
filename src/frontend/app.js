"use strict";

// Same-origin: CloudFront routes /api/* to the HTTP API, so no base URL,
// no CORS preflight and no API host baked into the bundle.
const API = "/api";

const els = {
  form: document.getElementById("item-form"),
  input: document.getElementById("message"),
  submit: document.getElementById("submit"),
  list: document.getElementById("items"),
  empty: document.getElementById("empty"),
  error: document.getElementById("error"),
  healthDot: document.getElementById("health-dot"),
  healthText: document.getElementById("health-text"),
};

function showError(message) {
  els.error.textContent = message;
  els.error.hidden = !message;
}

async function request(path, options = {}) {
  const response = await fetch(path, {
    headers: { "content-type": "application/json" },
    ...options,
  });
  if (response.status === 204) return null;
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload.error || `Request failed with status ${response.status}`);
  }
  return payload;
}

function render(items) {
  els.list.replaceChildren();
  els.empty.hidden = items.length > 0;

  for (const item of items) {
    const li = document.createElement("li");
    // textContent, never innerHTML: user input is never parsed as markup.
    const text = document.createElement("span");
    text.textContent = item.message;

    const stamp = document.createElement("time");
    const created = new Date(item.created_at * 1000);
    stamp.dateTime = created.toISOString();
    stamp.textContent = created.toLocaleString();

    li.append(text, stamp);
    els.list.append(li);
  }
}

async function loadItems() {
  try {
    const data = await request(`${API}/items?limit=25`);
    render(data.items ?? []);
    showError("");
  } catch (error) {
    showError(`Could not load messages: ${error.message}`);
  }
}

async function checkHealth() {
  try {
    const data = await request(`${API}/health`);
    els.healthDot.classList.add("ok");
    els.healthText.textContent = `API healthy — ${data.service}`;
  } catch (error) {
    els.healthDot.classList.add("bad");
    els.healthText.textContent = `API unreachable: ${error.message}`;
  }
}

els.form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const message = els.input.value.trim();
  if (!message) return;

  els.submit.disabled = true;
  try {
    await request(`${API}/items`, {
      method: "POST",
      body: JSON.stringify({ message }),
    });
    els.input.value = "";
    showError("");
    await loadItems();
  } catch (error) {
    showError(error.message);
  } finally {
    els.submit.disabled = false;
  }
});

checkHealth();
loadItems();
