function slugify(str){
  return (str||"").toString()
    .normalize("NFD").replace(/[\u0300-\u036f]/g,"")
    .trim().toLowerCase()
    .replace(/[^a-z0-9]+/g,"-")
    .replace(/^-+|-+$/g,"");
}
function renderPtipote(data){
  const eAff = data.e || "—";
  const tAff = data.t || "—";
  const eSlug = slugify(data.e);
  const tSlug = slugify(data.t);
  if(!eSlug || !tSlug){
    alert("❌ Erreur de lecture des données. Rechargement...");
    location.reload(); return;
  }
  document.getElementById("surnom").textContent = "Surnom : " + (data.s || "Aucun");
  document.getElementById("espece").textContent = "Espèce : " + eAff;
  document.getElementById("type").textContent   = "Type : " + tAff;
  document.getElementById("xp").textContent     = "XP : " + (data.x || 0);
  document.getElementById("niveau").textContent = "Niveau : " + (data.l || 0);
  document.getElementById("eleveur").textContent= "Éleveur : "+ (data.o || "Inconnu");
  const imgEl = document.getElementById("typeImage");
  imgEl.src = "img/" + tSlug + ".png";
  imgEl.onerror = () => { imgEl.src = "img/placeholder.png"; };
}
let autoTimer=null;
function startAuto(){ if(!autoTimer){ autoTimer=setInterval(()=>{location.reload();},5000);} }
function stopAuto(){ if(autoTimer){ clearInterval(autoTimer); autoTimer=null; } }
document.addEventListener("visibilitychange", ()=>{
  if(document.visibilityState === "visible") startAuto(); else stopAuto();
});
window.addEventListener("load", ()=>{
  const data = decodeFromUrlHash();
  if(data){ renderPtipote(data); if(document.visibilityState==="visible") startAuto(); }
});
