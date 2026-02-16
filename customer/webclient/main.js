const STORAGE_KEYS = {
  email: "ssa.webclient.email",
  rmUrl: "ssa.webclient.requestManagerUrl",
  rmSessionId: "ssa.webclient.requestManagerSessionId",
};

const DEFAULT_RM_URL = "http://localhost:8080";
const INITIAL_MESSAGE = "please introduce yourself and tell me how you can help";

function $(id) {
  const el = document.getElementById(id);
  if (!el) throw new Error(`Missing element: #${id}`);
  return el;
}

function nowTime() {
  return new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function safeTrim(s) {
  return (s ?? "").toString().trim();
}

function isValidEmail(email) {
  const e = safeTrim(email);
  // pragmatic check; server-side auth is out of scope here
  return e.length >= 3 && e.includes("@") && !e.includes(" ");
}

function normalizeBaseUrl(url) {
  const u = safeTrim(url) || DEFAULT_RM_URL;
  return u.endsWith("/") ? u.slice(0, -1) : u;
}

function getOrCreateSessionId() {
  const existing = localStorage.getItem(STORAGE_KEYS.rmSessionId);
  if (existing) return existing;
  const fresh = crypto.randomUUID();
  localStorage.setItem(STORAGE_KEYS.rmSessionId, fresh);
  return fresh;
}

function setAuthError(msg) {
  $("auth-error").textContent = msg ? String(msg) : "";
}

function setChatError(msg) {
  $("chat-error").textContent = msg ? String(msg) : "";
}

function setBusy(isBusy) {
  $("start").disabled = isBusy;
  $("send").disabled = isBusy;
  $("email").disabled = isBusy;
  $("rmUrl").disabled = isBusy;
  $("message").disabled = isBusy;
  $("reset").disabled = isBusy;
  $("changeUser").disabled = isBusy;
}

function showScreen(screen) {
  const auth = $("screen-auth");
  const chat = $("screen-chat");
  if (screen === "auth") {
    auth.classList.remove("hidden");
    chat.classList.add("hidden");
  } else {
    auth.classList.add("hidden");
    chat.classList.remove("hidden");
  }
}

function appendMessage({ role, content, time }) {
  const container = $("messages");
  const msg = document.createElement("div");
  msg.className = `msg ${role === "user" ? "msg--user" : "msg--agent"}`;

  const meta = document.createElement("div");
  meta.className = "msg__meta";

  const roleEl = document.createElement("div");
  roleEl.className = "msg__role";
  roleEl.textContent = role === "user" ? "You" : "Agent";

  const timeEl = document.createElement("div");
  timeEl.className = "msg__time";
  timeEl.textContent = time || nowTime();

  meta.appendChild(roleEl);
  meta.appendChild(timeEl);

  const body = document.createElement("div");
  body.className = "msg__content";
  body.textContent = content ?? "";

  msg.appendChild(meta);
  msg.appendChild(body);
  container.appendChild(msg);

  // autoscroll
  container.scrollTop = container.scrollHeight;
}

function clearMessages() {
  $("messages").innerHTML = "";
}

async function postToRequestManager({ rmUrl, email, content }) {
  const sessionId = getOrCreateSessionId();

  const payload = {
    integration_type: "WEB",
    user_id: email,
    content,
    request_type: "message",
    metadata: {
      // Mirrors what the CLI client sends (extra keys are fine for generic endpoint).
      // See: shared-clients/src/shared_clients/request_manager_client.py (CLIChatClient.send_message)
      command_context: { command: "chat", args: [] },
      request_manager_session_id: sessionId,
      user_email: email,
      session_name: "",
      client: "customer-webclient",
      user_agent: navigator.userAgent || "",
    },
  };

  const res = await fetch(`${rmUrl}/api/v1/requests/generic`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-user-id": email,
    },
    body: JSON.stringify(payload),
  });

  let data;
  try {
    data = await res.json();
  } catch {
    const raw = await res.text();
    throw new Error(`Non-JSON response (${res.status}): ${raw}`);
  }

  if (!res.ok) {
    const detail = data?.detail || data?.error || JSON.stringify(data);
    throw new Error(`Request failed (${res.status}): ${detail}`);
  }

  // Response format can be either:
  // - { response: { content, agent_id, ... }, session_id, request_id, ... }
  // - or (defensive) { content, agent_id, ... }
  const contentOut = data?.response?.content ?? data?.content ?? "";
  const sessionOut = data?.session_id ?? "";
  const requestOut = data?.request_id ?? "";

  return { content: String(contentOut ?? ""), sessionId: sessionOut, requestId: requestOut };
}

