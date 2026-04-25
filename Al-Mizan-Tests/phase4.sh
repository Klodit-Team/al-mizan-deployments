#!/bin/bash

# --- Configuration ---
API_URL="https://api.klodit.app/api/v1"
LOCAL_JAVA_URL="http://localhost:8004/api/v1"
LOCAL_COMMISSION_URL="http://localhost:8007/api/v1"
RESULTS_DIR="results"
COOKIE_CONTRACTANT="$RESULTS_DIR/cookie_contractant.txt"
mkdir -p $RESULTS_DIR

AO_ID="df3dbfef-6946-46f5-9821-60c5aad44932"
CURRENT_SHORT_DATE=$(date -u +"%Y-%m-%d")
CURRENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "=================================================="
echo "🚀 STARTING PHASE 4: OPENING SESSIONS & DECRYPTION"
echo "=================================================="

# 0. Get the latest Submission ID
RAW_SUB_ID=$(sudo docker exec al-mizan-mysql mysql -uroot -ppassword -sN -D soumission_db -e "SELECT id FROM soumissions ORDER BY created_at DESC LIMIT 1;" 2>/dev/null)
SUB_ID=$(echo "$RAW_SUB_ID" | tr -d '\r')

if [ -z "$SUB_ID" ] || [ "$SUB_ID" == "null" ]; then
  echo "❌ Could not fetch Submission ID from database!"
  exit 1
fi
echo "✅ Submission ID to decrypt: $SUB_ID"

# ---------------------------------------------------------
# 0.5 SANITIZE DATABASE (Kill the ghosts!)
# ---------------------------------------------------------
echo -e "\n[0/8] 🧹 Cleaning up corrupted test submissions from DB..."
sudo docker exec al-mizan-mysql mysql -uroot -ppassword -e "
USE soumission_db;
SET FOREIGN_KEY_CHECKS=0;
DELETE FROM offres_financieres WHERE soumission_id != '$SUB_ID';
SET FOREIGN_KEY_CHECKS=1;
" > /dev/null 2>&1
echo "✅ Ghosts busted. Only pristine submission remains."

# ---------------------------------------------------------
# 1. RE-AUTHENTICATE CONTRACTANT
# ---------------------------------------------------------
TOKEN_CONTRACTANT=$(grep 'access_token' $COOKIE_CONTRACTANT | awk '{print $7}')
USER_ID_CONTRACTANT=$(jq -r '.user.userId // empty' $RESULTS_DIR/p3_1_login.json)

if [ -z "$TOKEN_CONTRACTANT" ] || [ -z "$USER_ID_CONTRACTANT" ]; then
  echo "❌ Contractant Token missing! Did you run Phase 3?"
  exit 1
fi
echo "✅ Contractant Ready! ID: $USER_ID_CONTRACTANT"

# ---------------------------------------------------------
# 2. FIX THE ENCRYPTION ENVELOPE (DEV CONTROLLER)
# ---------------------------------------------------------
echo -e "\n[1/8] 🛠️ Fixing Cryptography Envelope via Java Dev Endpoint..."
curl -s -X POST "$LOCAL_JAVA_URL/dev/generer-offre-chiffree/$SUB_ID" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN" \
  -H "Content-Type: application/json" \
  -o $RESULTS_DIR/p4_1_fix_crypto.json

FIX_SUCCESS=$(jq -r '.success // empty' $RESULTS_DIR/p4_1_fix_crypto.json)
if [ "$FIX_SUCCESS" != "true" ]; then
  echo "❌ Failed to generate real encryption envelope!"
  cat $RESULTS_DIR/p4_1_fix_crypto.json | jq
  exit 1
fi
echo "✅ Valid AES-GCM Envelope uploaded to MinIO!"

# ---------------------------------------------------------
# 3. CREATE EVALUATION COMMISSION
# ---------------------------------------------------------
echo -e "\n[2/8] 🏛️ Creating Evaluation Commission..."
curl -s -X POST "$LOCAL_COMMISSION_URL/commissions-evaluation" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN,SERVICE_CONTRACTANT" \
  -H "Content-Type: application/json" \
  -d "{
    \"objet\": \"Commission d'Ouverture et d'Evaluation des Plis\",
    \"dateCreation\": \"$CURRENT_SHORT_DATE\",
    \"presidentId\": \"$USER_ID_CONTRACTANT\"
  }" -o $RESULTS_DIR/p4_2_create_commission.json

COMMISSION_ID=$(jq -r '.id // empty' $RESULTS_DIR/p4_2_create_commission.json)
echo "✅ Commission Created! ID: $COMMISSION_ID"

# ---------------------------------------------------------
# 4. CREATE OPENING SESSION
# ---------------------------------------------------------
echo -e "\n[3/8] 📅 Creating Opening Session..."
curl -s -X POST "$LOCAL_COMMISSION_URL/seances-ouverture" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN,SERVICE_CONTRACTANT" \
  -H "Content-Type: application/json" \
  -d "{
    \"appelOffreId\": \"$AO_ID\",
    \"commissionId\": \"$COMMISSION_ID\",
    \"type\": \"OFFRE_FINANCIERE\",
    \"dateSeance\": \"$CURRENT_DATE\",
    \"lieu\": \"Salle A - Ministère\",
    \"isPublique\": true
  }" -o $RESULTS_DIR/p4_3_create_seance.json

