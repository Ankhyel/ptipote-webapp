function decodeData(hash) {
  try {
    const base32Decoded = base32.decode(hash);
    const compressed = new Uint8Array(base32Decoded);
    const decompressed = LZString.decompressFromUint8Array(compressed);
    if (!decompressed) return null;
    const pairs = decompressed.split(";");
    const data = {};
    pairs.forEach(p => {
      if (p) {
        const [k, v] = p.split("=");
        data[k.trim()] = v ? v.trim() : "";
      }
    });
    return data;
  } catch (e) {
    console.error("Erreur de décodage:", e);
    return null;
  }
}