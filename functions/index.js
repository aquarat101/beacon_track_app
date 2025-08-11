const functions = require("firebase-functions");
const admin = require("firebase-admin");
const axios = require("axios");

admin.initializeApp();

const lineAccessToken = "Q1Hf6RcYV0zyQJoDBdypq3P2WF+e86v39uA5TxZb9fmGgKWhERwaP5H4b/2Ilr87LLgOy4hVle0xH8WZWBlYr0HFAd73cFN5pvESyhQvyjy2gLWQUvkhbB0RCyJhMF88U1iulZH4QUllbwsfbcOwUQdB04t89/1O/w1cDnyilFU=";
const momUserId = "Ua447dc04887c78d85ddcdcc630a4ad2a"; // LINE user ID แม่ที่จะแจ้งเตือน

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

        const message = `Piyo! Child's registration is complete! 🎉\nKid 2 has been successfully registered in our system with ID: 3021`;
        const mes2 = `Piyo! Child's registration is complete! 🎉\nKid 2 has been successfully registered in our system with ID: 2031`;
        const mes3 = `Piyo! Child's registration is complete! 🎉\nKid 3 has been successfully registered in our system with ID: 3013`;
        const mes4 = `Piyo! Piyo!\nKid1 has successfully reached school at 10:41AM.`;
        const mes5 = `Piyo! Piyo!\nKid2 has successfully reached school at 10:47AM.`;
        const mes6 = `Piyo! Piyo!\nKid3 has successfully reached school at 10:54AM.`;

        // ส่งข้อความผ่าน LINE Messaging API
        try {
            await Promise.all([
                axios.post("https://api.line.me/v2/bot/message/push", {
                    to: momUserId,
                    messages: [
                        { type: "text", text: message },
                        { type: "text", text: mes2 },
                        { type: "text", text: mes3 },
                        { type: "text", text: mes4 },
                        { type: "text", text: mes5 }
                    ],
                }, { headers: { Authorization: `Bearer ${lineAccessToken}`, "Content-Type": "application/json" } }),

                axios.post("https://api.line.me/v2/bot/message/push", {
                    to: momUserId,
                    messages: [
                        { type: "text", text: mes6 }
                    ],
                }, { headers: { Authorization: `Bearer ${lineAccessToken}`, "Content-Type": "application/json" } })
            ]);


            console.log("ส่ง LINE แจ้งเตือนสำเร็จ");
        } catch (error) {
            console.error("ส่ง LINE แจ้งเตือนล้มเหลว", error);
        }

        return null;
    });
