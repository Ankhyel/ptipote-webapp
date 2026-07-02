import { initializeApp } from "https://www.gstatic.com/firebasejs/11.10.0/firebase-app.js";
import {
  getAuth,
  GoogleAuthProvider,
  onAuthStateChanged,
  signInWithPopup,
  signOut,
} from "https://www.gstatic.com/firebasejs/11.10.0/firebase-auth.js";
import {
  collection,
  collectionGroup,
  doc,
  getCountFromServer,
  getDoc,
  getFirestore,
  query,
  where,
} from "https://www.gstatic.com/firebasejs/11.10.0/firebase-firestore.js";

const BOOTSTRAP_ADMIN_UIDS = new Set(["taNxWXLMh2gJx5CHgmBB8Phl4c93"]);

const firebaseConfig = {
  apiKey: "AIzaSyCol40AnP-uim5rxMT63ZzuO-E2dfoFTpQ",
  authDomain: "ptipote-13508.firebaseapp.com",
  projectId: "ptipote-13508",
  storageBucket: "ptipote-13508.firebasestorage.app",
  messagingSenderId: "141039369930",
};

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);
const provider = new GoogleAuthProvider();
let currentDashboardRole = "";

const ids = [
  "authState",
  "authDetail",
  "authButton",
  "refreshButton",
  "notice",
  "usersCount",
  "usersHint",
  "figurinesCount",
  "figurinesHint",
  "publicFigurinesCount",
  "publicFigurinesHint",
  "transferRequestsCount",
  "transferRequestsHint",
  "transferPending",
  "transferAccepted",
  "transferConfirmed",
  "transferRefused",
];

const el = Object.fromEntries(ids.map((id) => [id, document.getElementById(id)]));

function setNotice(title, message, isError = false) {
  el.notice.classList.toggle("error", isError);
  el.notice.innerHTML = `<strong>${escapeHtml(title)}</strong><span>${escapeHtml(message)}</span>`;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function setValue(valueId, hintId, result) {
  if (result.ok) {
    el[valueId].textContent = new Intl.NumberFormat("fr-FR").format(result.count);
    el[hintId].textContent = result.label;
    return;
  }

  el[valueId].textContent = "-";
  el[hintId].textContent = result.message;
}

async function safeCount(label, ref) {
  try {
    const snapshot = await getCountFromServer(ref);
    return { ok: true, count: snapshot.data().count, label };
  } catch (error) {
    return {
      ok: false,
      count: null,
      label,
      message: readableFirebaseError(error),
      error,
    };
  }
}

function readableFirebaseError(error) {
  if (error?.code === "permission-denied") return "Acces refuse par les rules";
  if (error?.code === "unauthenticated") return "Connexion requise";
  return error?.message || "Lecture impossible";
}

function clearStats() {
  setValue("usersCount", "usersHint", { ok: false, message: "Reserve admin/dev" });
  setValue("figurinesCount", "figurinesHint", { ok: false, message: "Reserve admin/dev" });
  setValue("publicFigurinesCount", "publicFigurinesHint", { ok: false, message: "Reserve admin/dev" });
  setValue("transferRequestsCount", "transferRequestsHint", { ok: false, message: "Reserve admin/dev" });
  el.transferPending.textContent = "-";
  el.transferAccepted.textContent = "-";
  el.transferConfirmed.textContent = "-";
  el.transferRefused.textContent = "-";
}

async function getDashboardRole(user) {
  if (BOOTSTRAP_ADMIN_UIDS.has(user.uid)) {
    return "admin";
  }

  const snapshot = await getDoc(doc(db, "users", user.uid));
  const role = snapshot.exists() ? snapshot.data().role : "";
  return role === "admin" || role === "dev" ? role : "";
}

async function loadStats(role) {
  if (!auth.currentUser) {
    setNotice("Connexion requise", "Les compteurs sont lances apres authentification Google.", false);
    return;
  }

  if (!role) {
    clearStats();
    setNotice("Acces refuse", "Ton document utilisateur doit avoir le role admin ou dev.", true);
    return;
  }

  setLoading(true);
  setNotice("Lecture en cours", "Comptage Firestore via agregations count(), sans exporter les documents.", false);

  const [users, figurines, publicFigurines, transferRequests, pending, accepted, confirmed, refused] =
    await Promise.all([
      safeCount("users", collection(db, "users")),
      safeCount("users/*/figurines", collectionGroup(db, "figurines")),
      safeCount("publicFigurines", collection(db, "publicFigurines")),
      safeCount("transferRequests", collection(db, "transferRequests")),
      safeCount("status == pending", query(collection(db, "transferRequests"), where("status", "==", "pending"))),
      safeCount("status == accepted", query(collection(db, "transferRequests"), where("status", "==", "accepted"))),
      safeCount("status == confirmed", query(collection(db, "transferRequests"), where("status", "==", "confirmed"))),
      safeCount("status == refused", query(collection(db, "transferRequests"), where("status", "==", "refused"))),
    ]);

  setValue("usersCount", "usersHint", users);
  setValue("figurinesCount", "figurinesHint", figurines);
  setValue("publicFigurinesCount", "publicFigurinesHint", publicFigurines);
  setValue("transferRequestsCount", "transferRequestsHint", transferRequests);
  el.transferPending.textContent = pending.ok ? pending.count : "-";
  el.transferAccepted.textContent = accepted.ok ? accepted.count : "-";
  el.transferConfirmed.textContent = confirmed.ok ? confirmed.count : "-";
  el.transferRefused.textContent = refused.ok ? refused.count : "-";

  const failures = [users, figurines, publicFigurines, transferRequests, pending, accepted, confirmed, refused]
    .filter((result) => !result.ok);

  if (failures.length) {
    setNotice(
      "Rules a completer",
      `${failures.length} compteur(s) refuse(s) ou indisponible(s). Voir README du dashboard pour les rules admin.`,
      true,
    );
  } else {
    setNotice("Stats a jour", `Derniere lecture: ${new Date().toLocaleString("fr-FR")}.`, false);
  }

  setLoading(false);
}

function setLoading(isLoading) {
  el.refreshButton.disabled = isLoading;
  el.authButton.disabled = isLoading;
}

async function handleAuthClick() {
  if (auth.currentUser) {
    await signOut(auth);
    return;
  }

  await signInWithPopup(auth, provider);
}

onAuthStateChanged(auth, (user) => {
  if (!user) {
    currentDashboardRole = "";
    el.authState.textContent = "Non connecte";
    el.authDetail.textContent = "Acces reserve admin/dev";
    el.authButton.textContent = "Connexion";
    clearStats();
    return;
  }

  el.authState.textContent = user.displayName || user.email || "Compte Firebase";
  el.authButton.textContent = "Deconnexion";
  getDashboardRole(user)
    .then((role) => {
      currentDashboardRole = role;
      el.authDetail.textContent = role ? `${user.email || user.uid} - ${role}` : user.email || user.uid;
      loadStats(role);
    })
    .catch((error) => {
      currentDashboardRole = "";
      clearStats();
      el.authDetail.textContent = user.email || user.uid;
      setNotice("Role illisible", readableFirebaseError(error), true);
    });
});

el.authButton.addEventListener("click", () => {
  handleAuthClick().catch((error) => {
    setNotice("Auth impossible", readableFirebaseError(error), true);
  });
});

el.refreshButton.addEventListener("click", () => {
  loadStats(currentDashboardRole);
});
