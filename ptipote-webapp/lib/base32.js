const base32 = {
  decode: function(input) {
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    let cleaned = input.replace(/=+$/, "");
    let bits = "";
    let output = [];
    for (let i = 0; i < cleaned.length; i++) {
      const val = alphabet.indexOf(cleaned[i].toUpperCase());
      if (val === -1) continue;
      bits += val.toString(2).padStart(5, "0");
      while (bits.length >= 8) {
        output.push(parseInt(bits.slice(0, 8), 2));
        bits = bits.slice(8);
      }
    }
    return output;
  }
};