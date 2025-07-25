const functions = require("firebase-functions");
const admin = require("firebase-admin");
const axios = require("axios");

admin.initializeApp();

const lineAccessToken = "MVQEnXLZAPczQrtzkRBbf7N+CxCKTXkFr7/aKL76F/sGlGNds0LVYxsJ3jBp9lHS0wR4p+dO7HvuDOvJRPeemDknPMuWMaqxrMWDdSuZKLbjQg2z4lRfzcDtzi7kSk2tfcgseR7fcdHa8hWWSqzPDQdB04t89/1O/w1cDnyilFU";
const momUserId = "U6ac3e1babfa232e29f1b5a73deb99114"; // LINE user ID แม่ที่จะแจ้งเตือน

exports.notifyBeaconZoneHit = functions.firestore
    .document("beacon_zone_hits/{docId}")
    .onCreate(async (snap, context) => {
        const data = snap.data();

        if (!data) return null;

        const { beaconName, uuid, major, minor, zoneName, timestamp } = data;

        // เพิ่ม +7 ชั่วโมง
        const timestampMs = timestamp._seconds * 1000;
        const thaiTime = new Date(timestampMs + (7 * 60 * 60 * 1000)); // บวก 7 ชั่วโมง
        const formatted = thaiTime.toLocaleString("th-TH");

        const message = `⚠️ พบอุปกรณ์ Beacon: ${beaconName} \nอยู่ในโซน: ${zoneName} เวลา: ${formatted}`;

        // ส่งข้อความผ่าน LINE Messaging API
        try {
            await axios.post(
                "https://api.line.me/v2/bot/message/push",
                {
                    to: momUserId,
                    messages: [{ type: "text", text: message }],
                },
                {
                    headers: {
                        "Authorization": `Bearer ${lineAccessToken}`,
                        "Content-Type": "application/json",
                    },
                },
            );
            console.log("ส่ง LINE แจ้งเตือนสำเร็จ");
        } catch (error) {
            console.error("ส่ง LINE แจ้งเตือนล้มเหลว", error);
        }

        return null;
    });
