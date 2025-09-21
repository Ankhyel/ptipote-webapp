
window.onload = () => {
  const data = decodeFromUrlHash();
  if (!data) return;

  const r = {
    "1": "Commun",
    "2": "Spécial",
    "3": "Rare",
    "4": "Légendaire"
  };

  document.getElementById("name").textContent = `${data.s || "P’tipote"}`;
  document.getElementById("espece").textContent = "Espèce : " + (data.e || "N/A");
  document.getElementById("type").textContent = "Type : " + (data.t || "N/A");
  document.getElementById("surnom").textContent = "Surnom : " + (data.s || "Aucun");
  document.getElementById("xp").textContent = "XP : " + data.x;
  document.getElementById("level").textContent = "Niveau : " + data.l;
  document.getElementById("eleveur").textContent = "Éleveur : " + (data.o || "Inconnu");

  // 🔁 Image appelée via le TYPE
  document.getElementById("typeImage").src = "img/" + data.t + ".png";

  // 🎨 Fond dynamique par espèce
  document.body.classList.add(data.e);

  const rarityDiv = document.createElement("div");
  rarityDiv.className = "info";
  rarityDiv.textContent = "Rareté : " + (r[data.r] || "Inconnue");
  document.querySelector(".ptipote-card").appendChild(rarityDiv);

  const acc = [data.a1, data.a2, data.a3, data.a4].filter(Boolean);
  if (acc.length) {
    const accList = document.createElement("div");
    accList.className = "info";
    accList.textContent = "Accessoires : " + acc.join(", ");
    document.querySelector(".ptipote-card").appendChild(accList);
  }

  const btn = document.querySelector(".btn-adopter");
  if (!data.on || data.on === " ") {
    btn.disabled = false;
    btn.textContent = "Adopter";
    btn.style.filter = "none";
    btn.style.cursor = "pointer";
  } else {
    btn.disabled = true;
    btn.textContent = "Déjà adopté";
  }
};
