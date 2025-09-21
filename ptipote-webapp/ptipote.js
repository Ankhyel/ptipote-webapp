
window.onload = () => {
  const hash = window.location.hash.slice(1);
  if (!hash) return;

  // Simulation des données avec tous les champs
  const data = {
    e: "",      // Espèce
    t: "",       // Type
    s: "",           // Surnom
    r: "1",          // Rareté (1=Commun)
    b: "1",          // Batch
    l: "0",          // Niveau
    x: "0",          // XP
    o: "",           // Nom de l’éleveur
    on: "",          // Numéro éleveur
    ta: "0",         // Transfert (non affiché)
    a1: "", a2: "", a3: "", a4: "" // Accessoires
  };

  document.getElementById("name").textContent = `${data.t} (${data.e})`;
  document.getElementById("surnom").textContent = "Surnom : " + (data.s || "Aucun");
  document.getElementById("xp").textContent = "XP : " + data.x;
  document.getElementById("level").textContent = "Niveau : " + data.l;
  document.getElementById("eleveur").textContent = "Éleveur : " + (data.o || "Inconnu");

  // Image
  document.getElementById("typeImage").src = "img/" + data.e + ".png";

  // Appliquer fond par espèce
  document.body.classList.add(data.e);

  // Accessoires
  const acc = [data.a1, data.a2, data.a3, data.a4].filter(Boolean);
  if (acc.length) {
    const accList = document.createElement("div");
    accList.className = "info";
    accList.textContent = "Accessoires : " + acc.join(", ");
    document.querySelector(".ptipote-card").appendChild(accList);
  }

  // Rareté
  const rarity = {
    "1": "Commun",
    "2": "Spécial",
    "3": "Rare",
    "4": "Légendaire"
  }[data.r] || "Inconnue";

  const rarityDiv = document.createElement("div");
  rarityDiv.className = "info";
  rarityDiv.textContent = "Rareté : " + rarity;
  document.querySelector(".ptipote-card").appendChild(rarityDiv);
};
