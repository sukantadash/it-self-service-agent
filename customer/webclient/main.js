const STORAGE_KEYS = {
  email: "ssa.webclient.email",
  rmSessionId: "ssa.webclient.requestManagerSessionId",
};

// Sent silently on chat start so the agent greets first
const INITIAL_MESSAGE = "Tell me how you can help";
// Client-side abort timeout (5 min) — must match the Route annotation
const FETCH_TIMEOUT_MS = 5 * 60 * 1000;

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
  return e.length >= 3 && e.includes("@") && !e.includes(" ");
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

/** Show a typing indicator bubble in the messages area. Returns a remove() handle. */
function showTypingIndicator() {
  const container = $("messages");
  const indicator = document.createElement("div");
  indicator.className = "msg msg--agent typing-indicator";
  indicator.innerHTML = `
    <div class="msg__meta">
      <div class="msg__role">Agent</div>
      <div class="msg__time">${nowTime()}</div>
    </div>
    <div class="msg__content typing-dots">
      <span></span><span></span><span></span>
    </div>`;
  container.appendChild(indicator);
  container.scrollTop = container.scrollHeight;

  return {
    remove() {
      if (indicator.parentNode) indicator.parentNode.removeChild(indicator);
    },
  };
}

function clearMessages() {
  $("messages").innerHTML = "";
}

// --------------- API communication ---------------

async function postToRequestManager({ email, content }) {
  const sessionId = getOrCreateSessionId();

  const payload = {
    integration_type: "WEB",
    user_id: email,
    content,
    request_type: "message",
    metadata: {
      command_context: { command: "chat", args: [] },
      request_manager_session_id: sessionId,
      user_email: email,
      session_name: "",
      client: "customer-webclient",
      user_agent: navigator.userAgent || "",
    },
  };

  // Abort controller — 5 min safety net (matches Route annotation)
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);

  try {
    const res = await fetch("/api/v1/requests/generic", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-user-id": email,
      },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });

    // Read body as text first to avoid "body stream already read" error
    const raw = await res.text();

    let data;
    try {
      data = JSON.parse(raw);
    } catch {
      throw new Error(`Non-JSON response (${res.status}): ${raw.slice(0, 300)}`);
    }

    if (!res.ok) {
      const detail = data?.detail || data?.error || JSON.stringify(data);
      throw new Error(`Request failed (${res.status}): ${detail}`);
    }

    const contentOut = data?.response?.content ?? data?.content ?? "";
    const sessionOut = data?.session_id ?? "";
    const requestOut = data?.request_id ?? "";

    return { content: String(contentOut ?? ""), sessionId: sessionOut, requestId: requestOut };
  } catch (err) {
    if (err.name === "AbortError") {
      throw new Error("Request timed out — the agent is taking too long. Please try again.");
    }
    throw err;
  } finally {
    clearTimeout(timeout);
  }
}

function setChatMeta({ email, sessionId }) {
  const meta = [
    `Email: ${email}`,
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

  if (!isValidEmail(email)) {
    setAuthError("Please enter a valid email address.");
    return;
  }

  localStorage.setItem(STORAGE_KEYS.email, email);
  localStorage.setItem(STORAGE_KEYS.rmSessionId, crypto.randomUUID());

  showScreen("chat");
  clearMessages();
  setChatMeta({ email, sessionId: "" });

  // Send INITIAL_MESSAGE silently — don't show it in the chat.
  // Only the agent's reply appears, so it looks agent-initiated.
  setBusy(true);
  const typing = showTypingIndicator();
  try {
    const out = await postToRequestManager({ email, content: INITIAL_MESSAGE });
    typing.remove();
    appendMessage({ role: "agent", content: out.content });
    setChatMeta({ email, sessionId: out.sessionId });
    $("message").focus();
  } catch (e) {
    typing.remove();
    setChatError(e?.message || String(e));
  } finally {
    setBusy(false);
  }
}

async function sendChatMessage() {
  setChatError("");
  const email = safeTrim(localStorage.getItem(STORAGE_KEYS.email));
  const msg = safeTrim($("message").value);

  if (!email) {
    showScreen("auth");
    setAuthError("Missing session info. Please start again.");
    return;
  }

  if (!msg) return;

  $("message").value = "";
  appendMessage({ role: "user", content: msg });

  setBusy(true);
  const typing = showTypingIndicator();
  try {
    const out = await postToRequestManager({ email, content: msg });
    typing.remove();
    appendMessage({ role: "agent", content: out.content });
    setChatMeta({ email, sessionId: out.sessionId });
  } catch (e) {
    typing.remove();
    setChatError(e?.message || String(e));
  } finally {
    setBusy(false);
    $("message").focus();
  }
}

async function resetConversation() {
  setChatError("");
  const email = safeTrim(localStorage.getItem(STORAGE_KEYS.email));
  if (!email) return;

  localStorage.setItem(STORAGE_KEYS.rmSessionId, crypto.randomUUID());
  clearMessages();

  setBusy(true);
  const typing = showTypingIndicator();
  try {
    appendMessage({ role: "user", content: "reset" });
    const out = await postToRequestManager({ email, content: "reset" });
    typing.remove();
    appendMessage({ role: "agent", content: out.content });
    setChatMeta({ email, sessionId: out.sessionId });
  } catch (e) {
    typing.remove();
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
  if (savedEmail) $("email").value = savedEmail;
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
