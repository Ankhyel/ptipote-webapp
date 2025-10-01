function decodeHash() {
    try {
        const hash = window.location.hash.substring(1);
        if (!hash) throw new Error("Aucune donnée trouvée");

        // Étape 1 : décodage Base32 → Uint8Array
        const bytes = base32.decode.asBytes(hash);

        // Étape 2 : décompression LZString
        const decoded = LZString.decompressFromUint8Array(new Uint8Array(bytes));
        if (!decoded) throw new Error("Décompression échouée");

        // Étape 3 : parsing
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
    if (!data.e || !data.t) {
        afficherErreur("Erreur de lecture. Actualisation...");
        return;
    }

    document.getElementById("surnom").textContent = "Surnom : " + (data.s || "Aucun");
    document.getElementById("espece").textContent = "Espèce : " + (data.e || "Inconnue");
    document.getElementById("type").textContent = "Type : " + (data.t || "Inconnu");
    document.getElementById("xp").textContent = "XP : " + (data.x || "0");
    document.getElementById("niveau").textContent = "Niveau : " + (data.l || "0");
    document.getElementById("eleveur").textContent = "Éleveur : " + (data.o || "Inconnu");

    // Image par type
    let type = (data.t || "").toLowerCase();
    let imgElement = document.getElementById("typeImage");
    imgElement.src = "img/" + type + ".png";
    imgElement.onerror = () => { imgElement.src = "img/placeholder.png"; };
}

function afficherErreur(message) {
    document.body.innerHTML = `<div style="color:white;text-align:center;margin-top:50px;">${message}</div>`;
    setTimeout(() => location.reload(), 2000);
}

// Auto-refresh quand onglet actif
document.addEventListener("visibilitychange", () => {
    if (!document.hidden) {
        setInterval(() => location.reload(), 5000);
    }
});

// Lancer au chargement
window.onload = decodeHash;
