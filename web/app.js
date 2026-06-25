"use strict";

/* ------------------------------------------------------------------ *
 * Theater Notes — push-to-talk note taking for rehearsals & tech.
 * Vanilla JS, no build step. State persists to localStorage.
 * ------------------------------------------------------------------ */

const STORAGE_KEY = "theater-notes-state-v1";

/* ----------------------------- State ----------------------------- */

const defaultState = () => ({
  castTemplate: [],     // [{id, name, role}]
  sessions: [],         // [{id, title, createdAt, endedAt, cast, notes}]
  activeSessionId: null,
});

let state = loadState();
let currentTab = "record";
let detailSessionId = null; // when viewing a session in History

function loadState() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) return Object.assign(defaultState(), JSON.parse(raw));
  } catch (e) { /* ignore */ }
  return defaultState();
}

function saveState() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  } catch (e) {
    console.error("save failed", e);
  }
}

const uid = () =>
  (crypto.randomUUID ? crypto.randomUUID()
    : Date.now().toString(36) + Math.random().toString(36).slice(2));

function activeSession() {
  return state.sessions.find((s) => s.id === state.activeSessionId) || null;
}
function getSession(id) {
  return state.sessions.find((s) => s.id === id) || null;
}

/* --------------------------- Utilities --------------------------- */

const $ = (sel, root = document) => root.querySelector(sel);
const el = (tag, props = {}, ...children) => {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (k === "class") node.className = v;
    else if (k === "html") node.innerHTML = v;
    else if (k.startsWith("on") && typeof v === "function") {
      node.addEventListener(k.slice(2).toLowerCase(), v);
    } else if (v !== null && v !== undefined && v !== false) {
      node.setAttribute(k, v);
    }
  }
  for (const c of children.flat()) {
    if (c == null || c === false) continue;
    node.append(c.nodeType ? c : document.createTextNode(String(c)));
  }
  return node;
};

const trimmed = (s) => (s || "").trim();
function fmtTime(ts) {
  return new Date(ts).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}
function fmtDate(ts) {
  return new Date(ts).toLocaleDateString([], { year: "numeric", month: "short", day: "numeric" }) +
    " · " + fmtTime(ts);
}

/* ----------------------- Name matching --------------------------- */
/* Mirrors the iOS NameMatcher: fuzzy-match the leading word(s) of a
   transcript against the cast, strip the name, return [assigned, note]. */

const NameMatcher = {
  match(raw, cast) {
    const transcript = trimmed(raw);
    if (!transcript) return [null, ""];
    if (!cast.length) return [null, capitalize(transcript)];

    const words = transcript.split(/\s+/);
    const maxLead = Math.min(3, words.length);
    for (let lead = maxLead; lead >= 1; lead--) {
      const phrase = words.slice(0, lead).join(" ");
      const norm = normalize(phrase);
      if (!norm) continue;
      const member = this.bestMatch(norm, cast);
      if (member) {
        const remainder = stripLeadingSeparators(words.slice(lead).join(" "));
        return [member.name, capitalize(remainder)];
      }
    }
    return [null, capitalize(transcript)];
  },

  bestMatch(norm, cast) {
    let best = null;
    for (const member of cast) {
      for (const variant of variants(member.name)) {
        const v = normalize(variant);
        if (!v) continue;
        const dist = levenshtein(norm, v);
        const score = 1 - dist / Math.max(norm.length, v.length);
        const accept = norm === v ||
          (dist <= 1 && Math.min(norm.length, v.length) >= 3) ||
          score >= 0.85;
        if (accept && (!best || score > best.score)) best = { member, score };
      }
    }
    return best ? best.member : null;
  },
};

function variants(name) {
  const parts = name.split(/\s+/).filter(Boolean);
  const out = [name];
  if (parts[0]) out.push(parts[0]);
  if (parts.length > 1) out.push(parts[parts.length - 1]);
  return out;
}
function normalize(s) {
  return s.toLowerCase().replace(/[^a-z\s]/g, "").trim();
}
function stripLeadingSeparators(s) {
  return s.replace(/^[\s,:;.\-—]+/, "").trim();
}
function capitalize(s) {
  return s ? s.charAt(0).toUpperCase() + s.slice(1) : s;
}
function levenshtein(a, b) {
  if (a === b) return 0;
  if (!a.length) return b.length;
  if (!b.length) return a.length;
  let prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  let cur = new Array(b.length + 1);
  for (let i = 1; i <= a.length; i++) {
    cur[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
    }
    [prev, cur] = [cur, prev];
  }
  return prev[b.length];
}

/* --------------------- Speech recognition ------------------------ */

