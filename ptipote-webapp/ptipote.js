function renderPtipote(data) {
  // Forcer en minuscules si les champs existent
  const espece = data.e ? data.e.toLowerCase() : "";
  const type = data.t ? data.t.toLowerCase() : "";

  // Vérification si les données essentielles sont présentes
  if (!espece || !type) {
    alert("❌ Erreur de lecture des données du P’tipote. La page va se recharger.");
    window.location.reload();
    return;
  }

  document.getElementById("surnom").textContent = "Surnom : " + (data.s || "Aucun");
  document.getElementById("espece").textContent = "Espèce : " + espece;
  document.getElementById("type").textContent = "Type : " + type;
  document.getElementById("xp").textContent = "XP : " + (data.x || 0);
  document.getElementById("niveau").textContent = "Niveau : " + (data.l || 0);
  document.getElementById("eleveur").textContent = "Éleveur : " + (data.o || "Inconnu");

  // Charger l’image en fonction du type (en minuscules)
  document.getElementById("typeImage").src = "img/" + type + ".png";
}

