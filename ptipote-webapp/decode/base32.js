// base32.js — RFC4648 Base32 (A-Z2-7) decode -> Uint8Array
// Expose: window.Base32.decodeToBytes(str)

(() => {
  const ALPH = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  const LOOKUP = (() => {
    const map = Object.create(null);
    for (let i = 0; i < ALPH.length; i++) map[ALPH[i]] = i;
    return map;
  })();

  function clean(input) {
    return (input || "")
      .toString()
      .trim()
      .replace(/^#/, "")
      .replace(/\s+/g, "")
      .replace(/=+$/g, "")
      .toUpperCase();
  }

  function decodeToBytes(input) {
    const s = clean(input);
    if (!s) return new Uint8Array(0);

    let bits = 0;
    let value = 0;
    const out = [];

    for (let i = 0; i < s.length; i++) {
      const ch = s[i];
      const v = LOOKUP[ch];
      if (v === undefined) continue;

      value = (value << 5) | v;
      bits += 5;

      if (bits >= 8) {
        bits -= 8;
        out.push((value >>> bits) & 0xff);
      }
    }

    return new Uint8Array(out);
  }

  window.Base32 = { decodeToBytes };
})();
