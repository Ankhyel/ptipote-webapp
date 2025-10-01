function parseKV(str){
  const parts = (str||"").split(";");
  const data = {};
  for(const p of parts){
    if(!p) continue;
    const idx = p.indexOf("=");
    if(idx<=0) continue;
    const k = p.slice(0,idx).trim();
    const v = p.slice(idx+1).trim();
    if(k) data[k] = v;
  }
  return data;
}
function decodeFromUrlHash(){
  const raw = decodeURIComponent((location.hash||"").slice(1));
  if(!raw) return null;
  try{
    const bytes = base32ToBytes(raw);
    if(typeof LZString !== "undefined" && LZString.decompressFromUint8Array){
      const txt = LZString.decompressFromUint8Array(bytes);
      if(txt && txt.includes("=")) return parseKV(txt);
    }
    const txt2 = new TextDecoder().decode(bytes);
    if(txt2 && txt2.includes("=")) return parseKV(txt2);
  }catch(err){
    console.error("Erreur décompression:",err);
  }
  return null;
}