const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

function base32ToBytes(base32) {
  let bits = "", result = [];
  base32 = base32.replace(/=+$/, "").toUpperCase();
  for (let i = 0; i < base32.length; i++) {
    const val = alphabet.indexOf(base32.charAt(i));
    if (val === -1) continue;
    bits += val.toString(2).padStart(5, "0");
  }
  for (let i = 0; i + 8 <= bits.length; i += 8) {
    result.push(parseInt(bits.substring(i, i+8), 2));
  }
  return new Uint8Array(result);
}