const SpeechRec = window.SpeechRecognition || window.webkitSpeechRecognition;
const speechSupported = !!SpeechRec;

let recognition = null;
let currentNoteId = null;
let interimText = "";
let finalText = "";
let isRecording = false;

function startRecording(sessionId) {
  if (isRecording || !speechSupported) return;
  const session = getSession(sessionId);
  if (!session) return;

  isRecording = true;
  interimText = "";
  finalText = "";

  const note = {
    id: uid(),
    createdAt: Date.now(),
    transcript: "",
    rawTranscript: "",
    assignedCastName: null,
    status: "recording",
  };
  currentNoteId = note.id;
  session.notes.push(note);
  saveState();
  renderNotesList();
  updatePttUI();

  recognition = new SpeechRec();
  recognition.lang = "en-US";
  recognition.interimResults = true;
  recognition.continuous = true;
  recognition.maxAlternatives = 1;

  recognition.onresult = (event) => {
    interimText = "";
    for (let i = event.resultIndex; i < event.results.length; i++) {
      const res = event.results[i];
      if (res.isFinal) finalText += res[0].transcript + " ";
      else interimText += res[0].transcript;
    }
    updateInterim();
  };

  recognition.onerror = (event) => {
    console.warn("speech error", event.error);
    if (event.error === "not-allowed" || event.error === "service-not-allowed") {
      finishRecording(sessionId, { permission: true });
    }
  };

  recognition.onend = () => {
    // Fires after stop() (or natural end). Finalize the note.
    if (isRecording) finishRecording(sessionId);
  };

  try {
    recognition.start();
  } catch (e) {
    console.error("recognition start failed", e);
    finishRecording(sessionId);
  }
}

function stopRecording() {
  if (!isRecording || !recognition) return;
  try { recognition.stop(); } catch (e) { /* ignore */ }
  // finishRecording is triggered by onend.
}

function finishRecording(sessionId, opts = {}) {
  if (!isRecording) return;
  isRecording = false;
  const rec = recognition;
  recognition = null;
  if (rec) { rec.onend = null; rec.onresult = null; rec.onerror = null; }

  const session = getSession(sessionId);
  const note = session && session.notes.find((n) => n.id === currentNoteId);
  const raw = trimmed(finalText + " " + interimText);
  currentNoteId = null;
  interimText = "";
  updatePttUI();

  if (!note) return;

  if (opts.permission) {
    note.status = "failed";
    note.transcript = "Microphone/speech permission denied.";
  } else if (!raw) {
    // Nothing captured — drop the empty note.
    session.notes = session.notes.filter((n) => n.id !== note.id);
    saveState();
    renderNotesList();
    return;
  } else {
    const [assigned, text] = NameMatcher.match(raw, session.cast);
    note.rawTranscript = raw;
    note.transcript = text || raw;
    note.assignedCastName = assigned;
    note.status = "done";
  }
  saveState();
  renderNotesList();
}

/* ----------------------------- Views ----------------------------- */

const content = () => $("#app-content");
const headerActions = () => $("#header-actions");
const headerTitle = () => $("#header-title");

function render() {
  document.querySelectorAll(".tab").forEach((t) =>
    t.classList.toggle("active", t.dataset.tab === currentTab));
  headerActions().innerHTML = "";
  if (currentTab === "record") renderRecord();
  else if (currentTab === "cast") renderCast();
  else if (currentTab === "history") renderHistory();
}

/* ---- Record tab ---- */

function renderRecord() {
  headerTitle().textContent = "Theater Notes";
  const c = content();
  c.innerHTML = "";

  const session = activeSession();
  if (!session) { renderStartSession(c); return; }

  headerTitle().textContent = session.title;
  headerActions().append(
    el("button", { class: "icon-btn", onClick: () => openCastSheet(session.id) }, "🎭 Cast")
  );

  const wrap = el("div", { class: "record-wrap" });
  const notesScroll = el("div", { class: "notes-scroll", id: "notes-scroll" });
  const list = el("div", { id: "notes-list" });
  notesScroll.append(list);

  const ptt = el("div", { class: "ptt-area" });
  const interim = el("div", { class: "interim", id: "interim" });
  const btn = el("button", { class: "ptt-button", id: "ptt-button" },
    el("span", { class: "ptt-emoji" }, "🎙️"),
    el("span", { id: "ptt-label" }, "Hold to Talk")
  );
  if (!speechSupported) {
    btn.disabled = true;
  }
  bindPushToTalk(btn, session.id);

  const hint = el("div", { class: "ptt-hint" },
    "Say the cast name first, e.g. “Sarah, your cross is late.”");
  const endBtn = el("button", { class: "btn danger", onClick: () => endSession() },
    "■ End Show");

  ptt.append(interim, btn, hint, endBtn);
  wrap.append(notesScroll, ptt);
  c.append(wrap);

  if (!speechSupported) {
    notesScroll.prepend(el("div", { class: "banner" },
      "This browser doesn’t support speech recognition. Try Chrome (Android/desktop) or Safari (iOS)."));
  }
  renderNotesList();
}

