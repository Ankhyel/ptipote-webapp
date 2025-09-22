
window.onload = () => {
  const data = decodeFromUrlHash();
  if (!data) return;

  document.getElementById("name").textContent = data.s || "P’tipote";
  document.getElementById("espece").textContent = "Espèce : " + (data.e || "N/A");
  document.getElementById("type").textContent = "Type : " + (data.t || "N/A");
  document.getElementById("surnom").textContent = "Surnom : " + (data.s || "Aucun");
  document.getElementById("xp").textContent = "XP : " + (data.x || "0");
  document.getElementById("level").textContent = "Niveau : " + (data.l || "0");
  document.getElementById("eleveur").textContent = "Éleveur : " + (data.o || "Inconnu");

  document.getElementById("typeImage").src = "img/" + (data.t || "placeholder") + ".png";

  document.body.classList.add(data.e || "");
};
