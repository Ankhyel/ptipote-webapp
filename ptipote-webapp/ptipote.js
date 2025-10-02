window.addEventListener("DOMContentLoaded", () => {
  const hash = window.location.hash.slice(1);
  const data = decodeData(hash);
  if (!data) {
    document.body.insertAdjacentHTML("afterbegin", "<div style='color:red;'>Erreur de lecture</div>");
    return;
  }

  document.getElementById("surnom").textContent = "Surnom : " + (data.s || "Aucun");
  document.getElementById("espece").textContent = "Espèce : " + (data.e || "Inconnue");
  document.getElementById("type").textContent   = "Type : " + (data.t || "Inconnu");
  document.getElementById("xp").textContent     = "XP : " + (data.x || "0");
  document.getElementById("niveau").textContent = "Niveau : " + (data.l || "0");
  document.getElementById("eleveur").textContent= "Éleveur : " + (data.o || "Inconnu");

  const imgEl = document.getElementById("typeImage");
  imgEl.src = "img/" + (data.t ? data.t.toLowerCase() : "placeholder") + ".png";
  imgEl.onerror = () => { imgEl.src = "img/placeholder.png"; };
});