function renderStartSession(c) {
  let title = "";
  const titleInput = el("input", {
    type: "text", placeholder: "Show / session title",
    oninput: (e) => { title = e.target.value; startBtn.disabled = !trimmed(title); },
  });

  const castCard = el("div", { class: "card" });
  castCard.append(el("div", { class: "section-title" }, `Cast (${state.castTemplate.length})`));
  if (!state.castTemplate.length) {
    castCard.append(el("div", { class: "small muted" },
      "No cast added yet. Add names in the Cast tab so notes can be matched to people. You can still record without a cast — those notes go to “Everyone”."));
  } else {
    state.castTemplate.forEach((m) =>
      castCard.append(el("div", { class: "row small" },
        el("span", {}, m.name),
        m.role ? el("span", { class: "muted" }, m.role) : null)));
  }

  const startBtn = el("button", { class: "btn", disabled: "true",
    onClick: () => { startSession(trimmed(title)); } }, "▶ Start Show");

  c.append(
    el("div", { class: "card" },
      el("div", { class: "section-title" }, "New Show Session"),
      titleInput),
    castCard,
    startBtn
  );
}

function renderNotesList() {
  const list = $("#notes-list");
  if (!list) return;
  const session = activeSession();
  if (!session) return;
  list.innerHTML = "";

  if (!session.notes.length) {
    list.append(el("div", { class: "empty" },
      el("div", { class: "big" }, "🎙️"),
      el("div", {}, "No notes yet"),
      el("div", { class: "small muted" }, "Hold the button below and speak your note.")));
    return;
  }
  [...session.notes].reverse().forEach((note) => list.append(noteRowCompact(note)));
}

function noteRowCompact(note) {
  const who = note.assignedCastName || "Everyone";
  const meta = el("div", { class: "meta" },
    el("span", { class: "who" + (note.assignedCastName ? "" : " everyone") },
      (note.assignedCastName ? "👤 " : "👥 ") + who));

  if (note.status === "recording" || note.status === "transcribing") {
    meta.append(el("span", { class: "time" }, el("span", { class: "spinner" })));
  } else if (note.status === "failed") {
    meta.append(el("span", { class: "time" }, "⚠️"));
  } else {
    meta.append(el("span", { class: "time" }, fmtTime(note.createdAt)));
  }

  let text, dim = false;
  if (note.status === "recording") { text = "● Recording…"; dim = true; }
  else if (note.status === "transcribing") { text = "Transcribing…"; dim = true; }
  else if (note.status === "failed") { text = note.transcript || "Couldn’t transcribe."; dim = true; }
  else { text = note.transcript || "(no speech detected)"; dim = !note.transcript; }

  return el("div", { class: "note" }, meta,
    el("div", { class: "text" + (dim ? " dim" : "") }, text));
}

function updateInterim() {
  const node = $("#interim");
  if (node) node.textContent = interimText;
}
function updatePttUI() {
  const btn = $("#ptt-button");
  const label = $("#ptt-label");
  if (btn) btn.classList.toggle("recording", isRecording);
  if (label) label.textContent = isRecording ? "Recording…" : "Hold to Talk";
  if (!isRecording) updateInterim();
}

function bindPushToTalk(btn, sessionId) {
  const down = (e) => { e.preventDefault(); startRecording(sessionId); };
  const up = (e) => { e.preventDefault(); stopRecording(); };
  btn.addEventListener("pointerdown", down);
  btn.addEventListener("pointerup", up);
  btn.addEventListener("pointercancel", up);
  btn.addEventListener("pointerleave", (e) => { if (isRecording) up(e); });
}

/* ---- Cast tab ---- */

function renderCast() {
  headerTitle().textContent = "Cast";
  const c = content();
  c.innerHTML = "";
  c.append(castEditor(
    () => state.castTemplate,
    (next) => { state.castTemplate = next; saveState(); },
    "This cast list is used for new shows and helps match each note to the right person."
  ));
}

