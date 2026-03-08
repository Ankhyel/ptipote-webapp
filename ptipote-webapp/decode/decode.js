// decode.js — UI + decode Base32 -> (try) LZString -> parse key=value; pairs
// Compatible IDs (index.html): input, btnDecode, btnFillExample, btnClear, status, decodedText, fields

const FIELD_LABELS = {
  e: "Espèce",
  t: "Type",
  s: "Surnom",
  r: "Rareté",
  b: "Batch",
  l: "Niveau",
  x: "XP",
  o: "Nom de l’éleveur",
  on: "Numéro de l’éleveur",
  te: "Transfert de l’éleveur",
  ta: "Transfert accepté",
  a1: "Accessoire 1",
  a2: "Accessoire 2",
  a3: "Accessoire 3",
  a4: "Accessoire 4",
};

// Order of display (we skip empty values, but KEEP zeros)
const FIELD_ORDER = ["s", "e", "t", "r", "b", "l", "x", "o", "on", "a1", "a2", "a3", "a4"];

// Mapping rareté code -> libellé
const RARITY_MAP = {
  "1": "Commun",
  "2": "Spéciale",
  "3": "Rare",
  "4": "Légendaire",
};

// Example string used by the "Mettre l’exemple" button
const EXAMPLE_B32 =
  "FGC6A2WAJYEWBBQNYALRAECAG3IAPPAM4J5EEAEM6ACGY7DIQABTZGG7AD3PUMA5X2FMB3CH5MAEY7ADGHYAFT4IAA======";

function $(id) {
  return document.getElementById(id);
}

function setStatus(msg, kind = "ok") {
  const el = $("status");
  if (!el) return;
  el.textContent = msg || "";
  el.classList.remove("ok", "err", "warn");
  el.classList.add(kind);
}

function renderRaw(text) {
  const el = $("decodedText");
  if (!el) return;
  el.textContent = text || "";
}

function hasValue(v) {
  if (v === undefined || v === null) return false;
  const s = String(v);
  // keep "0" visible; only hide truly empty
  if (s === "0") return true;
  return s.trim().length > 0;
}

