const admin = require("firebase-admin");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");

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

function stringifyData(data) {
  return Object.fromEntries(
    Object.entries(data).map(([key, value]) => [key, `${value ?? ""}`]),
  );
}