function castEditor(getList, setList, footer) {
  const wrap = el("div", {});
  const card = el("div", { class: "card" });
  card.append(el("div", { class: "section-title" }, "Cast Members"));

  const list = getList();
  if (!list.length) {
    card.append(el("div", { class: "small muted" }, "No cast members yet."));
  } else {
    list.forEach((m, idx) => {
      const nameInput = el("input", { type: "text", value: m.name, placeholder: "Name",
        oninput: (e) => { const l = getList(); l[idx].name = e.target.value; setList(l); } });
      const roleInput = el("input", { type: "text", value: m.role || "", placeholder: "Role (optional)",
        class: "role-input",
        oninput: (e) => { const l = getList(); l[idx].role = e.target.value; setList(l); } });
      const del = el("button", { class: "delete-x", title: "Remove",
        onClick: () => { const l = getList(); l.splice(idx, 1); setList(l); rerenderEditor(); } }, "×");
      card.append(el("div", { class: "cast-item" },
        el("div", { class: "line" }, nameInput, del),
        roleInput));
    });
  }
  if (footer) card.append(el("div", { class: "small muted", style: "margin-top:8px" }, footer));

  let newName = "", newRole = "";
  const addCard = el("div", { class: "card" });
  const addBtn = el("button", { class: "btn secondary", disabled: "true",
    onClick: () => {
      const l = getList();
      l.push({ id: uid(), name: trimmed(newName), role: trimmed(newRole) });
      setList(l);
      rerenderEditor();
    } }, "+ Add Member");
  const nameNew = el("input", { type: "text", placeholder: "Name",
    oninput: (e) => { newName = e.target.value; addBtn.disabled = !trimmed(newName); } });
  const roleNew = el("input", { type: "text", placeholder: "Role (optional)", class: "role-input",
    style: "margin-top:8px",
    oninput: (e) => { newRole = e.target.value; } });
  addCard.append(el("div", { class: "section-title" }, "Add Member"), nameNew, roleNew,
    el("div", { style: "margin-top:10px" }, addBtn));

  wrap.append(card, addCard);

  function rerenderEditor() {
    const fresh = castEditor(getList, setList, footer);
    wrap.replaceWith(fresh);
  }
  return wrap;
}

/* In-session cast sheet (reuses the editor against the session's cast) */
function openCastSheet(sessionId) {
  const session = getSession(sessionId);
  if (!session) return;
  const c = content();
  c.innerHTML = "";
  headerTitle().textContent = "Show Cast";
  headerActions().innerHTML = "";
  headerActions().append(el("button", { class: "icon-btn", onClick: () => render() }, "Done"));
  c.append(castEditor(
    () => session.cast,
    (next) => { session.cast = next; saveState(); },
    "Add or fix names mid-show. Changes apply to this session."
  ));
}

/* ---- History tab ---- */

function renderHistory() {
  if (detailSessionId) { renderSessionDetail(detailSessionId); return; }
  headerTitle().textContent = "History";
  const c = content();
  c.innerHTML = "";

  if (!state.sessions.length) {
    c.append(el("div", { class: "empty" },
      el("div", { class: "big" }, "🕑"),
      el("div", {}, "No shows yet"),
      el("div", { class: "small muted" }, "Start a show in the Record tab to capture notes.")));
    return;
  }

  const sorted = [...state.sessions].sort((a, b) => b.createdAt - a.createdAt);
  sorted.forEach((s) => {
    const row = el("div", { class: "card session-row", onClick: () => { detailSessionId = s.id; render(); } },
      el("div", { class: "title" }, s.title,
        s.id === state.activeSessionId ? el("span", { class: "badge-live" }, "LIVE") : null),
      el("div", { class: "small muted" }, fmtDate(s.createdAt)),
      el("div", { class: "small muted" }, `${s.notes.length} note${s.notes.length === 1 ? "" : "s"}`));
    const del = el("button", { class: "icon-btn", style: "margin-bottom:14px",
      onClick: (e) => { e.stopPropagation(); deleteSession(s.id); } }, "🗑 Delete");
    c.append(row);
    c.append(del);
  });
}

function renderSessionDetail(sessionId) {
  const session = getSession(sessionId);
  headerActions().innerHTML = "";
  headerActions().append(
    el("button", { class: "icon-btn", onClick: () => { detailSessionId = null; render(); } }, "‹ Back"),
    el("button", { class: "icon-btn", onClick: () => shareSession(session) }, "⤴ Share")
  );
  const c = content();
  c.innerHTML = "";

  if (!session) { c.append(el("div", { class: "empty" }, "Session not found")); return; }
  headerTitle().textContent = session.title;

  if (!session.notes.length) {
    c.append(el("div", { class: "empty" }, el("div", { class: "big" }, "📝"), "No notes in this session."));
    return;
  }

  for (const group of groupNotes(session)) {
    c.append(el("div", { class: "group-header" }, group.title,
      group.role ? el("span", { class: "role" }, group.role) : null));
    group.notes.forEach((note) => c.append(noteDetailRow(session, note)));
  }
}

