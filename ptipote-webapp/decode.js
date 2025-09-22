
function base32ToBytes(base32) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let bits = "", result = [];

  base32 = base32.replace(/=+$/, "").toUpperCase();
  for (let i = 0; i < base32.length; i++) {
    const val = alphabet.indexOf(base32.charAt(i));
    if (val === -1) continue;
    bits += val.toString(2).padStart(5, "0");
  }

  for (let i = 0; i + 8 <= bits.length; i += 8)
    result.push(parseInt(bits.substring(i, i + 8), 2));

  return new Uint8Array(result);
}

function decodeFromUrlHash() {
  const hash = window.location.hash.slice(1);
  if (!hash) return null;

  try {
    const bytes = base32ToBytes(hash);
    const decompressed = LZString.decompressFromUint8Array(bytes);
    if (!decompressed) return null;

    const fields = decompressed.split(";");
    const data = {};
    for (const field of fields) {
      const [key, value] = field.split("=");
      if (key) data[key.trim()] = value?.trim() ?? "";
    }

    return data;
  } catch (err) {
    console.error("Erreur de décompression:", err);
    return null;
  }
}
