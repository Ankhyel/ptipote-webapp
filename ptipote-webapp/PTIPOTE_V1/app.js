const DEFAULT_NICKNAME = "Ce PTIPOTE aimerait un surnom.";
const DEFAULT_OWNER = "Ce PTIPOTE n'est pas encore adopté... Qu'attends-tu ?";
const DEFAULT_ACCESSORY = "Aucun";
const ACTION_SOON_MESSAGE = "La fonctionnalité sera disponible rapidement.";
const THEME_STORAGE_KEY = "ptipote_theme";

const TYPE_COLORS = {
  myca: "#6b7bff",
  rori: "#28b1ff",
  skadi: "#14b89f",
  aural: "#f2874a",
};

const RARITY_LABELS = {
  "1": "Commun",
  "2": "Spéciale",
  "3": "Rare",
  "4": "Légendaire",
};

const IMAGE_EXTENSIONS = ["png", "jpg", "webp", "jpeg"];

function $(id) {
  return document.getElementById(id);
}

function getSystemTheme() {
  const query = "(prefers-color-scheme: light)";
  return window.matchMedia && window.matchMedia(query).matches ? "light" : "dark";
}

function loadSavedTheme() {
  try {
    const value = localStorage.getItem(THEME_STORAGE_KEY);
    return value === "light" || value === "dark" ? value : "";
  } catch (_) {
    return "";
  }
}

function saveTheme(theme) {
  try {
    localStorage.setItem(THEME_STORAGE_KEY, theme);
  } catch (_) {
    // ignore storage errors
  }
}

function applyTheme(theme) {
  const next = theme === "light" ? "light" : "dark";
  document.documentElement.setAttribute("data-theme", next);

  const btn = $("themeToggle");
  if (btn) {
    const target = next === "light" ? "sombre" : "clair";
    btn.setAttribute("aria-label", `Activer le mode ${target}`);
    btn.setAttribute("aria-pressed", next === "light" ? "true" : "false");
  }

  const icon = $("themeToggleIcon");
  if (icon) {
    icon.textContent = next === "light" ? "☀️" : "🌙";
  }
}

function initTheme() {
  const saved = loadSavedTheme();
  const initial = saved || "light";
  applyTheme(initial);

  const btn = $("themeToggle");
  if (!btn) return;

  btn.addEventListener("click", () => {
    const current = document.documentElement.getAttribute("data-theme") === "light" ? "light" : "dark";
    const next = current === "light" ? "dark" : "light";
    applyTheme(next);
    saveTheme(next);
    decodeFromHash();
  });
}

