// base32.js — Base32 (RFC 4648) decoder (A–Z, 2–7) -> Uint8Array
// Compatible avec encodeur.html (alphabet A-Z 2-7 + padding '=')

(() => {
  const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

  function decodeToBytes(input) {
    if (!input) return new Uint8Array();

    const s = String(input)
      .trim()
      .replace(/^#/, "")
      .replace(/[\s-]+/g, "")
      .toUpperCase()
      .replace(/=+$/g, "");

    let bits = "";
    for (const ch of s) {
      const v = ALPHABET.indexOf(ch);
      if (v === -1) {
        if (ch === "0") throw new Error("Base32: '0' invalide. Remplace par 'O'.");
        if (ch === "1") throw new Error("Base32: '1' invalide. Remplace par 'I'.");
        throw new Error(`Base32: caractère invalide '${ch}'. Autorisés: A–Z et 2–7.`);
      }
      bits += v.toString(2).padStart(5, "0");
    }

    const byteLen = Math.floor(bits.length / 8);
    const out = new Uint8Array(byteLen);
    for (let i = 0; i < byteLen; i++) {
      out[i] = parseInt(bits.slice(i * 8, i * 8 + 8), 2);
    }
    return out;
  }

  window.Base32 = { decodeToBytes };
})();