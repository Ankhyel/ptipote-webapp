const admin = require("firebase-admin");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");

admin.initializeApp();

exports.sendPushForNotification = onDocumentCreated(
  {
    document: "users/{userId}/notifications/{notificationId}",
    region: "europe-west9",
  },
  async (event) => {
    const userId = event.params.userId;
    const notification = event.data && event.data.data();

    if (!notification) return;
    const notificationRef = event.data.ref;

    const tokensSnapshot = await admin
      .firestore()
      .collection("users")
      .doc(userId)
      .collection("fcmTokens")
      .get();

    const tokens = tokensSnapshot.docs
      .map((doc) => `${doc.data().token || doc.id}`.trim())
      .filter(Boolean);

    if (tokens.length === 0) {
      await notificationRef.set(
        {
          pushStatus: "no_tokens",
          pushSuccessCount: 0,
          pushFailureCount: 0,
          pushErrors: [],
          pushCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      return;
    }

    const payload = {
      notification: {
        title: `${notification.title || "PTIPOTE"}`,
        body: `${notification.body || ""}`,
      },
      data: stringifyData({
        notificationId: event.params.notificationId,
        type: notification.type || "",
        ...(notification.data || {}),
      }),
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    };

    let response;
    try {
      response = await admin.messaging().sendEachForMulticast({
        tokens,
        ...payload,
      });
    } catch (error) {
      await notificationRef.set(
        {
          pushStatus: "error",
          pushFailureCount: tokens.length,
          pushErrors: [
            {
              code: error.code || "unknown",
              message: error.message || `${error}`,
            },
          ],
          pushCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      throw error;
    }
    const pushErrors = response.responses
      .filter((result) => !result.success)
      .slice(0, 5)
      .map((result) => ({
        code: (result.error && result.error.code) || "unknown",
        message: (result.error && result.error.message) || "",
      }));

    const batch = admin.firestore().batch();
    batch.set(
      notificationRef,
      {
        pushStatus: response.failureCount === 0 ? "sent" : "partial",
        pushSuccessCount: response.successCount,
        pushFailureCount: response.failureCount,
        pushErrors,
        pushCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    response.responses.forEach((result, index) => {
      if (result.success) return;
      const code = result.error && result.error.code;
      const shouldDelete =
        code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token";
      if (!shouldDelete) return;
      batch.delete(tokensSnapshot.docs[index].ref);
    });
    await batch.commit();
  },
);

// The game simulation is normally persisted by the app, but an iPhone that is
// closed cannot display an in-app warning. This server-side check turns the
// latest saved urgent needs into a notification document, which is then sent by
// the trigger above. Deterministic ids keep one push per need and per hour.
exports.notifySavedPtipoteNeeds = onSchedule(
  {schedule: "every 30 minutes", region: "europe-west9"},
  async () => {
    const games = await admin
      .firestore()
      .collectionGroup("game")
      .where(admin.firestore.FieldPath.documentId(), "==", "zone0")
      .get();
    const hour = new Date().toISOString().slice(0, 13).replace(/[-T:]/g, "");
    const writes = [];
    for (const game of games.docs) {
      const data = game.data();
      const userDoc = game.ref.parent.parent;
      if (!userDoc) continue;
      const uid = userDoc.id;
      const [figurines] = await Promise.all([
        userDoc.collection("figurines").get(),
      ]);
      const names = new Map(figurines.docs.map((doc) => [doc.id, `${doc.data().fields?.s || doc.data().displayName || "P’TIPOTE"}`]));
      const checks = [
        ["hungerOverrides", 20, "faim", "a faim et attend un repas."],
        ["restOverrides", 15, "repos", "a besoin de dormir."],
        ["vitalityOverrides", 10, "energie", "est épuisé et a besoin de repos."],
      ];
      for (const [field, threshold, type, sentence] of checks) {
        const values = data[field] || {};
        for (const [figurineId, value] of Object.entries(values)) {
          if (Number(value) > threshold) continue;
          const name = names.get(figurineId) || "Un P’TIPOTE";
          const ref = userDoc.collection("notifications").doc(`need-${figurineId}-${type}-${hour}`);
          writes.push(ref.create({
            recipientUid: uid,
            senderUid: "system",
            type: "ptipote_need",
            title: `${name} a besoin de toi`,
            body: `${name} ${sentence}`,
            read: false,
            data: {figurineId, needType: type, value: Number(value)},
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }).catch((error) => {
            if (error.code !== 6) throw error; // already notified this hour
          }));
      }
    }
    }
    await Promise.all(writes);
  },
);

function stringifyData(data) {
  return Object.fromEntries(
    Object.entries(data).map(([key, value]) => [key, `${value ?? ""}`]),
  );
}
