require('dotenv').config(); // ต้องเป็นบรรทัดแรกๆ
const express = require('express');
const admin = require('firebase-admin');
const bodyParser = require('body-parser');

// ตรวจสอบว่า Firebase Admin SDK ได้รับการเริ่มต้นแล้ว
if (!admin.apps.length) {
    const encodedKey = process.env.GOOGLE_APPLICATION_CREDENTIALS_ENCODED; // <--- ดึงค่าจาก .env
    if (!encodedKey) {
        throw new Error("GOOGLE_APPLICATION_CREDENTIALS_ENCODED environment variable is not set.");
    }
    const decodedKey = Buffer.from(encodedKey, 'base64').toString('utf8');
    admin.initializeApp({
        credential: admin.credential.cert(JSON.parse(decodedKey))
    });
}

const db = admin.firestore();
const app = express();

app.use(bodyParser.json());

app.get('/api/beacon-hit', async (req, res) => {
    try {
        const { beaconName, serial, zoneId, zoneName } = req.query;  

        const missingFields = [];
        if (!beaconName) missingFields.push('beaconName');
        if (!serial) missingFields.push('serial');
        if (!zoneId) missingFields.push('zoneId');
        if (!zoneName) missingFields.push('zoneName');

        if (missingFields.length > 0) {
            return res.status(400).json({
                success: false,
                message: 'Missing required fields.',
                missingFields
            });
        }

        let query = db.collection('beacon_zone_hits')
            .where('beaconName', '==', beaconName)
            .where('serial', '==', serial)
            .where('zoneId', '==', zoneId)
            .where('zoneName', '==', zoneName);

        const snapshot = await query.get();

        if (snapshot.empty) {
            return res.status(404).json({
                success: false,
                message: 'No matching documents found.'
            });
        }

        const results = [];
        snapshot.forEach(doc => {
            results.push({ id: doc.id, ...doc.data() });
        });

        res.status(200).json({
            success: true,
            count: results.length,
            data: results
        });

    } catch (error) {
        console.error('Error fetching beacon hits:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch beacon hits.',
            error: error.message
        });
    }
});


const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`API server is running on port ${PORT}`);
});