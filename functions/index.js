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

        const { beaconName, beaconId, uuid, major, minor, zoneName, timestamp } = data;

        // เพิ่ม +7 ชั่วโมง
        const timestampMs = timestamp._seconds * 1000;
        const thaiTime = new Date(timestampMs + (7 * 60 * 60 * 1000)); // บวก 7 ชั่วโมง

        const dateOptions = { year: 'numeric', month: 'numeric', day: 'numeric' };
        const dateFormatted = thaiTime.toLocaleDateString("th-TH", dateOptions);

        const timeOptions = { hour: 'numeric', minute: 'numeric', hour12: true };
        const timeFormatted = thaiTime.toLocaleTimeString('en-US', timeOptions);

        // const message = `Piyo! Piyo!\nKid1 has successfully reached school at ${timeFormatted}`;
        // const message = `Piyo! Child's registration is complete! 🎉\nKid 2 has been successfully registered in our system with ID: 3021`;
        // const mes2 = `Piyo! Child's registration is complete! 🎉\nKid 2 has been successfully registered in our system with ID: 2031`;
        // const mes3 = `Piyo! Child's registration is complete! 🎉\nKid 3 has been successfully registered in our system with ID: 3013`;
        // const mes4 = `Piyo! Piyo!\nKid1 has successfully reached school at 10:41AM.`;
        // const mes5 = `Piyo! Piyo!\nKid2 has successfully reached school at 10:47AM.`;
        // const mes6 = `Piyo! Piyo!\nKid3 has successfully reached school at 10:54AM.`;

        // ส่งข้อความผ่าน LINE Messaging API
        try {
            // ดึงข้อมูลเด็กจาก collection 'kids' ตาม beacon uuid
            const kidSnap = await admin.firestore().collection('kids')
                .where('beaconId', '==', beaconId)
                .get();

            if (kidSnap.empty) {
                console.log('ไม่พบเด็กที่ตรงกับ beacon uuid นี้');
                return null;
            }

            const promises = [];

            kidSnap.forEach(doc => {
                const kidData = doc.data();
                const kidName = kidData.name;
                const parentId = kidData.userId; // ถ้าคุณเก็บ userId ของแม่ไว้ใน doc

                const message = `Piyo! Piyo!\n${kidName} has successfully reached at ${dateFormatted} ${timeFormatted}`;

                promises.push(
                    axios.post("https://api.line.me/v2/bot/message/push", {
                        to: parentId,
                        messages: [{ type: "text", text: message }]
                    }, {
                        headers: { Authorization: `Bearer ${lineAccessToken}`, "Content-Type": "application/json" }
                    })
                );

                console.log("ส่ง LINE แจ้งเตือนสำเร็จ");
            });

            await Promise.all(promises);
            console.log("ส่ง LINE แจ้งเตือนครบทุก user แล้ว");

            // await Promise.all([
            //     axios.post("https://api.line.me/v2/bot/message/push", {
            //         to: momUserId,
            //         messages: [
            //             { type: "text", text: message },
            //             { type: "text", text: mes2 },
            //             { type: "text", text: mes3 },
            //             { type: "text", text: mes4 },
            //             { type: "text", text: mes5 }
            //         ],
            //     }, { headers: { Authorization: `Bearer ${lineAccessToken}`, "Content-Type": "application/json" } }),

            //     axios.post("https://api.line.me/v2/bot/message/push", {
            //         to: momUserId,
            //         messages: [
            //             { type: "text", text: mes6 }
            //         ],
            //     }, { headers: { Authorization: `Bearer ${lineAccessToken}`, "Content-Type": "application/json" } })
            // ]);


        } catch (error) {
            console.error("ส่ง LINE แจ้งเตือนล้มเหลว", error);
        }

        return null;
    });