function base32Bytes(b32) {
  // We may encounter different Base32 alphabets depending on the encoder used.
  // To make decoding robust, we try multiple decoders and later pick the one
  // that actually yields a valid P'TIPOTE KV payload after LZ/UTF-8 decoding.

  const rawInput = String(b32 || "").trim().replace(/^#/, "");

  // Remove spaces/dashes but KEEP '=' padding for RFC4648 decoders.
  const cleaned = rawInput
    .toUpperCase()
    .replace(/\s+/g, "")
    .replace(/-/g, "");

  const stringToLatin1Bytes = (s) => {
    const out = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i) & 0xff;
    return out;
  };

  const normalizeMaybeBytes = (out) => {
    if (out instanceof Uint8Array) return out;
    if (Array.isArray(out)) return new Uint8Array(out);
    // Some libs return a "binary string" (bytes in char codes 0..255)
    if (typeof out === "string") return stringToLatin1Bytes(out);
    return null;
  };

  const tryLib = (lib, label) => {
    if (!lib) return null;

    const candidates = ["decodeToBytes", "toBytes", "decodeBytes", "decode", "fromBase32", "toUint8Array"];
    for (const name of candidates) {
      if (typeof lib[name] !== "function") continue;
      try {
        const out = lib[name](cleaned);
        const bytes = normalizeMaybeBytes(out);
        if (bytes && bytes.length) {
          bytes.__ptipoteDecoder = `${label}.${name}`;
          return bytes;
        }
      } catch (_) {
        // keep trying
      }
    }

    if (lib.base32 && typeof lib.base32 === "object") {
      return tryLib(lib.base32, `${label}.base32`);
    }

    return null;
  };

  // RFC4648 Base32: A-Z + 2-7 with optional '=' padding
  // IMPORTANT: we must respect '=' padding to recover the exact original byte length.
  const rfc4648DecodeToBytes = () => {
    const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    const map = Object.create(null);
    for (let i = 0; i < ALPHABET.length; i++) map[ALPHABET[i]] = i;

    const full = cleaned;
    if (!full) throw new Error("Base32 vide (RFC4648)");

    // We expect padding to make the length a multiple of 8.
    if (full.length % 8 !== 0) {
      throw new Error("Base32 invalide (RFC4648): longueur non multiple de 8 (padding manquant ?)");
    }

    // Count '=' padding at end
    const padMatch = full.match(/=+$/);
    const pad = padMatch ? padMatch[0].length : 0;

    // RFC4648 padding-to-bytes mapping (last quantum only)
    // 0 pad -> 5 bytes
    // 1 pad -> 4 bytes
    // 3 pad -> 3 bytes
    // 4 pad -> 2 bytes
    // 6 pad -> 1 byte
    const padToDrop = (() => {
      if (pad === 0) return 0;
      if (pad === 1) return 1;
      if (pad === 3) return 2;
      if (pad === 4) return 3;
      if (pad === 6) return 4;
      throw new Error(`Base32 invalide (RFC4648): padding '=' inattendu (${pad})`);
    })();

    const totalQuanta = full.length / 8;
    const expectedLen = totalQuanta * 5 - padToDrop;

    // Strip '=' for bit-unpacking
    const clean = full.replace(/=+$/g, "");

    let buffer = 0;
    let bits = 0;
    const out = [];

    for (let i = 0; i < clean.length; i++) {
      const ch = clean[i];
      const val = map[ch];
      if (val === undefined) {
        throw new Error(`Base32 invalide (RFC4648): caractère '${ch}'`);
      }
      buffer = (buffer << 5) | val;
      bits += 5;
      while (bits >= 8) {
        bits -= 8;
        out.push((buffer >> bits) & 0xff);
      }
    }

    // Truncate to expected length (padding implies dropped bytes)
    if (out.length > expectedLen) out.length = expectedLen;

    if (!out.length) throw new Error("Base32 vide/invalide (RFC4648)");
    const u8 = new Uint8Array(out);
    u8.__ptipoteDecoder = "internal-rfc4648";
    return u8;
  };

  // Crockford Base32: 0-9 + A-Z without I,L,O,U (with aliases)
  const crockfordDecodeToBytes = () => {
    const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
    const map = Object.create(null);
    for (let i = 0; i < ALPHABET.length; i++) map[ALPHABET[i]] = i;
    map["O"] = map["0"];
    map["I"] = map["1"];
    map["L"] = map["1"];

    // IMPORTANT: Crockford does not use '=' padding
    const clean = cleaned.replace(/=+$/g, "");

    let buffer = 0;
    let bits = 0;
    const out = [];

    for (let i = 0; i < clean.length; i++) {
      const ch = clean[i];
      const val = map[ch];
      if (val === undefined) {
        throw new Error(`Base32 invalide (Crockford): caractère '${ch}'`);
      }
      buffer = (buffer << 5) | val;
      bits += 5;
      while (bits >= 8) {
        bits -= 8;
        out.push((buffer >> bits) & 0xff);
      }
    }

    if (!out.length) throw new Error("Base32 vide/invalide (Crockford)");
    const u8 = new Uint8Array(out);
    u8.__ptipoteDecoder = "internal-crockford";
    return u8;
  };

  // Return ALL candidate decodes so the caller can choose the one that works.
  // Order matters: prefer standards first, then library fallbacks.
  const candidates = [];

  try {
    candidates.push(rfc4648DecodeToBytes());
  } catch (_) {}

  try {
    candidates.push(crockfordDecodeToBytes());
  } catch (_) {}

  // Library fallbacks (sometimes they assume a different alphabet)
  const libBytes = tryLib(window.base32, "window.base32") || tryLib(window.Base32, "window.Base32");
  if (libBytes) candidates.push(libBytes);

  if (!candidates.length) {
    throw new Error("Impossible de décoder la chaîne Base32 (libs + RFC4648 + Crockford)." );
  }

  return candidates;
}

