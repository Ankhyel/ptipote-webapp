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