SEANCE_ID=$(jq -r '.id // empty' $RESULTS_DIR/p4_3_create_seance.json)
echo "✅ Seance Created! ID: $SEANCE_ID"

# ---------------------------------------------------------
# 5. START OPENING SESSION
# ---------------------------------------------------------
echo -e "\n[4/8] ▶️ Starting the Session..."
curl -s -X PATCH "$LOCAL_COMMISSION_URL/seances-ouverture/$SEANCE_ID/demarrer" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN,SERVICE_CONTRACTANT" \
  -H "Content-Type: application/json" \
  -o $RESULTS_DIR/p4_4_start_seance.json
echo "✅ Session Started!"

# ---------------------------------------------------------
# 6. EXTRACT SHAMIR FRAGMENTS
# ---------------------------------------------------------
echo -e "\n[5/8] 🕵️ Extracting 3 Shamir Fragments from Database..."
RAW_FRAGMENTS=$(sudo docker exec al-mizan-mysql mysql -uroot -ppassword -sN -D soumission_db -e "
SELECT CONCAT('{\"index\":', fragment_index, ',\"valeur\":\"', fragment_chiffre, '\",\"membreId\":\"', membre_commission_id, '\"}')
FROM fragments_cle
WHERE cle_chiffrement_id = (SELECT id FROM cles_chiffrement WHERE appel_offre_id = '$AO_ID' LIMIT 1)
LIMIT 3;" 2>/dev/null | paste -sd "," -)

FRAGMENTS_JSON=$(echo "$RAW_FRAGMENTS" | tr -d '\r')
DECRYPT_PAYLOAD="{\"fragments\": [$FRAGMENTS_JSON]}"
echo "✅ 3 Fragments extracted!"

# ---------------------------------------------------------
# 7. DECRYPT FINANCIAL OFFERS
# ---------------------------------------------------------
echo -e "\n[6/8] 🔓 Decrypting Financial Offers..."
curl -s -X POST "$LOCAL_JAVA_URL/offres-financieres/dechiffrer/$AO_ID" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN,SERVICE_CONTRACTANT,MEMBRE_COMMISSION" \
  -H "Content-Type: application/json" \
  -d "$DECRYPT_PAYLOAD" \
  -o $RESULTS_DIR/p4_6_decrypt.json

DECRYPT_SUCCESS=$(jq -r '.success // empty' $RESULTS_DIR/p4_6_decrypt.json)
if [ "$DECRYPT_SUCCESS" != "true" ]; then
  echo "❌ Decryption Failed! Response:"
  cat $RESULTS_DIR/p4_6_decrypt.json | jq
  exit 1
fi
echo "✅ Offers Decrypted Successfully!"

# ---------------------------------------------------------
# 8. RECORD RESULTS & CLOSE SESSION
# ---------------------------------------------------------
echo -e "\n[7/8] 📝 Recording Results and Closing Session..."
curl -s -X POST "$LOCAL_COMMISSION_URL/seances-ouverture/$SEANCE_ID/resultats" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN,SERVICE_CONTRACTANT" \
  -H "Content-Type: application/json" \
  -d "{
    \"soumissionId\": \"$SUB_ID\",
    \"pliRecu\": true,
    \"pliConforme\": true,
    \"observations\": \"Déchiffrement réussi et transparent\"
  }" > /dev/null

curl -s -X PATCH "$LOCAL_COMMISSION_URL/seances-ouverture/$SEANCE_ID/terminer" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN,SERVICE_CONTRACTANT" \
  -H "Content-Type: application/json" \
  -o $RESULTS_DIR/p4_7_close_seance.json
echo "✅ Session Closed!"

# ---------------------------------------------------------
# 9. GENERATE OFFICIAL PV (PDF)
# ---------------------------------------------------------
echo -e "\n[8/8] 📄 Generating Official PV PDF..."
curl -s -X POST "$LOCAL_COMMISSION_URL/seances-ouverture/$SEANCE_ID/pv" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN,SERVICE_CONTRACTANT" \
  -H "Content-Type: application/json" \
  -o $RESULTS_DIR/p4_8_generate_pv.json

PV_URL=$(jq -r '.url // empty' $RESULTS_DIR/p4_8_generate_pv.json)
if [ -z "$PV_URL" ] || [ "$PV_URL" == "null" ]; then
  echo "❌ PV Generation Failed! Error:"
  cat $RESULTS_DIR/p4_8_generate_pv.json | jq
  exit 1
fi

echo "✅ PV Generated and Uploaded to MinIO! URL: $PV_URL"
echo -e "\n🎉 PHASE 4 COMPLETE!"