function setStatus(message, kind = "") {
  const el = $("status");
  if (!el) return;
  el.textContent = message || "";
  el.className = "status" + (kind ? " " + kind : "");
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function normalizeKey(value) {
  return String(value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "")
    .trim();
}

function pretty(value, fallback = "—") {
  const s = String(value ?? "").trim();
  return s.length ? s : fallback;
}

function boolFlag(value) {
  const s = String(value ?? "").trim().toLowerCase();
  return s === "1" || s === "true" || s === "yes" || s === "on";
}

function getValue(data, keys) {
  for (const key of keys) {
    if (Object.prototype.hasOwnProperty.call(data, key)) {
      return String(data[key] ?? "").trim();
    }
  }
  return "";
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

function looksLikeKV(text) {
  return /(^|;)\s*([a-z]{1,3}|a[1-4])\s*=/.test(String(text || "").trim());
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
      throw new Error(`Base32 invalide: '${ch}'`);
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

function safeDecompressFromUint8Array(arr) {
  if (!arr || arr.length === 0) return "";

  if (typeof LZString.decompressFromUint8Array === "function") {
    try {
      const direct = LZString.decompressFromUint8Array(arr);
      if (direct && String(direct).trim().length) return direct;
    } catch (_) {
      // fallback below
    }
  }

  const pairCount = Math.floor(arr.length / 2);
  const chars = new Array(pairCount);
  for (let i = 0; i < pairCount; i++) {
    chars[i] = String.fromCharCode((arr[i * 2] << 8) | arr[i * 2 + 1]);
  }
  return LZString.decompress(chars.join(""));
}

function decodeLZ(bytes) {
  if (typeof LZString === "undefined" || typeof LZString.decompress !== "function") {
    throw new Error("LZString indisponible");
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

  if (fallback) return fallback;
  throw new Error("Payload LZ invalide");
}

function typeColor(typeValue) {
  const key = normalizeKey(typeValue);
  if (!key) return "#4f8cff";
  if (TYPE_COLORS[key]) return TYPE_COLORS[key];

  let hash = 0;
  for (let i = 0; i < key.length; i++) {
    hash = (hash * 31 + key.charCodeAt(i)) >>> 0;
  }
  const hue = hash % 360;
  return `hsl(${hue} 78% 58%)`;
}

function currentTheme() {
  return document.documentElement.getAttribute("data-theme") === "light" ? "light" : "dark";
}

function rarityLabel(value) {
  const raw = String(value ?? "").trim();
  if (!raw) return "";
  return RARITY_LABELS[raw] || raw;
}

function xpProgress(rawXp) {
  const raw = String(rawXp ?? "").trim();

  if (!raw) {
    return { current: 0, max: 100, percent: 0, text: "0 / 100 XP" };
  }

  const ratio = raw.match(/^(\d+)\s*\/\s*(\d+)$/);
  if (ratio) {
    const current = Number(ratio[1]);
    const max = Math.max(1, Number(ratio[2]));
    const percent = Math.max(0, Math.min(100, (current / max) * 100));
    return { current, max, percent, text: `${current} / ${max} XP` };
  }

  if (/^\d+$/.test(raw)) {
    const current = Number(raw);
    const max = Math.max(100, current);
    const percent = Math.max(0, Math.min(100, (current / max) * 100));
    return { current, max, percent, text: `${current} / ${max} XP` };
  }

  return { current: 0, max: 100, percent: 0, text: `${raw} XP` };
}

function heroColorByRarity(rarity, fallbackColor) {
  const raw = String(rarity ?? "").trim();
  if (raw === "2") return "#ff5cae"; // Spéciale
  if (raw === "3") return "#3f7cff"; // Rare
  if (raw === "4") return "#d4a63b"; // Légendaire
  return fallbackColor; // Commun: current color
}

function heroBackgroundByRarity(rarity) {
  const raw = String(rarity ?? "").trim();
  const isLight = currentTheme() === "light";

  if (raw === "2") {
    return isLight
      ? { start: "rgba(255, 177, 220, 0.9)", end: "rgba(244, 138, 198, 0.86)" }
      : { start: "rgba(255, 92, 174, 0.82)", end: "rgba(156, 36, 102, 0.78)" };
  }

  if (raw === "3") {
    return isLight
      ? { start: "rgba(145, 184, 255, 0.9)", end: "rgba(104, 150, 237, 0.86)" }
      : { start: "rgba(63, 124, 255, 0.82)", end: "rgba(28, 70, 167, 0.78)" };
  }

  if (raw === "4") {
    return isLight
      ? { start: "rgba(244, 217, 138, 0.92)", end: "rgba(227, 192, 92, 0.88)" }
      : { start: "rgba(212, 166, 59, 0.84)", end: "rgba(129, 90, 23, 0.8)" };
  }

  if (isLight) {
    return { start: "rgba(229, 238, 255, 0.92)", end: "rgba(206, 222, 248, 0.9)" };
  }

  return { start: "rgba(16, 24, 40, 0.7)", end: "rgba(13, 21, 41, 0.7)" };
}

function buildImageCandidates(...names) {
  const orderedNames = [];
  const seen = new Set();

  function pushName(name) {
    const clean = String(name || "")
      .replace(/[\u0000-\u001f\u007f]/g, "")
      .trim();
    if (!clean) return;
    if (seen.has(clean)) return;
    seen.add(clean);
    orderedNames.push(clean);
  }

  for (const name of names) {
    const raw = String(name || "")
      .replace(/[\u0000-\u001f\u007f]/g, "")
      .trim();
    if (!raw) continue;

    pushName(raw);
    const normalized = normalizeKey(raw);
    pushName(normalized);

    const lower = raw.toLowerCase();
    const upperFirst = lower.charAt(0).toUpperCase() + lower.slice(1);
    pushName(lower);
    pushName(upperFirst);

    const normalizedUpperFirst = normalized.charAt(0).toUpperCase() + normalized.slice(1);
    pushName(normalizedUpperFirst);
  }

  const candidates = [];
  for (const name of orderedNames) {
    for (const ext of IMAGE_EXTENSIONS) {
      candidates.push(`/img/${encodeURIComponent(name)}.${ext}`);
    }
  }
  candidates.push("/img/bplaceholder.png");
  return candidates;
}

function inlineFallbackImage(label) {
  const safe = escapeHtml(String(label || "PTIPOTE"));
  const svg = `
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#eef3ff"/>
      <stop offset="100%" stop-color="#dce7ff"/>
    </linearGradient>
  </defs>
  <rect width="512" height="512" fill="url(#g)"/>
  <circle cx="256" cy="210" r="96" fill="#9cb4ea"/>
  <rect x="136" y="332" width="240" height="28" rx="14" fill="#90a8de"/>
  <text x="256" y="418" text-anchor="middle" fill="#4a5f8f" font-family="Arial, sans-serif" font-size="28">${safe}</text>
</svg>`.trim();
  return `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(svg)}`;
}

function applySafeContainLayout(imageEl) {
  const w = Number(imageEl.naturalWidth || 0);
  const h = Number(imageEl.naturalHeight || 0);
  if (!w || !h) return;
  imageEl.style.objectPosition = "top center";

  // Safari iOS can crop <img> with object-fit in some compositions.
  // We force a manual contain behavior based on real image ratio.
  if (w >= h) {
    imageEl.style.width = "100%";
    imageEl.style.height = "auto";
  } else {
    imageEl.style.width = "auto";
    imageEl.style.height = "100%";
  }
}

function updateSpeciesImage(type, species) {
  const imageEl = $("speciesImage");
  if (!imageEl) return;

  // Public rule: image is driven by "type" first, then species as fallback.
  const candidates = buildImageCandidates(type, species);
  const finalFallback = inlineFallbackImage(pretty(type || species, "PTIPOTE"));

  let index = 0;
  const tryNext = () => {
    if (index >= candidates.length) {
      imageEl.onerror = null;
      imageEl.onload = null;
      imageEl.src = finalFallback;
      return;
    }
    imageEl.src = candidates[index];
  };

  imageEl.onload = () => {
    // Safari/iOS can occasionally report a completed image with invalid size.
    if (!imageEl.naturalWidth || !imageEl.naturalHeight) {
      index += 1;
      tryNext();
      return;
    }
    applySafeContainLayout(imageEl);
  };

  imageEl.onerror = () => {
    index += 1;
    tryNext();
  };

  tryNext();
}

function renderInfoCards(model) {
  const root = $("infoCards");
  if (!root) return;

  const nicknameRaw = String(model.nickname ?? "").trim();
  const ownerRaw = String(model.ownerName ?? "").trim();
  const hasOwner = ownerRaw.length > 0;
  const accessories = model.accessories.map((v) => String(v ?? "").trim());
  const hasAnyAccessory = accessories.some((v) => v.length > 0);
  const xp = xpProgress(model.xp);

  const cards = [
    {
      label: "Surnom",
      value: pretty(model.nickname, DEFAULT_NICKNAME),
      isPlaceholder: nicknameRaw.length === 0,
    },
    { label: "Rareté", value: pretty(rarityLabel(model.rarity)) },
    { label: "Niveau", value: pretty(model.level) },
    {
      label: "Nom de l’éleveur",
      value: pretty(model.ownerName, DEFAULT_OWNER),
      isPlaceholder: ownerRaw.length === 0,
    },
  ];

  let html = cards
    .map((card) => `
      <article class="infoCard">
        <div class="label">${escapeHtml(card.label)}</div>
        <div class="value${card.isPlaceholder ? " placeholder" : ""}">${escapeHtml(card.value)}</div>
      </article>
    `)
    .join("");

  html += `
    <article class="infoCard xpCard">
      <div class="label">XP</div>
      <div class="xpBarTrack">
        <div class="xpBarFill" style="width:${xp.percent.toFixed(2)}%"></div>
      </div>
      <div class="xpText">${escapeHtml(xp.text)}</div>
    </article>
  `;

  const actionLabel = hasOwner ? "Embarquer" : "Adopter";
  html += `
    <article class="infoCard action">
      <div class="label">Action</div>
      <button class="actionBtn ${hasOwner ? "embark" : "adopt"}" type="button" data-soon="1">${actionLabel}</button>
      <p class="actionHint">${escapeHtml(ACTION_SOON_MESSAGE)}</p>
    </article>
  `;

  const accessoryRows = accessories
    .map((value, idx) => `<li><span>A${idx + 1}</span><strong>${escapeHtml(pretty(value, DEFAULT_ACCESSORY))}</strong></li>`)
    .join("");

  html += `
    <article class="infoCard accessoriesCard">
      <details class="accessories">
        <summary>
          <span class="label">Accessoires</span>
          <span class="summaryRight">
            <span class="summaryValue">${escapeHtml(hasAnyAccessory ? "Voir le détail" : "Aucun")}</span>
            <span class="summaryArrow" aria-hidden="true">▾</span>
          </span>
        </summary>
        <ul>${accessoryRows}</ul>
      </details>
    </article>
  `;

  if (model.transferRequested || model.transferConfirmed) {
    html += `
      <article class="infoCard transfer ${model.transferConfirmed ? "confirmed" : "pending"}">
        <div class="label">Transfert de l’éleveur</div>
        <div class="value">${escapeHtml(model.transferConfirmed ? "Transfert confirmé" : "Transfert en cours")}</div>
      </article>
    `;
  }

  html += `
    <article class="infoCard tiny">
      <div class="label">Batch</div>
      <div class="value">${escapeHtml(pretty(model.batch))}</div>
    </article>
  `;

  root.innerHTML = html;
}

function normalizeModel(data) {
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

function renderHero(model) {
  // In hero card: Type is primary (big), Espèce is secondary.
  $("heroSpecies").textContent = pretty(model.type, "Type inconnu");
  $("heroType").textContent = pretty(model.species, "Espèce inconnue");
  const baseColor = typeColor(model.species);
  const rarityColor = heroColorByRarity(model.rarity, baseColor);
  const rarityBg = heroBackgroundByRarity(model.rarity);
  const hero = $("heroCard");
  hero.style.setProperty("--type-color", rarityColor);
  hero.style.setProperty("--hero-bg-start", rarityBg.start);
  hero.style.setProperty("--hero-bg-end", rarityBg.end);
  updateSpeciesImage(model.type, model.species);
}

function decodeFromHash() {
  const rawHash = String(location.hash || "").replace(/^#/, "").trim();

  if (!rawHash) {
    setStatus("Scanne une puce NFC pour afficher un PTIPOTE.", "warn");
    const emptyModel = normalizeModel({});
    renderHero(emptyModel);
    renderInfoCards(emptyModel);
    return;
  }

  try {
    const bytes = decodeBase32ToBytes(rawHash);
    const lz = decodeLZ(bytes);
    const data = parseKV(lz.text);
    if (!looksLikeKV(lz.text) || Object.keys(data).length === 0) {
      throw new Error("Payload décodé mais format non-KV");
    }
    const model = normalizeModel(data);

    renderHero(model);
    renderInfoCards(model);
    setStatus("Lien Zone 0 : OK", "ok");
  } catch (error) {
    console.error(error);
    setStatus("Erreur de décodage : vague en cours ou PTIPOTE infecté.", "err");
    const emptyModel = normalizeModel({});
    renderHero(emptyModel);
    renderInfoCards(emptyModel);
  }
}

function showActionToast(message) {
  const toast = $("actionToast");
  if (!toast) return;
  toast.textContent = message;
  toast.classList.add("show");

  if (showActionToast.timer) {
    clearTimeout(showActionToast.timer);
  }
  showActionToast.timer = setTimeout(() => {
    toast.classList.remove("show");
  }, 2200);
}

function bindActionInfo() {
  document.addEventListener("click", (event) => {
    const btn = event.target.closest(".actionBtn[data-soon='1']");
    if (!btn) return;
    event.preventDefault();
    showActionToast(ACTION_SOON_MESSAGE);
  });
}

function init() {
  initTheme();
  bindActionInfo();
  decodeFromHash();
  window.addEventListener("hashchange", decodeFromHash);
}

window.PTIPOTE_V1 = {
  decodeBase32ToBytes,
  decodeLZ,
  parseKV,
  normalizeModel,
  decodeFromHash,
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init);
} else {
  init();
}