function tryDecodePayload(bytes) {
  // Heuristic: accept a decoded string only if it looks like a KV payload.
  // This avoids the case where LZString returns a short/gibberish string (ex: "``")
  // even though the real payload is plain UTF-8.
  const looksLikeKV = (s) => {
    if (!s) return false;
    const t = String(s);
    // at least one key=value pair (keys like e,t,s,r,b,l,x,o,on,te,ta,a1..a4)
    return /(\b|^)(e|t|s|r|b|l|x|o|on|te|ta|a[1-4])\s*=/.test(t);
  };

  // 1) LZString path (binary)
  if (typeof LZString !== "undefined" && typeof LZString.decompressFromUint8Array === "function") {
    const tryLZ = (u8, label) => {
      try {
        // defensive copy so we never pass a Uint8Array with custom props
        const safe = u8 instanceof Uint8Array ? new Uint8Array(u8) : new Uint8Array(u8 || []);
        const txt = LZString.decompressFromUint8Array(safe);
        if (txt && txt.trim().length > 0) {
          if (looksLikeKV(txt)) return { mode: `lz:${label}`, text: txt };
          console.warn("[PTIPOTE] LZ decoded but does not look like KV (", label, "), falling back.", txt);
        }
      } catch (_) {
        // ignore
      }
      return null;
    };

    // a) bytes as-is
    let hit = tryLZ(bytes, "as-is");
    if (hit) return hit;

    // b) swap each pair of bytes (endianness fallback)
    if (bytes && bytes.length >= 2) {
      const swapped = new Uint8Array(bytes.length);
      for (let i = 0; i < bytes.length; i += 2) {
        if (i + 1 < bytes.length) {
          swapped[i] = bytes[i + 1];
          swapped[i + 1] = bytes[i];
        } else {
          swapped[i] = bytes[i];
        }
      }
      hit = tryLZ(swapped, "swap16");
      if (hit) return hit;
    }
  }

  // 2) UTF-8 fallback
  const utf8 = new TextDecoder("utf-8", { fatal: false }).decode(bytes);
  if (utf8 && utf8.trim().length > 0) {
    return { mode: "utf8", text: utf8 };
  }

  throw new Error("Décodage OK mais contenu vide/non lisible.");
}

function parseKV(text) {
  const parts = String(text || "").split(";");
  const data = {};
  for (const p of parts) {
    if (!p) continue;
    const idx = p.indexOf("=");
    if (idx === -1) continue;
    const k = p.slice(0, idx).trim();
    const v = p.slice(idx + 1).trim();
    if (!k) continue;
    data[k] = v;
  }
  return data;
}

function renderFields(data) {
  const wrap = $("fields");
  if (!wrap) return;
  wrap.innerHTML = "";

  const isEmpty = (v) => {
    if (v === null || v === undefined) return true;
    const s = String(v);
    if (s === "0") return false; // keep 0 visible
    return s.trim().length === 0; // hide empty strings
  };

  const addField = (label, value) => {
    const card = document.createElement("div");
    card.className = "field";

    const k = document.createElement("div");
    k.className = "k";
    k.textContent = label;

    const v = document.createElement("div");
    v.className = "v";
    v.textContent = value;

    card.appendChild(k);
    card.appendChild(v);
    wrap.appendChild(card);
  };

  // Transfer button (display-only for now)
  // - show only if te==1 OR ta==1
  // - te==1 => "Transfert en cours"
  // - ta==1 => "Transfert accepté"
  const te = Number((data && data.te) ?? 0);
  const ta = Number((data && data.ta) ?? 0);
  if (te === 1 || ta === 1) {
    const card = document.createElement("div");
    card.className = "field field--transfer";

    const k = document.createElement("div");
    k.className = "k";
    k.textContent = "Transfert";

    const btn = document.createElement("button");
    btn.className = "transferBtn";
    btn.type = "button";
    btn.disabled = true;
    btn.textContent = ta === 1 ? "Transfert accepté" : "Transfert en cours";

    card.appendChild(k);
    card.appendChild(btn);
    wrap.appendChild(card);
  }

  // Regular fields
  const source = data || {};
  for (const key of FIELD_ORDER) {
    if (!(key in FIELD_LABELS)) continue;
    const raw = source[key];
    if (isEmpty(raw)) continue; // hide empty fields only

    let displayValue = String(raw);
    if (key === "r") {
      displayValue = RARITY_MAP[String(raw)] || String(raw);
    }

    addField(FIELD_LABELS[key], displayValue);
  }

  // If nothing is shown, keep UI stable
  if (!wrap.children.length) {
    const hint = document.createElement("div");
    hint.className = "field";
    hint.innerHTML = `<div class="k">Aucun champ</div><div class="v">(tous les champs sont vides)</div>`;
    wrap.appendChild(hint);
  }
}

