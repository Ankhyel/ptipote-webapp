const B32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
function base32ToBytes(input){
  let bits="", out=[];
  if(!input) return new Uint8Array();
  input = input.replace(/\s+/g,"").replace(/=+$/,"").toUpperCase();
  for(let c of input){
    const v = B32_ALPHABET.indexOf(c);
    if(v<0) continue;
    bits += v.toString(2).padStart(5,"0");
  }
  for(let i=0;i+8<=bits.length;i+=8){
    out.push(parseInt(bits.slice(i,i+8),2));
  }
  return new Uint8Array(out);
}