function groupNotes(session) {
  const groups = [];
  const everyone = session.notes.filter((n) => !n.assignedCastName)
    .sort((a, b) => a.createdAt - b.createdAt);
  if (everyone.length) groups.push({ title: "Everyone", role: "", notes: everyone });

  for (const m of session.cast) {
    const notes = session.notes.filter((n) => n.assignedCastName === m.name)
      .sort((a, b) => a.createdAt - b.createdAt);
    if (notes.length) groups.push({ title: m.name, role: m.role || "", notes });
  }

  const known = new Set(session.cast.map((m) => m.name));
  const orphans = [...new Set(session.notes.map((n) => n.assignedCastName)
    .filter((n) => n && !known.has(n)))].sort();
  for (const name of orphans) {
    const notes = session.notes.filter((n) => n.assignedCastName === name)
      .sort((a, b) => a.createdAt - b.createdAt);
    groups.push({ title: name, role: "", notes });
  }
  return groups;
}

function noteDetailRow(session, note) {
  const ta = el("textarea", { rows: "1",
    oninput: (e) => {
      note.transcript = e.target.value;
      saveState();
      e.target.style.height = "auto";
      e.target.style.height = e.target.scrollHeight + "px";
    } });
  ta.value = note.transcript;
  // Auto-size after insertion.
  requestAnimationFrame(() => { ta.style.height = "auto"; ta.style.height = ta.scrollHeight + "px"; });

  const select = el("select", {
    onChange: (e) => {
      note.assignedCastName = e.target.value || null;
      saveState();
      detailSessionId = session.id; render();
    } });
  select.append(el("option", { value: "" }, "Everyone"));
  for (const m of session.cast) {
    const opt = el("option", { value: m.name }, m.name);
    if (m.name === note.assignedCastName) opt.selected = true;
    select.append(opt);
  }
  // Keep an orphaned name selectable.
  if (note.assignedCastName && !session.cast.some((m) => m.name === note.assignedCastName)) {
    const opt = el("option", { value: note.assignedCastName }, note.assignedCastName);
    opt.selected = true;
    select.append(opt);
  }

  const del = el("button", { class: "icon-btn",
    onClick: () => {
      session.notes = session.notes.filter((n) => n.id !== note.id);
      saveState();
      detailSessionId = session.id; render();
    } }, "🗑");

  return el("div", { class: "note" },
    el("div", { class: "meta" }, el("span", { class: "time" }, fmtTime(note.createdAt))),
    ta,
    el("div", { class: "controls" }, select, el("span", { class: "spacer" }), del));
}

/* --------------------------- Actions ----------------------------- */

function startSession(title) {
  if (!title) return;
  const session = {
    id: uid(),
    title,
    createdAt: Date.now(),
    endedAt: null,
    cast: state.castTemplate.map((m) => ({ ...m })),
    notes: [],
  };
  state.sessions.push(session);
  state.activeSessionId = session.id;
  saveState();
  render();
}

function endSession() {
  if (!confirm("End this show session?")) return;
  if (isRecording) stopRecording();
  const session = activeSession();
  if (session) session.endedAt = Date.now();
  state.activeSessionId = null;
  saveState();
  render();
}

function deleteSession(id) {
  if (!confirm("Delete this session and all its notes?")) return;
  state.sessions = state.sessions.filter((s) => s.id !== id);
  if (state.activeSessionId === id) state.activeSessionId = null;
  saveState();
  render();
}

function exportText(session) {
  const lines = [session.title, fmtDate(session.createdAt), "=".repeat(28)];
  for (const group of groupNotes(session)) {
    lines.push("", group.title.toUpperCase() + ":");
    for (const note of group.notes) {
      const t = trimmed(note.transcript) || "(no transcript)";
      lines.push("  • " + t);
    }
  }
  return lines.join("\n");
}

async function shareSession(session) {
  const text = exportText(session);
  if (navigator.share) {
    try { await navigator.share({ title: session.title, text }); return; } catch (e) { /* cancelled */ }
  }
  try {
    await navigator.clipboard.writeText(text);
    alert("Notes copied to clipboard.");
  } catch (e) {
    prompt("Copy your notes:", text);
  }
}

/* --------------------------- Bootstrap --------------------------- */

document.querySelectorAll(".tab").forEach((tab) => {
  tab.addEventListener("click", () => {
    currentTab = tab.dataset.tab;
    detailSessionId = null;
    render();
  });
});

render();

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("sw.js").catch(() => {});
  });
}
