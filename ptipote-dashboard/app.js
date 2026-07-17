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
  serverTimestamp,
  setDoc,
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
let ptipoteStatsConfig = {};
let campHeartConfig = {};
let kernelConfig = {};
let lisiereForageConfig = {};
let securityTowerConfig = {};
let fablabConfig = {};
let recyclerConfig = {};
const PTIPOTE_STATS_FIELDS = [
  "maxVitality",
  "vitalityRecoveryPerMinute",
  "alcoveVitalityRecoveryPerMinute",
  "naturalVitalityRecoveryMinutes",
  "happyVitalityRecoveryPerMinute",
  "minVitalityBeforeAutoRest",
  "minimumMissionVitality",
  "maxRest",
  "sleepRestRecoveryPerMinute",
  "awakeRestLossMinutes",
  "missionRestLossRatio",
  "wellRestedThreshold",
  "restedThreshold",
  "tiredThreshold",
  "exhaustedThreshold",
  "wellRestedXpBonus",
  "wellRestedRewardBonus",
  "tiredXpPenalty",
  "tiredRewardPenalty",
  "indigestionXpPenalty",
  "maxHunger",
  "maxOverfedHunger",
  "baseHunger",
  "hungerDecayMinutes",
  "missionHungerCostRatio",
  "wellFedHungerThreshold",
  "wellFedVitalityRecoveryBonus",
  "indigestionHungerThreshold",
  "indigestionVitalityRecoveryPenalty",
  "happyVitalityThreshold",
  "happyHungerThreshold",
  "cuddleCooldownMinutes",
  "cuddleCareDurationMinutes",
  "vitalityBubbleThreshold",
  "hungerBubbleThreshold",
  "cuddleBubbleWarningMinutes",
  "needBubbleMinIntervalMinutes",
  "needBubbleMaxIntervalMinutes",
  "needBubbleDisplayDurationSeconds",
  "happyNeedsRequired",
  "okayNeedsRequired",
  "baseHappiness",
  "maxHappiness",
  "happinessDecayPerHour",
  "xpRequiredBase",
  "xpRequiredMultiplier",
  "baseEVG",
  "baseForageEfficiency",
  "baseSafetyContribution",
  "baseMarketContribution",
];

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
  "statPtipoteForm",
  "statPtipoteStatus",
  "resetPtipoteStatsButton",
  "exportPtipoteStatsButton",
  "kernelStatus",
  "kernelConfigList",
  "exportKernelButton",
  "kernelProgressEditor",
  "exportKernelProgressButton",
  "campHeartStatus",
  "campHeartStageList",
  "publishCampHeartButton",
  "lisiereForageStatus",
  "lisiereForageList",
  "publishLisiereForageButton",
  "securityTowerStatus",
  "securityTowerConfigList",
  "publishSecurityTowerButton",
  "fablabStatus",
  "fablabConfigList",
  "publishFablabButton",
  "recyclerStatus",
  "recyclerConfigList",
  "exportRecyclerButton",
  "craftStatus",
  "craftRecipeList",
  "craftRecipeForm",
  "publishCraftButton",
  "zone0SettingsForm",
  "zone0SettingsStatus",
  "publishZone0SettingsButton",
  "marketSettingsForm",
  "marketSettingsStatus",
  "publishMarketButton",
];

const el = Object.fromEntries(ids.map((id) => [id, document.getElementById(id)]));
const dashboardTabButtons = Array.from(document.querySelectorAll("[data-dashboard-tab]"));
const dashboardPanels = Array.from(document.querySelectorAll("[data-dashboard-panel]"));

function setupDashboardTabs() {
  dashboardTabButtons.forEach((button) => {
    button.addEventListener("click", () => {
      const target = button.dataset.dashboardTab;
      dashboardTabButtons.forEach((item) => {
        item.classList.toggle("active", item === button);
      });
      dashboardPanels.forEach((panel) => {
        panel.classList.toggle("active", panel.dataset.dashboardPanel === target);
      });
    });
  });
}

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