function setChatMeta({ email, rmUrl, sessionId }) {
  const meta = [
    `Email: ${email}`,
    `Request Manager: ${rmUrl}`,
    sessionId ? `Session: ${sessionId}` : null,
  ]
    .filter(Boolean)
    .join(" · ");
  $("chat-meta").textContent = meta;
}

async function startChat() {
  setAuthError("");
  setChatError("");

  const email = safeTrim($("email").value);
  const rmUrl = normalizeBaseUrl($("rmUrl").value);

  if (!isValidEmail(email)) {
    setAuthError("Please enter a valid email address.");
    return;
  }

  localStorage.setItem(STORAGE_KEYS.email, email);
  localStorage.setItem(STORAGE_KEYS.rmUrl, rmUrl);

  // Keep per-email session IDs separate (so switching emails doesn’t leak sessions)
  localStorage.setItem(STORAGE_KEYS.rmSessionId, crypto.randomUUID());

  showScreen("chat");
  clearMessages();
  setChatMeta({ email, rmUrl, sessionId: "" });

  setBusy(true);
  try {
    appendMessage({ role: "user", content: INITIAL_MESSAGE });
    const out = await postToRequestManager({ rmUrl, email, content: INITIAL_MESSAGE });
    appendMessage({ role: "agent", content: out.content });
    setChatMeta({ email, rmUrl, sessionId: out.sessionId });
    $("message").focus();
  } catch (e) {
    setChatError(e?.message || String(e));
  } finally {
    setBusy(false);
  }
}

async function sendChatMessage() {
  setChatError("");
  const email = safeTrim(localStorage.getItem(STORAGE_KEYS.email));
  const rmUrl = normalizeBaseUrl(localStorage.getItem(STORAGE_KEYS.rmUrl));
  const msg = safeTrim($("message").value);

  if (!email || !rmUrl) {
    showScreen("auth");
    setAuthError("Missing session info. Please start again.");
    return;
  }

  if (!msg) return;

  $("message").value = "";
  appendMessage({ role: "user", content: msg });

  setBusy(true);
  try {
    const out = await postToRequestManager({ rmUrl, email, content: msg });
    appendMessage({ role: "agent", content: out.content });
    setChatMeta({ email, rmUrl, sessionId: out.sessionId });
  } catch (e) {
    setChatError(e?.message || String(e));
  } finally {
    setBusy(false);
    $("message").focus();
  }
}

async function resetConversation() {
  setChatError("");
  const email = safeTrim(localStorage.getItem(STORAGE_KEYS.email));
  const rmUrl = normalizeBaseUrl(localStorage.getItem(STORAGE_KEYS.rmUrl));
  if (!email || !rmUrl) return;

  // new session id + clear local messages; server-side reset is done by sending "reset"
  localStorage.setItem(STORAGE_KEYS.rmSessionId, crypto.randomUUID());
  clearMessages();

  setBusy(true);
  try {
    appendMessage({ role: "user", content: "reset" });
    const out = await postToRequestManager({ rmUrl, email, content: "reset" });
    appendMessage({ role: "agent", content: out.content });
    setChatMeta({ email, rmUrl, sessionId: out.sessionId });
  } catch (e) {
    setChatError(e?.message || String(e));
  } finally {
    setBusy(false);
    $("message").focus();
  }
}

function changeEmail() {
  setAuthError("");
  setChatError("");
  showScreen("auth");
}

function hydrateFromStorage() {
  const savedEmail = safeTrim(localStorage.getItem(STORAGE_KEYS.email));
  const savedUrl = safeTrim(localStorage.getItem(STORAGE_KEYS.rmUrl));
  if (savedEmail) $("email").value = savedEmail;
  $("rmUrl").value = savedUrl || DEFAULT_RM_URL;
}

function wireEvents() {
  $("auth-form").addEventListener("submit", (e) => {
    e.preventDefault();
    startChat();
  });

  $("chat-form").addEventListener("submit", (e) => {
    e.preventDefault();
    sendChatMessage();
  });

  $("reset").addEventListener("click", () => resetConversation());
  $("changeUser").addEventListener("click", () => changeEmail());
}

hydrateFromStorage();
wireEvents();
showScreen("auth");

