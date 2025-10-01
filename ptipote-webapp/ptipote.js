function slugify(str) {
  return (str || "").toString()
    .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function renderPtipote(data) {
  const especeAff = data.e || "—";
  const typeAff = data.t || "—";
  const especeSlug = slugify(data.e);
  const typeSlug = slugify(data.t);

  if (!especeSlug || !typeSlug) {
    alert("❌ Erreur de lecture des données du P’tipote. La page va se recharger.");
    window.location.reload();
    return;
  }

  document.getElementById("surnom").textContent = "Surnom : " + (data.s || "Aucun");
  document.getElementById("espece").textContent = "Espèce : " + especeAff;
  document.getElementById("type").textContent = "Type : " + typeAff;
  document.getElementById("xp").textContent = "XP : " + (data.x || 0);
  document.getElementById("niveau").textContent = "Niveau : " + (data.l || 0);
  document.getElementById("eleveur").textContent = "Éleveur : " + (data.o || "Inconnu");

  const imgEl = document.getElementById("typeImage");
  imgEl.src = "img/" + typeSlug + ".png";
  imgEl.onerror = () => { imgEl.src = "img/placeholder.png"; };

  const speciesClasses = ["geoda","ferox","mousse","monts","ivy","cactin","veria"];
  speciesClasses.forEach(c => document.body.classList.remove(c));
  document.body.classList.add(especeSlug);
}

let refreshInterval = null;
function startAutoRefresh() {
  if (!refreshInterval) {
    refreshInterval = setInterval(() => { window.location.reload(); }, 5000);
  }
}
function stopAutoRefresh() {
  if (refreshInterval) { clearInterval(refreshInterval); refreshInterval = null; }
}
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") startAutoRefresh();
  else stopAutoRefresh();
});
if (document.visibilityState === "visible") startAutoRefresh();

window.onload = () => {
  const data = decodeFromUrlHash();
  if (data) renderPtipote(data);
};