async function loadPtipoteStatsConfig() {
  try {
    const response = await fetch("./ptipote-stats-config.json", { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const baseConfig = await response.json();
    let publishedConfig = null;
    if (auth.currentUser && currentDashboardRole) {
      const snapshot = await getDoc(doc(db, "gameConfigs", "zone0"));
      const values = snapshot.data()?.ptipoteStats;
      if (values && typeof values === "object" && !Array.isArray(values)) {
        publishedConfig = values;
      }
    }
    ptipoteStatsConfig = { ...baseConfig, ...(publishedConfig || {}) };
    renderPtipoteStatsForm();
    el.statPtipoteStatus.textContent = publishedConfig
      ? "Configuration publiee chargee depuis Firestore."
      : "Valeurs V1 embarquees chargees. Publie-les pour les appliquer a l'application.";
  } catch (error) {
    el.statPtipoteStatus.textContent = `Configuration Stat Ptipote illisible: ${error.message}`;
  }
}

function renderPtipoteStatsForm() {
  el.statPtipoteForm.innerHTML = PTIPOTE_STATS_FIELDS.map((field) => `
    <div class="stat-field">
      <label for="stat-${field}">${escapeHtml(field)}</label>
      <input id="stat-${field}" name="${escapeHtml(field)}" type="number" step="0.01" value="${escapeHtml(ptipoteStatsConfig[field] ?? "")}">
    </div>
  `).join("") + `
    <div class="stat-field stat-field-wide">
      <label>XP requis par niveau</label>
      <p id="xpRequiredPreview"></p>
    </div>
  `;
  renderXpRequiredPreview();

  el.statPtipoteForm.querySelectorAll("input").forEach((input) => {
    input.addEventListener("input", () => {
      const value = Number(input.value);
      ptipoteStatsConfig[input.name] = Number.isFinite(value) ? value : input.value;
      renderXpRequiredPreview();
      el.statPtipoteStatus.textContent = "Modifications en attente. Clique sur Publier dans l'application.";
    });
  });
}

function renderXpRequiredPreview() {
  const preview = document.getElementById("xpRequiredPreview");
  if (!preview) return;
  const xpBase = Number(ptipoteStatsConfig.xpRequiredBase || 100);
  const xpMultiplier = Number(ptipoteStatsConfig.xpRequiredMultiplier || 1.25);
  preview.textContent = [1, 2, 3, 4, 5]
    .map((level) => `Niv. ${level}→${level + 1}: ${Math.round(xpBase * Math.pow(xpMultiplier, level - 1))} XP`)
    .join(" · ");
}

async function publishPtipoteStatsConfig() {
  if (!auth.currentUser || !currentDashboardRole) {
    throw new Error("Connexion admin ou dev requise.");
  }
  const values = Object.fromEntries(
    PTIPOTE_STATS_FIELDS.map((field) => [field, Number(ptipoteStatsConfig[field])]),
  );
  const invalidField = Object.entries(values).find(([, value]) => !Number.isFinite(value));
  if (invalidField) {
    throw new Error(`Valeur invalide pour ${invalidField[0]}.`);
  }
  await setDoc(
    doc(db, "gameConfigs", "zone0"),
    {
      schemaVersion: 1,
      ptipoteStats: values,
      ptipoteStatsUpdatedAt: serverTimestamp(),
      ptipoteStatsUpdatedBy: auth.currentUser.uid,
    },
    { merge: true },
  );
  el.statPtipoteStatus.textContent = "Configuration publiee. Les applications connectees se mettent a jour.";
}

async function loadKernelConfig() {
  try {
    const response = await fetch("./kernel-config.json", { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    kernelConfig = await response.json();
    renderKernelConfig();
    el.kernelStatus.textContent = "Configuration Camp / Kernel chargée depuis le JSON versionné.";
  } catch (error) {
    el.kernelStatus.textContent = `Configuration Kernel illisible: ${error.message}`;
  }
}

function renderKernelConfig() {
  const capacity = kernelConfig.populationCapacityByCampHeartLevel || {};
  const missions = Array.isArray(kernelConfig.missions) ? kernelConfig.missions : [];
  const plans = Array.isArray(kernelConfig.plans) ? kernelConfig.plans : [];
  const rows = [
    ["Population départ", kernelConfig.startingPopulation],
    ["Bien-être départ", `${kernelConfig.startingWellbeing}%`],
    ["Bio-batteries départ", kernelConfig.startingBioBatteries],
    ["Demandes secondaires max", kernelConfig.maxRefugeRequests],
    ["Couleurs HUD", `rouge < ${kernelConfig.wellbeingRedThreshold} · orange < ${kernelConfig.wellbeingOrangeThreshold} · vert au-delà`],
    ["Capacité population", Object.entries(capacity).map(([level, value]) => `Cœur ${level}: ${value}`).join(" · ")],
  ];
  const missionRows = missions.map((mission) => [
    `Mission: ${mission.title}`,
    `${mission.type} · ${mission.conditionType} ${mission.requiredAmount} · +${mission.populationReward} habitant(s) · +${mission.bioBatteryReward || 0} bio-batterie(s)`,
  ]);
  const planRows = plans.map((plan) => [
    `Plan: ${plan.title}`,
    `Cœur requis ${plan.requiredCampHeartLevel} · ${plan.description}`,
  ]);
  el.kernelConfigList.innerHTML = [...rows, ...missionRows, ...planRows].map(([label, value]) => `
    <div class="stage-row">
      <div><strong>${escapeHtml(label)}</strong><span>${escapeHtml(value)}</span></div>
      <strong>Kernel</strong>
    </div>
  `).join("");
}

function exportKernelConfig() {
  const blob = new Blob([JSON.stringify(kernelConfig, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "kernel-config.json";
  link.click();
  URL.revokeObjectURL(url);
}

async function loadCampHeartConfig() {
  try {
    const response = await fetch("./camp-heart-config.json", { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    campHeartConfig = await response.json();
    renderCampHeartConfig();
    el.campHeartStatus.textContent = "Paliers charges depuis le JSON versionne.";
  } catch (error) {
    el.campHeartStatus.textContent = `Configuration Cœur du Camp illisible: ${error.message}`;
  }
}

function renderCampHeartConfig() {
  const stages = Array.isArray(campHeartConfig.stages) ? campHeartConfig.stages : [];
  el.campHeartStageList.innerHTML = stages.map((stage) => `
    <div class="stage-row">
      <div>
        <strong>Niv. ${escapeHtml(stage.level)} - ${escapeHtml(stage.label)}</strong>
        <span>${escapeHtml(stage.populationLabel)} · ${escapeHtml(stage.activePtipoteComfortLimit)} P'TIPOTE(s) confort · bonheur +${escapeHtml(stage.refugeHappinessBonus)}</span>
      </div>
      <strong>${stage.xpRequiredForNextLevel == null ? "max V1" : `${escapeHtml(stage.xpRequiredForNextLevel)} XP`}</strong>
    </div>
  `).join("");
}

async function loadLisiereForageConfig() {
  try {
    const response = await fetch("./lisiere-forage-config.json", { cache: "no-store" });
    if (!response.ok) throw new Error("HTTP " + response.status);
    lisiereForageConfig = await response.json();
    renderLisiereForageConfig();
    el.lisiereForageStatus.textContent = "Configuration Lisière chargée depuis le JSON versionné.";
  } catch (error) {
    el.lisiereForageStatus.textContent = "Configuration Lisière illisible: " + error.message;
  }
}

function renderLisiereForageConfig() {
  const durations = Array.isArray(lisiereForageConfig.durations) ? lisiereForageConfig.durations : [];
  const intensities = Array.isArray(lisiereForageConfig.intensities) ? lisiereForageConfig.intensities : [];
  const biomes = Array.isArray(lisiereForageConfig.biomes) ? lisiereForageConfig.biomes : [];
  const rows = [];
  rows.push('<div class="stage-row"><div><strong>Temps</strong><span>Multiplicateur test x' + escapeHtml(lisiereForageConfig.forageTimeScale) + ' · ' + durations.map((item) => escapeHtml(item.label) + ' => ' + escapeHtml(item.realMinutes) + ' min').join(' · ') + '</span></div><strong>durées</strong></div>');
  rows.push('<div class="stage-row"><div><strong>Intensités</strong><span>' + intensities.map((item) => escapeHtml(item.label) + ' x' + escapeHtml(item.rewardMultiplier) + ' risque ' + escapeHtml(item.riskModifierPercent) + '%').join(' · ') + '</span></div><strong>coûts</strong></div>');
  const xpByDuration = lisiereForageConfig.xpGainByDuration || {};
  const xpByIntensity = lisiereForageConfig.intensityXpMultiplier || {};
  rows.push('<div class="stage-row"><div><strong>XP mission</strong><span>Base par durée: ' + Object.entries(xpByDuration).map(([key, value]) => escapeHtml(key) + ' +' + escapeHtml(value)).join(' · ') + ' | intensité: ' + Object.entries(xpByIntensity).map(([key, value]) => escapeHtml(key) + ' x' + escapeHtml(value)).join(' · ') + '</span></div><strong>progression</strong></div>');
  rows.push('<div class="stage-row"><div><strong>Formule danger</strong><span>Minimum ' + escapeHtml(lisiereForageConfig.minimumMissionRisk) + '% · réduction sécurité x' + escapeHtml(lisiereForageConfig.securityRiskReductionFactor) + '</span></div><strong>sécurité</strong></div>');
  biomes.forEach((biome) => {
    const organic = biome.rewards && biome.rewards.Organique ? biome.rewards.Organique : 0;
    const mineral = biome.rewards && biome.rewards["Minéral"] ? biome.rewards["Minéral"] : 0;
    const hazards = Array.isArray(biome.hazards) ? biome.hazards.join(', ') : '';
    rows.push('<div class="stage-row"><div><strong>' + escapeHtml(biome.label) + '</strong><span>Risque ' + escapeHtml(biome.baseRiskPercent) + '% · Organique ' + escapeHtml(organic) + ' · Minéral ' + escapeHtml(mineral) + ' · dangers ' + escapeHtml(hazards) + '</span></div><strong>biome</strong></div>');
  });
  el.lisiereForageList.innerHTML = rows.join('');
}

function exportLisiereForageConfig() {
  const blob = new Blob([JSON.stringify(lisiereForageConfig, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "lisiere-forage-config.json";
  link.click();
  URL.revokeObjectURL(url);
}

async function loadSecurityTowerConfig() {
  try {
    const response = await fetch("./security-tower-config.json", { cache: "no-store" });
    if (!response.ok) throw new Error("HTTP " + response.status);
    securityTowerConfig = await response.json();
    renderSecurityTowerConfig();
    el.securityTowerStatus.textContent = "Configuration Tour chargée depuis le JSON versionné.";
  } catch (error) {
    el.securityTowerStatus.textContent = "Configuration Tour illisible: " + error.message;
  }
}

function renderSecurityTowerConfig() {
  const slots = securityTowerConfig.slotsByLevel || {};
  const labels = Array.isArray(securityTowerConfig.dangerLabels) ? securityTowerConfig.dangerLabels : [];
  const rows = [
    ["Coût Organique", securityTowerConfig.constructionCostOrganic],
    ["Coût Minéral", securityTowerConfig.constructionCostMineral],
    ["Cœur requis", securityTowerConfig.requiredCampHeartLevel],
    ["Sécurité max", securityTowerConfig.maxSecurity],
    ["Sécurité initiale", securityTowerConfig.initialSecurity],
    ["Gain sécurité / tick", securityTowerConfig.securityGainPerTick],
    ["Durée tick", `${securityTowerConfig.tickMinutes} min`],
    ["Coût Vitalité / tick", securityTowerConfig.vitalityCostPerTick],
    ["Décroissance sécurité", securityTowerConfig.securityDecayPerTick],
    ["Recharge manuelle", `+${securityTowerConfig.manualRechargeSecurityGain} sécurité`],
    ["Cooldown recharge", `${securityTowerConfig.manualRechargeCooldownMinutes} min`],
    ["Risque minimum", `${securityTowerConfig.minimumMissionRisk}%`],
    ["Coefficient réduction", securityTowerConfig.securityRiskReductionFactor],
    ["Slots", Object.entries(slots).map(([level, count]) => `niv. ${level}: ${count}`).join(" · ")],
    ["Labels danger", labels.map((item) => `${item.label} ${item.min}-${item.max}%`).join(" · ")],
  ];
  el.securityTowerConfigList.innerHTML = rows.map(([label, value]) => `
    <div class="stage-row">
      <div><strong>${escapeHtml(label)}</strong><span>${escapeHtml(value)}</span></div>
      <strong>Tour</strong>
    </div>
  `).join("");
}

function exportSecurityTowerConfig() {
  const blob = new Blob([JSON.stringify(securityTowerConfig, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "security-tower-config.json";
  link.click();
  URL.revokeObjectURL(url);
}

async function loadFablabConfig() {
  try {
    const response = await fetch("./fablab-config.json", { cache: "no-store" });
    if (!response.ok) throw new Error("HTTP " + response.status);
    fablabConfig = await response.json();
    renderFablabConfig();
    el.fablabStatus.textContent = "Configuration Fablab chargée depuis le JSON versionné.";
  } catch (error) {
    el.fablabStatus.textContent = "Configuration Fablab illisible: " + error.message;
  }
}

function renderFablabConfig() {
  const rows = [
    ["Construction Organique niv. 1", fablabConfig.constructionCostLevel1Organic],
    ["Construction Minéral niv. 1", fablabConfig.constructionCostLevel1Mineral],
    ["Capacité stock de base", fablabConfig.baseGlobalStockCapacity],
    ["Bonus stock par niveau", fablabConfig.stockCapacityBonusPerFablabLevel],
    ["Niveau max Fablab", fablabConfig.fablabMaxLevel],
    ["Niveau max Cuisine", fablabConfig.cuisineMaxLevel],
    ["Niveau max Atelier", fablabConfig.atelierMaxLevel],
    ["Niveau max Recycleur", fablabConfig.recyclerMaxLevel],
    ["Amélioration Cuisine", `${fablabConfig.cuisineUpgradeOrganic} Organique · ${fablabConfig.cuisineUpgradeMineral} Minéral`],
    ["Amélioration Atelier", `${fablabConfig.atelierUpgradeOrganic} Organique · ${fablabConfig.atelierUpgradeMineral} Minéral`],
    ["Amélioration Recycleur", `${fablabConfig.recyclerUpgradeOrganic} Organique · ${fablabConfig.recyclerUpgradeMineral} Minéral`],
    ["Durée amélioration unité", `${fablabConfig.unitUpgradeDurationMinutes} min`],
    ["Cuisine active niveau", fablabConfig.cuisineUnlockLevel],
    ["Atelier requis Cœur", fablabConfig.atelierUnlockCampHeartLevel],
    ["Recycleur requis Cœur", fablabConfig.recyclerUnlockCampHeartLevel],
  ];
  el.fablabConfigList.innerHTML = rows.map(([label, value]) => `
    <div class="stage-row">
      <div><strong>${escapeHtml(label)}</strong><span>${escapeHtml(value)}</span></div>
      <strong>V1</strong>
    </div>
  `).join("");
}

async function loadRecyclerConfig() {
  try {
    const response = await fetch("./waste-recycler-config.json", { cache: "no-store" });
    if (!response.ok) throw new Error("HTTP " + response.status);
    recyclerConfig = await response.json();
    const rows = [
      ["Cycle déchets refuge", `${recyclerConfig.wasteGenerationCycleMinutes} min`],
      ["Population par Déchet", recyclerConfig.populationPerWasteUnit],
      ["Bâtiments par Déchet", recyclerConfig.buildingsPerWasteUnit],
      ["Déchets Lisière", `${recyclerConfig.wasteRewardMinimumPercent}–${recyclerConfig.wasteRewardMaximumPercent}%`],
      ["Cœur requis", recyclerConfig.recyclerUnlockCampHeartLevel],
      ["Niveau initial / maximum", `${recyclerConfig.initialRecyclerLevel} / ${recyclerConfig.recyclerMaxLevel}`],
      ["Cuve de base", recyclerConfig.baseWasteTankCapacity],
      ["Coût niveau 1", `${recyclerConfig.baseWasteRequired} Déchets → ${recyclerConfig.outputResourcesPerCycle} ressources`],
      ["Énergie / Bio-batterie", recyclerConfig.energyUnitsPerBioBattery],
      ["Coût par cycle", recyclerConfig.energyCostPerCycle],
      ["Stock sortie / attente", `${recyclerConfig.outputStorageCapacity} / ${recyclerConfig.pendingWasteCapacity}`],
      ["Temps par niveau", JSON.stringify(recyclerConfig.cycleMinutesByLevel)],
    ];
    el.recyclerConfigList.innerHTML = rows.map(([label, value]) => `
      <div class="stage-row"><div><strong>${escapeHtml(label)}</strong><span>${escapeHtml(value)}</span></div><strong>V1</strong></div>
    `).join("");
    el.recyclerStatus.textContent = "Configuration Déchets / Recycleur chargée depuis le JSON versionné.";
  } catch (error) {
    el.recyclerStatus.textContent = "Configuration Recycleur illisible: " + error.message;
  }
}

function exportRecyclerConfig() {
  const blob = new Blob([JSON.stringify(recyclerConfig, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "waste-recycler-config.json";
  link.click();
  URL.revokeObjectURL(url);
}

function craftNumber(value, minimum = 0) {
  return Math.max(minimum, Number(value) || minimum);
}

function craftIngredients(recipe) {
  return Array.isArray(recipe.ingredients) ? recipe.ingredients : [];
}

function renderCraftConfig() {
  const recipes = Array.isArray(zone0Settings.craft?.recipes) ? zone0Settings.craft.recipes : [];
  el.craftRecipeList.innerHTML = recipes.map((recipe, index) => {
    const ingredients = craftIngredients(recipe)
      .map((item) => `${escapeHtml(item.amount)} ${escapeHtml(item.resource)}`).join(" + ");
    const section = recipe.craftSection === "atelier" ? "Atelier" : "Cuisine";
    const stackLimit = craftNumber(recipe.stackLimit || 1, 1);
    const requirement = `Kernel ${craftNumber(recipe.kernelTrustLevel, 1)} · Éleveur ${craftNumber(recipe.breederLevel, 1)} · Bâtisseur ${craftNumber(recipe.builderLevel, 1)} · Restaurateur ${craftNumber(recipe.restorerLevel, 1)} · Cuisine ${craftNumber(recipe.cuisineLevel)} · Atelier ${craftNumber(recipe.atelierLevel)}`;
    const ingredientFields = [0, 1, 2].map((slot) => {
      const ingredient = craftIngredients(recipe)[slot] || { resource: "", amount: 0 };
      return `<div class="stat-field"><label>Ingrédient ${slot + 1}</label><input type="text" data-craft-index="${index}" data-craft-ingredient="${slot}" data-craft-part="resource" value="${escapeHtml(ingredient.resource)}"></div><div class="stat-field"><label>Quantité ${slot + 1}</label><input type="number" min="0" data-craft-index="${index}" data-craft-ingredient="${slot}" data-craft-part="amount" value="${escapeHtml(ingredient.amount)}"></div>`;
    }).join("");
    return `<details class="config-card craft-card">
      <summary><span><strong>${escapeHtml(recipe.displayName || recipe.resultItem)}</strong><small>${section} · ${ingredients || "sans ingrédient"} → ${escapeHtml(recipe.resultAmount || 1)} ${escapeHtml(recipe.resultItem)} · ${requirement}</small></span><span class="pill">pile ${stackLimit}</span></summary>
      <div class="stat-form config-card-body">
        <div class="stat-field"><label>Nom</label><input type="text" data-craft-index="${index}" data-craft-field="displayName" value="${escapeHtml(recipe.displayName || "")}"></div>
        <div class="stat-field"><label>Section de fabrication</label><select data-craft-index="${index}" data-craft-field="craftSection"><option value="cuisine" ${recipe.craftSection !== "atelier" ? "selected" : ""}>Cuisine</option><option value="atelier" ${recipe.craftSection === "atelier" ? "selected" : ""}>Atelier</option></select></div>
        <div class="stat-field"><label>Objet résultat</label><input type="text" data-craft-index="${index}" data-craft-field="resultItem" value="${escapeHtml(recipe.resultItem || "")}"></div>
        <div class="stat-field"><label>Quantité créée</label><input type="number" min="1" data-craft-index="${index}" data-craft-field="resultAmount" value="${escapeHtml(recipe.resultAmount || 1)}"></div>
        <div class="stat-field"><label>Durée (minutes)</label><input type="number" min="1" data-craft-index="${index}" data-craft-field="durationMinutes" value="${escapeHtml(recipe.durationMinutes || 1)}"></div>
        <div class="stat-field"><label>Taille maximale d'une pile</label><input type="number" min="1" data-craft-index="${index}" data-craft-field="stackLimit" value="${stackLimit}"></div>
        ${ingredientFields}
        <div class="stat-field"><label>Confiance du Kernel</label><input type="number" min="1" data-craft-index="${index}" data-craft-field="kernelTrustLevel" value="${craftNumber(recipe.kernelTrustLevel, 1)}"></div>
        <div class="stat-field"><label>Niveau Éleveur</label><input type="number" min="1" data-craft-index="${index}" data-craft-field="breederLevel" value="${craftNumber(recipe.breederLevel, 1)}"></div>
        <div class="stat-field"><label>Niveau Bâtisseur</label><input type="number" min="1" data-craft-index="${index}" data-craft-field="builderLevel" value="${craftNumber(recipe.builderLevel, 1)}"></div>
        <div class="stat-field"><label>Niveau Restaurateur</label><input type="number" min="1" data-craft-index="${index}" data-craft-field="restorerLevel" value="${craftNumber(recipe.restorerLevel, 1)}"></div>
        <div class="stat-field"><label>Niveau Cuisine</label><input type="number" min="0" data-craft-index="${index}" data-craft-field="cuisineLevel" value="${craftNumber(recipe.cuisineLevel)}"></div>
        <div class="stat-field"><label>Niveau Atelier</label><input type="number" min="0" data-craft-index="${index}" data-craft-field="atelierLevel" value="${craftNumber(recipe.atelierLevel)}"></div>
        <div class="stat-field stat-field-wide"><button class="ghost" type="button" data-delete-craft="${index}" ${recipe.id === "simpleMeal" ? "disabled" : ""}>${recipe.id === "simpleMeal" ? "Recette de départ" : "Supprimer la recette"}</button></div>
      </div>
    </details>`;
  }).join("");
  el.craftRecipeList.querySelectorAll("[data-craft-index]").forEach((input) => {
    const updateRecipe = () => {
      const recipe = zone0Settings.craft.recipes[Number(input.dataset.craftIndex)];
      if (input.dataset.craftIngredient !== undefined) {
        const slot = Number(input.dataset.craftIngredient);
        recipe.ingredients = craftIngredients(recipe);
        recipe.ingredients[slot] ||= { resource: "", amount: 0 };
        recipe.ingredients[slot][input.dataset.craftPart] = input.dataset.craftPart === "amount" ? craftNumber(input.value) : input.value;
        recipe.ingredients = recipe.ingredients.filter((item) => item.resource && craftNumber(item.amount) > 0);
      } else {
        const field = input.dataset.craftField;
        recipe[field] = input.type === "number" ? craftNumber(input.value, field === "cuisineLevel" || field === "atelierLevel" ? 0 : 1) : input.value;
      }
      el.craftStatus.textContent = "Modifications en attente. Clique sur Publier dans l'app.";
    };
    input.addEventListener("input", updateRecipe);
    input.addEventListener("change", updateRecipe);
  });
  el.craftRecipeList.querySelectorAll("[data-delete-craft]").forEach((button) => {
    button.addEventListener("click", () => {
      zone0Settings.craft.recipes.splice(Number(button.dataset.deleteCraft), 1);
      renderCraftConfig();
      el.craftStatus.textContent = "Recette supprimée. Clique sur Publier dans l'app pour appliquer ce retrait.";
    });
  });
}

function addCraftRecipe(event) {
  event.preventDefault();
  const form = new FormData(el.craftRecipeForm);
  const displayName = String(form.get("displayName") || "Nouvelle recette").trim();
  const resultItem = String(form.get("resultItem") || displayName).trim();
  const resource2 = String(form.get("ingredientResource2") || "");
  const ingredients = [{ resource: String(form.get("ingredientResource") || "Organique"), amount: craftNumber(form.get("ingredientAmount"), 1) }];
  if (resource2 && craftNumber(form.get("ingredientAmount2")) > 0) ingredients.push({ resource: resource2, amount: craftNumber(form.get("ingredientAmount2")) });
  const id = displayName.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || `recipe-${Date.now()}`;
  if (zone0Settings.craft.recipes.some((recipe) => recipe.id === id)) {
    el.craftStatus.textContent = "Une recette utilise déjà cet identifiant. Change son nom avant de l'ajouter.";
    return;
  }
  zone0Settings.craft.recipes.push({
    id, displayName, craftSection: String(form.get("craftSection") || "cuisine"), ingredients, contextIngredients: {},
    cuisineLevel: craftNumber(form.get("cuisineLevel")), atelierLevel: craftNumber(form.get("atelierLevel")), kernelTrustLevel: craftNumber(form.get("kernelTrustLevel"), 1),
    breederLevel: craftNumber(form.get("breederLevel"), 1), builderLevel: craftNumber(form.get("builderLevel"), 1), restorerLevel: craftNumber(form.get("restorerLevel"), 1),
    resultItem, resultAmount: craftNumber(form.get("resultAmount"), 1), durationMinutes: 1, stackLimit: craftNumber(form.get("stackLimit"), 1),
    isConsumable: form.get("isConsumable") === "true", foodType: String(form.get("foodType") || "meal"), hungerRestore: craftNumber(form.get("hungerRestore")), vitalityRestore: craftNumber(form.get("vitalityRestore")), energyCost: 0,
  });
  renderCraftConfig();
  el.craftStatus.textContent = "Recette ajoutée. Clique sur Publier dans l'app pour l'ajouter à l'application.";
}

function exportFablabConfig() {
  const blob = new Blob([JSON.stringify(fablabConfig, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "fablab-config.json";
  link.click();
  URL.revokeObjectURL(url);
}

function exportCampHeartConfig() {
  const blob = new Blob([JSON.stringify(campHeartConfig, null, 2)], {
    type: "application/json",
  });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "camp-heart-config.json";
  link.click();
  URL.revokeObjectURL(url);
}

const ZONE0_SECTION_SOURCES = {
  campHeart: "camp-heart-config.json",
  lisiere: "lisiere-forage-config.json",
  tower: "security-tower-config.json",
  towerOperations: "tower-operations-config.json",
  fablab: "fablab-config.json",
  workshop: "workshop-config.json",
  craft: "craft-config.json",
  market: "market-config.json",
  housing: "housing-config.json",
};

const ZONE0_SECTION_LABELS = {
  campHeart: "Paliers du Cœur du Camp",
  lisiere: "Lisière",
  tower: "Tour de sécurité",
  towerOperations: "Exploration, météo et marchand",
  fablab: "Fablab",
  workshop: "Atelier",
  craft: "Craft",
  market: "Marché",
  housing: "Maison et logements",
};

// These legacy JSON display fields are not gameplay inputs in Flutter. They
// stay versioned as documentation, but cannot be published as active tuning.
const ZONE0_NON_RUNTIME_PATHS = new Set([
  "lisiere.durations.0.realMinutes", "lisiere.durations.1.realMinutes",
  "lisiere.durations.2.realMinutes", "lisiere.durations.3.realMinutes",
  "tower.minimumMissionRisk", "tower.securityRiskReductionFactor",
  "tower.dangerLabels.0.min", "tower.dangerLabels.0.max",
  "tower.dangerLabels.1.min", "tower.dangerLabels.1.max",
  "tower.dangerLabels.2.min", "tower.dangerLabels.2.max",
  "tower.dangerLabels.3.min", "tower.dangerLabels.3.max",
  "tower.dangerLabels.4.min", "tower.dangerLabels.4.max",
  "towerOperations.weather.forecastWarningMinutes", "towerOperations.weather.defaultDurationMinutes",
  "fablab.recyclerMaxLevel", "fablab.cuisineUpgradeOrganic", "fablab.cuisineUpgradeMineral",
  "fablab.atelierUpgradeOrganic", "fablab.atelierUpgradeMineral",
  "fablab.recyclerUpgradeOrganic", "fablab.recyclerUpgradeMineral",
  "fablab.unitUpgradeDurationMinutes",
]);

let zone0Settings = {};

function cloneConfig(value) {
  return JSON.parse(JSON.stringify(value));
}

function mergeConfig(base, override) {
  if (Array.isArray(base)) {
    return Array.isArray(override)
      ? base.map((item, index) => mergeConfig(item, override[index]))
      : cloneConfig(base);
  }
  if (base && typeof base === "object") {
    const source = override && typeof override === "object" ? override : {};
    return Object.fromEntries(Object.entries(base).map(([key, value]) => [key, mergeConfig(value, source[key])]));
  }
  return override === undefined || override === null ? base : override;
}

async function loadZone0Settings() {
  try {
    const entries = await Promise.all(Object.entries(ZONE0_SECTION_SOURCES).map(async ([key, file]) => {
      const response = await fetch(`./${file}`, { cache: "no-store" });
      if (!response.ok) throw new Error(`${file}: HTTP ${response.status}`);
      return [key, await response.json()];
    }));
    const base = Object.fromEntries(entries);
    let published = null;
    if (auth.currentUser && currentDashboardRole) {
      const snapshot = await getDoc(doc(db, "gameConfigs", "zone0"));
      const candidate = snapshot.data()?.zone0Settings;
      if (candidate && typeof candidate === "object" && !Array.isArray(candidate)) published = candidate;
    }
    zone0Settings = mergeConfig(base, published || {});
    if (Array.isArray(published?.craft?.recipes)) {
      const baselineById = new Map((base.craft?.recipes || []).map((recipe) => [recipe.id, recipe]));
      zone0Settings.craft.recipes = published.craft.recipes.map((recipe) => mergeConfig(baselineById.get(recipe.id) || {}, recipe));
    }
    renderZone0Settings();
    el.zone0SettingsStatus.textContent = published
      ? "Configuration publiée chargée depuis Firestore."
      : "Valeurs versionnées chargées. Publie-les pour les appliquer à l'application.";
    el.craftStatus.textContent = published?.craft
      ? "Recettes publiées chargées depuis Firestore."
      : "Recettes versionnées chargées. Publie-les pour les appliquer à l'application.";
  } catch (error) {
    el.zone0SettingsStatus.textContent = `Configuration Zone 0 illisible: ${error.message}`;
  }
}

function readPath(source, path) {
  return path.reduce((value, key) => value?.[key], source);
}

function writePath(source, path, value) {
  let target = source;
  path.slice(0, -1).forEach((key) => { target = target[key]; });
  target[path[path.length - 1]] = value;
}

function prettyPath(path) {
  return path.map((key) => String(key).replace(/([A-Z])/g, " $1")).join(" / ");
}

function configFields(value, path = []) {
  if (typeof value === "number" || typeof value === "boolean") return [{ path, value }];
  if (!value || typeof value !== "object") return [];
  return Object.entries(value).flatMap(([key, child]) => configFields(child, [...path, key]));
}

function configFieldControls(key, value, prefix = []) {
  return configFields(value, prefix)
    .filter((field) => !ZONE0_NON_RUNTIME_PATHS.has(`${key}.${field.path.join(".")}`))
    .map((field) => {
      const path = field.path.join(".");
      const label = prettyPath(field.path.slice(prefix.length));
      if (typeof field.value === "boolean") {
        return `<label class="toggle-field"><input type="checkbox" data-zone0-key="${key}" data-zone0-path="${escapeHtml(path)}" ${field.value ? "checked" : ""}>${escapeHtml(label)}</label>`;
      }
      return `<div class="stat-field"><label for="zone0-${escapeHtml(key)}-${escapeHtml(path)}">${escapeHtml(label)}</label><input id="zone0-${escapeHtml(key)}-${escapeHtml(path)}" type="number" step="0.01" data-zone0-key="${key}" data-zone0-path="${escapeHtml(path)}" value="${escapeHtml(field.value)}"></div>`;
    }).join("");
}

function configCard(title, key, value, prefix = [], { open = false, meta = "" } = {}) {
  return `<details class="config-card" ${open ? "open" : ""}><summary><span><strong>${escapeHtml(title)}</strong><small>${escapeHtml(meta)}</small></span><span class="card-chevron">⌄</span></summary><div class="stat-form config-card-body">${configFieldControls(key, value, prefix)}</div></details>`;
}

function bindZone0Inputs(target) {
  target.querySelectorAll("[data-zone0-key]").forEach((input) => {
    input.addEventListener("input", () => {
      const path = input.dataset.zone0Path.split(".").map((key) => /^\d+$/.test(key) ? Number(key) : key);
      const value = input.type === "checkbox" ? input.checked : Number(input.value);
      writePath(zone0Settings[input.dataset.zone0Key], path, value);
      el.zone0SettingsStatus.textContent = "Modifications en attente. Clique sur Publier dans l'application.";
    });
  });
}

function renderConfigEditor(target, keys) {
  target.innerHTML = keys.map((key) => configCard(ZONE0_SECTION_LABELS[key], key, zone0Settings[key], [], { open: true })).join("");
  bindZone0Inputs(target);
}

function renderCampHeartEditor() {
  const stages = zone0Settings.campHeart?.stages || [];
  el.campHeartStageList.innerHTML = stages.map((stage, index) => configCard(
    `Niveau ${stage.level} · ${stage.label}`,
    "campHeart",
    stage,
    ["stages", index],
    { open: index === 0, meta: `Palier ${stage.stage || "Cœur"}` },
  )).join("");
  bindZone0Inputs(el.campHeartStageList);
}

function renderLisiereEditor() {
  const { biomes = [], durations = [], intensities = [], ...general } = zone0Settings.lisiere || {};
  el.lisiereForageList.innerHTML = [
    configCard("Réglages généraux", "lisiere", general, [], { open: true, meta: "Temps, inventaire et sécurité" }),
    configCard("Durées de mission", "lisiere", durations, ["durations"], { meta: "Durées et coût de vitalité" }),
    configCard("Intensités", "lisiere", intensities, ["intensities"], { meta: "Gains, fatigue et risque" }),
    ...biomes.map((biome, index) => configCard(biome.label || `Biome ${index + 1}`, "lisiere", biome, ["biomes", index], { meta: "Récompenses et risque" })),
  ].join("");
  bindZone0Inputs(el.lisiereForageList);
}

function renderWorkshopEditor() {
  const { recipes: _legacyRecipes, ...general } = zone0Settings.workshop || {};
  el.zone0SettingsForm.innerHTML = [
    configCard("Atelier · réglages généraux", "workshop", general, [], { open: true, meta: "Emplacements, vitalité et vitesse" }),
    configCard("Maison et logements", "housing", zone0Settings.housing, [], { meta: "Capacité, coûts et bien-être" }),
  ].join("");
  bindZone0Inputs(el.zone0SettingsForm);
}

function renderMarketEditor() {
  const market = zone0Settings.market || {};
  const construction = Object.fromEntries(["constructionCost", "requiredCampHeartLevel", "requiredPopulation", "saleSlotsPerLevel"].map((key) => [key, market[key]]));
  const { constructionCost, requiredCampHeartLevel, requiredPopulation, saleSlotsPerLevel, saleValues, ...activity } = market;
  el.marketSettingsForm.innerHTML = [
    configCard("Construction et prérequis", "market", construction, [], { open: true, meta: "Accès au bâtiment et emplacements" }),
    configCard("Activité du marché", "market", activity, [], { meta: "Vitalité, fréquence et demandes" }),
    configCard("Tarifs des ressources et objets", "market", saleValues || {}, ["saleValues"], { meta: "Prix par matériau et objet fabriqué" }),
  ].join("");
  bindZone0Inputs(el.marketSettingsForm);
}

function renderZone0Settings() {
  renderCampHeartEditor();
  renderLisiereEditor();
  renderConfigEditor(el.securityTowerConfigList, ["tower", "towerOperations"]);
  renderConfigEditor(el.fablabConfigList, ["fablab"]);
  renderWorkshopEditor();
  renderCraftConfig();
  renderMarketEditor();
}

function validateZone0Settings() {
  const invalid = configFields(zone0Settings).find(({ path, value }) => {
    if (typeof value !== "number" || !Number.isFinite(value)) return true;
    return value < 0 && !path.includes("riskModifierPercent");
  });
  if (invalid) throw new Error(`Valeur invalide pour ${prettyPath(invalid.path)}.`);
}

async function publishZone0Settings() {
  if (!auth.currentUser || !currentDashboardRole) throw new Error("Connexion admin ou dev requise.");
  validateZone0Settings();
  await setDoc(doc(db, "gameConfigs", "zone0"), {
    schemaVersion: 2,
    zone0Settings,
    zone0SettingsUpdatedAt: serverTimestamp(),
    zone0SettingsUpdatedBy: auth.currentUser.uid,
  }, { merge: true });
  el.zone0SettingsStatus.textContent = "Configuration publiée. Les applications connectées se mettent à jour.";
  el.craftStatus.textContent = "Configuration Craft publiée. Les applications connectées se mettent à jour.";
  el.marketSettingsStatus.textContent = "Configuration publiée. Les applications connectées se mettent à jour.";
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
      loadPtipoteStatsConfig();
      loadZone0Settings();
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

el.resetPtipoteStatsButton.addEventListener("click", () => {
  loadPtipoteStatsConfig();
});

el.exportPtipoteStatsButton.addEventListener("click", () => {
  publishPtipoteStatsConfig().catch((error) => {
    el.statPtipoteStatus.textContent = `Publication impossible: ${readableFirebaseError(error)}`;
  });
});

el.exportKernelButton.addEventListener("click", () => {
  exportKernelConfig();
});

[
  el.publishCampHeartButton,
  el.publishLisiereForageButton,
  el.publishSecurityTowerButton,
  el.publishFablabButton,
  el.publishZone0SettingsButton,
  el.publishCraftButton,
  el.publishMarketButton,
].forEach((button) => {
  button.addEventListener("click", () => {
    publishZone0Settings().catch((error) => {
      el.zone0SettingsStatus.textContent = `Publication impossible: ${readableFirebaseError(error)}`;
      el.craftStatus.textContent = `Publication impossible: ${readableFirebaseError(error)}`;
      el.marketSettingsStatus.textContent = `Publication impossible: ${readableFirebaseError(error)}`;
    });
  });
});

el.craftRecipeForm.addEventListener("submit", addCraftRecipe);

async function loadKernelProgressConfig() {
  const response = await fetch("./kernel-progress-config.json", { cache: "no-store" });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  el.kernelProgressEditor.value = JSON.stringify(await response.json(), null, 2);
}

function exportEditor(editor, filename) {
  const parsed = JSON.parse(editor.value);
  downloadJson(filename, parsed);
}

function downloadJson(filename, value) {
  const blob = new Blob([JSON.stringify(value, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}

el.exportRecyclerButton.addEventListener("click", () => exportRecyclerConfig());
el.exportKernelProgressButton.addEventListener("click", () => exportEditor(el.kernelProgressEditor, "kernel-progress-config.json"));

setupDashboardTabs();
loadPtipoteStatsConfig();
loadKernelConfig();
loadCampHeartConfig();
loadLisiereForageConfig();
loadSecurityTowerConfig();
loadFablabConfig();
loadRecyclerConfig();
loadZone0Settings();
loadKernelProgressConfig().catch((error) => {
  el.kernelStatus.textContent = `Configuration progression Kernel illisible: ${error.message}`;
});
