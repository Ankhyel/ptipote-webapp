// decode.js — NFC test decoder (Base32 RFC4648 -> LZString Uint8Array -> "k=v;" pairs)

const EXAMPLE_B32 =
  "FGC6BMQPMCXAZYYQNYALRACKCAJYCLATCARRABDAIARWEEAGYQABQEAD22CCPQQA5XZEAQZGXI7S4AEYAQDGAEAFT4IAA===";

const DEFAULT_NICKNAME = "Ce Ptipote aimerais un surnom";
const DEFAULT_OWNER = "Ce ptipote n'est pas encore adopter... Qu'attend tu ?";
const DEV_SHOW_ALL_FIELDS = true;

function $(id) {
  return document.getElementById(id);
}

function setStatus(msg, kind = "") {
  const el = $("status");
  if (!el) return;
  el.textContent = msg || "";
  el.className = "status " + (kind || "");
}

function setDecodedText(text) {
  const el = $("decodedText");
  if (!el) return;
  el.textContent = text || "";
}

function escapeHtml(s) {
  return String(s)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function looksLikeKV(text) {
  if (!text) return false;
  return /(^|;)\s*([a-z]{1,3}|a[1-4])\s*=/.test(String(text).trim());
}

function parseKV(text) {
  const out = {};
  const parts = String(text || "").split(";");

  for (const part of parts) {
    if (!part) continue;
    const idx = part.indexOf("=");
    if (idx < 0) continue;

    const key = part.slice(0, idx).trim();
    const value = part.slice(idx + 1).trim();

    if (key) out[key] = value;
  }

  return out;
}

function getValue(source, keys) {
  for (const key of keys) {
    if (Object.prototype.hasOwnProperty.call(source, key)) {
      return String(source[key] ?? "").trim();
    }
  }
  return "";
}

function boolFlag(v) {
  const s = String(v ?? "").trim().toLowerCase();
  return s === "1" || s === "true" || s === "yes" || s === "on";
}

function prettyValue(value, fallback = "—") {
  const s = String(value ?? "").trim();
  return s.length ? s : fallback;
}

function normalizedModel(source) {
  const data = source || {};

  const transferRequestedRaw = getValue(data, ["te", "ta"]);
  const transferConfirmedRaw = getValue(data, ["ter"]);

  return {
    species: getValue(data, ["e"]),
    type: getValue(data, ["t"]),
    nickname: getValue(data, ["s"]),
    rarity: getValue(data, ["r"]),
    batch: getValue(data, ["b"]),
    level: getValue(data, ["l", "n"]),
    xp: getValue(data, ["x"]),
    ownerName: getValue(data, ["o"]),
    ownerId: getValue(data, ["on"]),
    transferRequested: boolFlag(transferRequestedRaw),
    transferConfirmed: boolFlag(transferConfirmedRaw),
    accessories: [
      getValue(data, ["a1"]),
      getValue(data, ["a2"]),
      getValue(data, ["a3"]),
      getValue(data, ["a4"]),
    ],
  };
}

function createField(label, value, className = "") {
  const row = document.createElement("div");
  row.className = "field" + (className ? " " + className : "");
  row.innerHTML = `
    <div class="k">${escapeHtml(label)}</div>
    <div class="v">${escapeHtml(value)}</div>
  `;
  return row;
}

function createTransferField(confirmed) {
  const row = document.createElement("div");
  row.className = "field field--transfer";
  row.innerHTML = `
    <div class="k">Transfert de l’éleveur</div>
    <button class="transferBtn ${confirmed ? "confirmed" : "pending"}" disabled>
      ${escapeHtml(confirmed ? "Transfert confirmer" : "Transfert en cours")}
    </button>
  `;
  return row;
}

function renderFields(source) {
  const wrap = $("fields");
  if (!wrap) return;

  wrap.innerHTML = "";

  const model = normalizedModel(source);

  wrap.appendChild(createField("Espèce", prettyValue(model.species)));
  wrap.appendChild(createField("Type", prettyValue(model.type)));
  wrap.appendChild(createField("Surnom", prettyValue(model.nickname, DEFAULT_NICKNAME)));
  wrap.appendChild(createField("Rareté", prettyValue(model.rarity)));
  wrap.appendChild(createField("Niveau", prettyValue(model.level)));
  wrap.appendChild(createField("Xp", prettyValue(model.xp)));
  wrap.appendChild(createField("Nom de l’éleveur", prettyValue(model.ownerName, DEFAULT_OWNER)));

  if (DEV_SHOW_ALL_FIELDS) {
    wrap.appendChild(createField("Numéro de l’éleveur (owner_id)", prettyValue(model.ownerId, "Aucun")));
    wrap.appendChild(createField("Transfert demandé (te/ta)", model.transferRequested ? "1" : "0"));
    wrap.appendChild(createField("Transfert confirmé (ter)", model.transferConfirmed ? "1" : "0"));
  }

  for (let i = 0; i < model.accessories.length; i++) {
    wrap.appendChild(createField(`Accessoire ${i + 1}`, prettyValue(model.accessories[i], "Aucun")));
  }

  if (model.transferRequested || model.transferConfirmed) {
    wrap.appendChild(createTransferField(model.transferConfirmed));
  }

  wrap.appendChild(createField("Batch", prettyValue(model.batch)));
}

function decodeBase32ToBytes(b32) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

  let s = String(b32 || "")
    .trim()
    .replace(/^#/, "")
    .replace(/[\s-]+/g, "")
    .toUpperCase();

  s = s.replace(/0/g, "O").replace(/1/g, "I").replace(/=+$/g, "");

  let bits = "";
  for (const ch of s) {
    const value = alphabet.indexOf(ch);
    if (value === -1) {
      throw new Error(`Base32 invalide: '${ch}' (autorisé: A–Z et 2–7)`);
    }
    bits += value.toString(2).padStart(5, "0");
  }

  const byteLen = Math.floor(bits.length / 8);
  const out = new Uint8Array(byteLen);

  for (let i = 0; i < byteLen; i++) {
    out[i] = parseInt(bits.slice(i * 8, i * 8 + 8), 2);
  }

  return out;
}

function decodeLZ(bytes) {
  if (!bytes || bytes.length === 0) {
    throw new Error("Chaîne Base32 vide ou invalide.");
  }

  if (typeof LZString === "undefined" || typeof LZString.decompress !== "function") {
    throw new Error("LZString.decompress indisponible (lz-string.min.js non chargé).");
  }

  // Compatible with compressToUint8Array from the encoder:
  // each UTF-16 code unit is stored as 2 bytes (big-endian).
  function safeDecompressFromUint8Array(arr) {
    if (!arr || arr.length === 0) return "";
    const pairCount = Math.floor(arr.length / 2);
    const chars = new Array(pairCount);
    for (let i = 0; i < pairCount; i++) {
      chars[i] = String.fromCharCode((arr[i * 2] << 8) | arr[i * 2 + 1]);
    }
    return LZString.decompress(chars.join(""));
  }

  const maxTrim = Math.min(24, bytes.length);
  let fallback = null;

  for (let trim = 0; trim <= maxTrim; trim++) {
    const arr = trim === 0 ? bytes : bytes.slice(0, bytes.length - trim);
    const text = safeDecompressFromUint8Array(arr);

    if (text && looksLikeKV(text)) {
      return { text, trimmed: trim };
    }

    if (!fallback && text && String(text).trim().length) {
      fallback = { text, trimmed: trim };
    }
  }

  if (fallback) {
    return fallback;
  }

  throw new Error("Décompression LZ vide (Base32 OK mais payload non-LZ ou corrompu).");
}

function onDecode() {
  const raw = ($("input")?.value || "").trim();

  if (!raw) {
    setStatus("Colle une chaîne Base32.", "warn");
    setDecodedText("");
    renderFields({});
    return;
  }

  try {
    setStatus("Décodage en cours…", "");

    const bytes = decodeBase32ToBytes(raw);
    const lz = decodeLZ(bytes);

    setDecodedText(lz.text);

    const data = parseKV(lz.text);

    if (!looksLikeKV(lz.text) || Object.keys(data).length === 0) {
      setStatus(`Décodage OK ✅ (LZ${lz.trimmed ? ", trim=" + lz.trimmed : ""}) mais format non-KV`, "warn");
      renderFields({});
      return;
    }

    setStatus(`Décodage OK ✅ (LZ${lz.trimmed ? ", trim=" + lz.trimmed : ""})`, "ok");
    renderFields(data);
  } catch (e) {
    console.error(e);
    setStatus("Erreur: " + (e?.message || String(e)), "err");
    setDecodedText("");
    renderFields({});
  }
}

function setExample() {
  const input = $("input");
  if (!input) return;
  input.value = EXAMPLE_B32;
  onDecode();
}

function clearAll() {
  const input = $("input");
  if (input) input.value = "";

  setDecodedText("");
  renderFields({});
  setStatus("");

  if (location.hash) {
    history.replaceState(null, "", location.pathname + location.search);
  }
}

function init() {
  $("btnDecode")?.addEventListener("click", onDecode);
  $("btnFillExample")?.addEventListener("click", setExample);
  $("btnClear")?.addEventListener("click", clearAll);

  const hash = (location.hash || "").replace(/^#/, "").trim();
  if (hash) {
    const input = $("input");
    if (input) input.value = hash;
    onDecode();
    return;
  }

  renderFields({});
}

window.PTIPOTE_DECODE = {
  init,
  onDecode,
  parseKV,
  renderFields,
  decodeBase32ToBytes,
  decodeLZ,
  normalizedModel,
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init);
} else {
  init();
}
