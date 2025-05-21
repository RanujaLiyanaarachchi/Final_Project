const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

const firestore = admin.firestore();
const messaging = admin.messaging();

// Function to send push notification when a new message is created
exports.sendMessageNotification = functions.firestore
    .document("messages/{messageId}")
    .onCreate(async (snapshot, context) => {
      try {
        const messageData = snapshot.data();
        const messageId = context.params.messageId;

        // Make sure we have required data
        if (!messageData.customerId) {
          console.log(`Message ${messageId} has no customerId, skipping notification`);
          return null;
        }

        // Get customer data to find FCM token
        const customerIdStr = messageData.customerId.toString();
        const fcmTokens = [];

        // Try to get token from identity collection
        if (messageData.customerNic) {
          const nicStr = messageData.customerNic.toString();
          const safeNic = nicStr.replace("/", "_").replace(".", "_");

          const identityDoc = await firestore.collection("identity").doc(safeNic).get();
          if (identityDoc.exists) {
            const identityData = identityDoc.data();
            if (identityData.fcmToken) {
              fcmTokens.push(identityData.fcmToken);
            }
          }
        }

        // If no tokens found via identity, try using topics
        if (fcmTokens.length === 0) {
          console.log(`Sending to customer_${customerIdStr} topic instead`);
          // We'll send to topic instead
        }

        // Prepare notification content
        const title = messageData.heading || "New Message";
        const body = messageData.message || "";

        // Check if message has attachments
        const hasAttachments = messageData.attachments &&
                                  messageData.attachments.length > 0;

        // Create message payload
        const payload = {
          notification: {
            title: hasAttachments ? `{title}` : title,
            body: body,
            sound: "default",
            badge: "1",
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          },
          data: {
            messageId: messageId,
            customerId: customerIdStr,
            title: hasAttachments ? `📎 ${title}` : title,
            body: body,
            type: "message",
          },
        };

        // Send via tokens if available
        const results = [];
        if (fcmTokens.length > 0) {
          console.log(`Sending notification to ${fcmTokens.length} tokens`);
          const tokensMessage = {
            tokens: fcmTokens,
            notification: payload.notification,
            data: payload.data,
            android: {
              priority: "high",
              notification: {
                sound: "default",
                priority: "high",
                channelId: "high_importance_channel",
              },
            },
            apns: {
              payload: {
                aps: {
                  sound: "default",
                  badge: 1,
                  contentAvailable: true,
                },
              },
            },
          };

          results.push(await messaging.sendMulticast(tokensMessage));
        }

        // Also send as topic message to ensure delivery
        const topicMessage = {
          topic: `customer_${customerIdStr}`,
          notification: payload.notification,
          data: payload.data,
          android: {
            priority: "high",
            notification: {
              sound: "default",
              priority: "high",
              channelId: "high_importance_channel",
            },
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
                badge: 1,
                contentAvailable: true,
              },
            },
          },
        };

        results.push(await messaging.send(topicMessage));

        console.log(`Successfully sent message: ${JSON.stringify(results)}`);
        return results;
      } catch (error) {
        console.error("Error sending notification:", error);
        return null;
      }
    });

// Function to clean up messages that are older than 30 days
exports.cleanupOldMessages = functions.pubsub
    .schedule("0 0 * * *") // Every day at midnight
    .timeZone("UTC")
    .onRun(async (context) => {
      const thirtyDaysAgo = new Date();
      thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

      const oldMessagesQuery = await firestore.collection("messages")
          .where("createdAt", "<", thirtyDaysAgo)
          .get();

      const batch = firestore.batch();
      let count = 0;

      oldMessagesQuery.forEach((doc) => {
        batch.delete(doc.ref);
        count++;
      });

      if (count > 0) {
        await batch.commit();
        console.log(`Deleted ${count} old messages`);
      } else {
        console.log("No old messages to delete");
      }

      return null;
    });

// Function to mark a message as read when opened
exports.markMessageAsRead = functions.https.onCall(async (data, context) => {
  // Ensure user is authenticated if needed
  // if (!context.auth) {
  //     throw new functions.https.HttpsError(
  //         'unauthenticated',
  //         'You must be signed in to mark messages as read'
  //     );
  // }

  const {messageId} = data;

  if (!messageId) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "Message ID is required",
    );
  }

  try {
    await firestore
        .collection("messages")
        .doc(messageId)
        .update({
          isRead: true,
          readAt: admin.firestore.FieldValue.serverTimestamp(),
        });

    return {success: true};
  } catch (error) {
    console.error("Error marking message as read:", error);
    throw new functions.https.HttpsError(
        "internal",
        "Error marking message as read",
    );
  }
});

// Function to delete a message
exports.deleteMessage = functions.https.onCall(async (data, context) => {
  // Ensure user is authenticated if needed
  // if (!context.auth) {
  //     throw new functions.https.HttpsError(
  //         'unauthenticated',
  //         'You must be signed in to delete messages'
  //     );
  // }

  const {messageId} = data;

  if (!messageId) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "Message ID is required",
    );
  }

  try {
    await firestore
        .collection("messages")
        .doc(messageId)
        .delete();

    return {success: true};
  } catch (error) {
    console.error("Error deleting message:", error);
    throw new functions.https.HttpsError(
        "internal",
        "Error deleting message",
    );
  }
});

// Function to update FCM token
exports.updateFcmToken = functions.https.onCall(async (data, context) => {
  const {nic, customerId, fcmToken} = data;

  if (!nic || !fcmToken) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "NIC and FCM token are required",
    );
  }

  try {
    const safeNic = nic.replace("/", "_").replace(".", "_");

    await firestore.collection("identity").doc(safeNic).set({
      nic: nic,
      customerId: customerId || "",
      fcmToken: fcmToken,
      platform: data.platform || "unknown",
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      active: true,
    }, {merge: true});

    return {success: true};
  } catch (error) {
    console.error("Error updating FCM token:", error);
    throw new functions.https.HttpsError(
        "internal",
        "Error updating FCM token",
    );
  }
});
