/* ptipote.js – décode Base32 (+ LZString si dispo) et affiche les infos */

(function () {
  // --- Base32 decoder (autonome) ---
  const B32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  function base32ToBytes(input) {
    if (!input) return new Uint8Array();
    let clean = input.trim().replace(/=+$/g, "").toUpperCase();
    let bits = "";
    const out = [];
    for (const c of clean) {
      const v = B32.indexOf(c);
      if (v < 0) continue;
      bits += v.toString(2).padStart(5, "0");
      while (bits.length >= 8) {
        out.push(parseInt(bits.slice(0, 8), 2));
        bits = bits.slice(8);
      }
    }
    return new Uint8Array(out);
  }

  // --- Utils ---
  function parseKV(s) {
    const data = {};
    (s || "").split(";").forEach((pair) => {
      if (!pair) return;
      const idx = pair.indexOf("=");
      if (idx < 0) return;
      const k = pair.slice(0, idx).trim();
      const v = pair.slice(idx + 1).trim();
      if (k) data[k] = v;
    });
    return data;
  }

  function slugify(str) {
    return (str || "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "");
  }

  // --- Décodage robuste du hash ---
  function tryDecode(hash) {
    if (!hash) return null;
    const h = decodeURIComponent(hash);

    // 1) Base32 -> bytes
    let bytes = null;
    try { bytes = base32ToBytes(h); } catch (e) {}

    // 2) LZString depuis bytes
    if (bytes && typeof LZString !== "undefined" && LZString.decompressFromUint8Array) {
      try {
        const txt = LZString.decompressFromUint8Array(bytes);
        if (txt && txt.includes("=")) return parseKV(txt);
      } catch (e) {}
    }

    // 3) UTF-8 direct
    if (bytes && bytes.length) {
      try {
        const txt = new TextDecoder().decode(bytes);
        if (txt && txt.includes("=")) return parseKV(txt);
      } catch (e) {}
    }

    // 4) Fallback : EncodedURIComponent (au cas où)
    if (typeof LZString !== "undefined" && LZString.decompressFromEncodedURIComponent) {
      try {
        const txt = LZString.decompressFromEncodedURIComponent(h);
        if (txt && txt.includes("=")) return parseKV(txt);
      } catch (e) {}
    }

    return null;
  }

  // --- Rendu ---
  function render(data) {
    // Affichages (sans bloquer si e/t manquent)
    const espece = data.e || "Inconnue";
    const type = data.t || "Inconnu";

    document.getElementById("surnom").textContent = "Surnom : " + (data.s || "Aucun");
    document.getElementById("espece").textContent = "Espèce : " + espece;
    document.getElementById("type").textContent   = "Type : " + type;
    document.getElementById("xp").textContent     = "XP : " + (data.x || "0");
    document.getElementById("niveau").textContent = "Niveau : " + (data.l || "0");
    document.getElementById("eleveur").textContent= "Éleveur : " + (data.o || "Inconnu");

    // Image par type (normalisé)
    const typeSlug = slugify(type);
    const imgEl = document.getElementById("typeImage");
    imgEl.src = "img/" + typeSlug + ".png";
    imgEl.onerror = () => { imgEl.src = "img/placeholder.png"; };
  }

  function showError(msg) {
    // On affiche le message mais on n’écrase plus la page complète
    const id = "ptipote-error";
    let el = document.getElementById(id);
    if (!el) {
      el = document.createElement("div");
      el.id = id;
      el.style.cssText = "color:#fff;text-align:center;margin:16px;";
      document.body.prepend(el);
    }
    el.textContent = msg;
  }

  function init() {
    const hash = window.location.hash.slice(1);
    const data = tryDecode(hash);

    if (!data) {
      showError("Erreur de lecture. Actualisation…");
      setTimeout(() => location.reload(), 2000);
      return;
    }

    render(data);
  }

  // Charge au démarrage
  window.addEventListener("load", init);

  // Auto-refresh si onglet actif
  let timer = null;
  function start() { if (!timer) timer = setInterval(() => location.reload(), 5000); }
  function stop()  { if (timer) { clearInterval(timer); timer = null; } }

  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") start();
    else stop();
  });
})();