function onDecode() {
  try {
    const input = $("input");
    const b32 = (input?.value || "").trim();
    if (!b32) {
      setStatus("Colle une chaîne Base32.", "warn");
      renderRaw("");
      renderFields({});
      return;
    }

    const candidates = base32Bytes(b32);

    // Try each Base32 decoding candidate until we get a KV-like payload.
    let chosen = null;
    let payload = null;

    for (const bytes of candidates) {
      console.log(
        "[PTIPOTE] base32 bytes length:",
        bytes?.length,
        "first16:",
        Array.from(bytes.slice(0, 16))
          .map((b) => b.toString(16).padStart(2, "0"))
          .join(" "),
        "decoder:",
        bytes && bytes.__ptipoteDecoder ? bytes.__ptipoteDecoder : "unknown"
      );

      try {
        const p = tryDecodePayload(bytes);
        // Accept only if it contains at least one key=value (same rule as in tryDecodePayload)
        if (/(\b|^)(e|t|s|r|b|l|x|o|on|te|ta|a[1-4])\s*=/.test(String(p.text || ""))) {
          chosen = bytes;
          payload = p;
          break;
        }

        // Not KV, keep trying next candidate
      } catch (_) {
        // keep trying next candidate
      }
    }

    // If none looked like KV, fall back to the first candidate and decode normally
    if (!payload) {
      chosen = candidates[0];
      payload = tryDecodePayload(chosen);
    }

    console.log("[PTIPOTE] payload mode:", payload.mode, "text length:", payload.text?.length);
    console.log("[PTIPOTE] payload preview:", JSON.stringify(String(payload.text).slice(0, 120)));

    renderRaw(payload.text);

    const data = parseKV(payload.text);
    const hasAnyKV = Object.keys(data).length > 0;

    if (!hasAnyKV) {
      const prettyMode = payload.mode.startsWith("lz") ? "LZ" : payload.mode.toUpperCase();
      setStatus(`Décodage OK ✅ (${prettyMode}) mais format non-KV (aucun 'clé=valeur' trouvé)`, "warn");
      renderFields({});
      return;
    }

    const prettyMode = payload.mode.startsWith("lz") ? "LZ" : payload.mode.toUpperCase();
    setStatus(`Décodage OK ✅ (${prettyMode})`, "ok");
    renderFields(data);
  } catch (e) {
    console.error(e);
    setStatus(`Erreur: ${e?.message || e}`, "err");
    renderRaw("");
    renderFields({});
  }
}

function init() {
  const btnDecode = $("btnDecode");
  const btnFill = $("btnFillExample");
  const btnClear = $("btnClear");
  const input = $("input");

  btnDecode?.addEventListener("click", onDecode);
  btnFill?.addEventListener("click", () => {
    if (input) input.value = EXAMPLE_B32;
    onDecode();
  });
  btnClear?.addEventListener("click", () => {
    if (input) input.value = "";
    setStatus("", "ok");
    renderRaw("");
    renderFields({});
  });

  // Auto-decode from URL hash
  const hash = (location.hash || "").replace(/^#/, "").trim();
  if (hash) {
    if (input) input.value = hash;
    onDecode();
  } else {
    renderFields({});
  }
}

// Expose helpers for debugging in DevTools
window.PTIPOTE_DECODE = { init, onDecode, parseKV, renderFields };

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init);
} else {
  init();
}