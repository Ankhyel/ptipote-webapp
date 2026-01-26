// --- Base32 decode (RFC4648, sans padding) ---
const B32_ALPH = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

function base32DecodeToUtf8(input) {
  const clean = (input || "").toUpperCase().replace(/[^A-Z2-7]/g, "");
  let bits = 0;
  let value = 0;
  const bytes = [];

  for (let i = 0; i < clean.length; i++) {
    const v = B32_ALPH.indexOf(clean[i]);
    if (v < 0) continue;
    value = (value << 5) | v;
    bits += 5;
    if (bits >= 8) {
      bytes.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return new TextDecoder("utf-8", { fatal: false }).decode(new Uint8Array(bytes));
}

// --- Parse message clair: c=?|p=?|message|signature ---
function parseDecoded(decoded) {
  const parts = (decoded || "").split("|");

  const meta = { c: "p", p: "i" };
  let idx = 0;

  if (parts[idx] && parts[idx].startsWith("c=")) { meta.c = (parts[idx].slice(2) || meta.c).trim(); idx++; }
  if (parts[idx] && parts[idx].startsWith("p=")) { meta.p = (parts[idx].slice(2) || meta.p).trim(); idx++; }

  const msg = (parts[idx++] || "").trim();
  const sig = (parts[idx++] || "").trim();

  return { meta, msg, sig };
}

// --- Codes -> emoji ---
function heartCodeToEmoji(c) {
  const map = {
    r: "❤️",
    p: "💗",
    o: "🧡",
    y: "💛",
    g: "💚",
    b: "💙",
    v: "💜",
    w: "🤍",
    k: "🖤",
    c: "💎",     // cristal
    x: "❤️‍🔥",  // cristal rouge
    z: "💛"      // cristal or (effet étoiles fait le “cristal”)
  };
  return map[c] || "💗";
}

function applyTheme(c) {
  const known = new Set(["r","p","o","y","g","b","v","w","k","c","x","z"]);
  const code = known.has(c) ? c : "p";
  document.body.classList.add("theme-" + code);
  return code;
}

function setPtipoteImage(p) {
  const known = new Set(["i","g","a","d"]);
  const code = known.has(p) ? p : "i";
  document.getElementById("ptipoteImg").src = `/love/assets/ptipote-${code}.png`;
}

function setSparkles(enabled) {
  const box = document.getElementById("sparkles");
  box.innerHTML = "";
  box.classList.toggle("on", enabled);
  if (!enabled) return;

  const count = 12;
  for (let i = 0; i < count; i++) {
    const s = document.createElement("div");
    s.className = "sparkle";
    s.style.left = (8 + Math.random() * 84) + "%";
    s.style.top  = (6 + Math.random() * 78) + "%";
    s.style.animationDelay = (Math.random() * 1.2) + "s";
    const size = 7 + Math.random() * 9;
    s.style.width = size + "px";
    s.style.height = size + "px";
    box.appendChild(s);
  }
}

function showError(message) {
  const err = document.getElementById("err");
  err.style.display = "block";
  err.textContent = message;
}

(function init() {
  const hash = (location.hash || "").replace(/^#/, "").trim();
  if (!hash) {
    showError("Aucun message dans l’URL. Exemple : /love#BASE32");
    return;
  }

  let decoded = "";
  try {
    decoded = base32DecodeToUtf8(hash);
  } catch {
    showError("Impossible de décoder le message (Base32 invalide).");
    return;
  }

  if (!decoded || decoded.trim().length === 0) {
    showError("Message vide après décodage.");
    return;
  }

  const { meta, msg, sig } = parseDecoded(decoded);

  meta.c = applyTheme(meta.c);
  document.getElementById("heartEmoji").textContent = heartCodeToEmoji(meta.c);
  setPtipoteImage(meta.p);

  // étoiles si coeur cristal / cristal rouge / cristal or
  setSparkles(meta.c === "c" || meta.c === "x" || meta.c === "z");

  document.getElementById("msg").textContent = msg || "…";
  document.getElementById("sig").textContent = sig || "";
 
  document.getElementById("hint").textContent =
  "Bravo tu as découvert le message secret. Ce petit message a été écrit avec affection";

})();
