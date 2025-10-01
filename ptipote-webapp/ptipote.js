function decodeHash() {
    try {
        const hash = window.location.hash.substring(1);
        if (!hash) throw new Error("Aucune donnée trouvée");

        const decoded = LZString.decompressFromEncodedURIComponent(hash);
        if (!decoded) throw new Error("Décompression échouée");

        const pairs = decoded.split(";");
        let data = {};
        pairs.forEach(pair => {
            if (pair.trim() !== "") {
                const [key, value] = pair.split("=");
                data[key.trim()] = value ? value.trim() : "";
            }
        });

        afficherPtipote(data);
    } catch (e) {
        afficherErreur("Erreur de lecture. Actualisation...");
    }
}

function afficherPtipote(data) {
    // Vérification si espèce et type existent
    if (!data.e || !data.t) {
        afficherErreur("Erreur de lecture. Actualisation...");
        return;
    }

    // Normalisation pour les images
    let espece = (data.e || "").toLowerCase();
    let type = (data.t || "").toLowerCase();

    // Affichage des infos
    document.getElementById("surnom").textContent = "Surnom : " + (data.s || "Aucun");
    document.getElementById("espece").textContent = "Espèce : " + (data.e || "Inconnue");
    document.getElementById("type").textContent = "Type : " + (data.t || "Inconnu");
    document.getElementById("xp").textContent = "XP : " + (data.x || "0");
    document.getElementById("niveau").textContent = "Niveau : " + (data.l || "0");
    document.getElementById("eleveur").textContent = "Éleveur : " + (data.o || "Inconnu");

    // Image en fonction du type
    let imgElement = document.getElementById("typeImage");
    imgElement.src = "img/" + type + ".png";
    imgElement.onerror = () => { imgElement.src = "img/placeholder.png"; };
}

function afficherErreur(message) {
    document.body.innerHTML = `<div style="color:white;text-align:center;margin-top:50px;">${message}</div>`;
    setTimeout(() => {
        location.reload();
    }, 2000);
}

// Lancer au chargement
window.onload = decodeHash;

// Auto-refresh si onglet actif
document.addEventListener("visibilitychange", () => {
    if (!document.hidden) {
        setInterval(() => {
            location.reload();
        }, 5000);
    }
});
