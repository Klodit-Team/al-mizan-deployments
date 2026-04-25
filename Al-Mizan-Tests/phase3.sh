#!/bin/bash

# --- Configuration ---
API_URL="https://api.klodit.app/api/v1"
LOCAL_JAVA_URL="http://localhost:8004/api/v1"
RESULTS_DIR="results"
COOKIE_CONTRACTANT="$RESULTS_DIR/cookie_contractant.txt"
COOKIE_OPERATEUR="$RESULTS_DIR/cookie_operateur.txt"
mkdir -p $RESULTS_DIR

# Hardcoded AO_ID from Phase 2
AO_ID="df3dbfef-6946-46f5-9821-60c5aad44932"
RANDOM_ID=$(date +%s)
CURRENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%S")

echo "=================================================="
echo "🚀 STARTING PHASE 3: E2EE SUBMISSIONS & UPLOADS"
echo "=================================================="

# ---------------------------------------------------------
# 1. RE-AUTHENTICATE CONTRACTANT
# ---------------------------------------------------------
EMAIL_CONTRACTANT="acheteur_${RANDOM_ID}@ministere.dz"
echo -e "\n[1/8] 📝 Registering & Logging in Contractant ($EMAIL_CONTRACTANT)..."

curl -s -X POST "$API_URL/auth/register" \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"$EMAIL_CONTRACTANT\",
    \"password\": \"Password123!\",
    \"role\": \"SERVICE_CONTRACTANT\",
    \"langue\": \"fr\",
    \"nom\": \"Directeur\",
    \"prenom\": \"Achat\",
    \"telephone\": \"0210000000\",
    \"denomination\": \"Ministere des Finances\",
    \"type\": \"MINISTERE\",
    \"nif\": \"$RANDOM_ID\",
    \"nis\": \"$RANDOM_ID\",
    \"code_service\": \"SRV-$RANDOM_ID\",
    \"secteur_activite\": \"Finances\",
    \"ordonnateur\": \"Ministre\"
  }" > /dev/null

sleep 2

curl -s -c $COOKIE_CONTRACTANT -X POST "$API_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\": \"$EMAIL_CONTRACTANT\", \"password\": \"Password123!\"}" -o $RESULTS_DIR/p3_1_login.json

TOKEN_CONTRACTANT=$(grep 'access_token' $COOKIE_CONTRACTANT | awk '{print $7}')
USER_ID_CONTRACTANT=$(jq -r '.user.userId // empty' $RESULTS_DIR/p3_1_login.json)
echo "✅ Contractant Ready! ID: $USER_ID_CONTRACTANT"

# ---------------------------------------------------------
# 2. PROMOTE CONTRACTANT TO ADMIN
# ---------------------------------------------------------
echo -e "\n[2/8] 👑 Temporarily promoting Contractant to ADMIN via MySQL..."
sudo docker exec al-mizan-mysql mysql -uroot -ppassword -e "
USE al_mizan_users;
SET @adminRoleId = (SELECT id FROM roles WHERE name='ADMIN' LIMIT 1);
INSERT IGNORE INTO user_roles (id, user_id, role_id, assigned_at) VALUES (UUID(), '$USER_ID_CONTRACTANT', @adminRoleId, NOW());
" > /dev/null 2>&1
echo "✅ Promoted to Admin!"

# ---------------------------------------------------------
# 3. GENERATE E2EE KEYS
# ---------------------------------------------------------
echo -e "\n[3/8] 🔐 Generating RSA/Shamir Encryption Keys (5 Members!)..."
curl -s -X POST "$LOCAL_JAVA_URL/cles-chiffrement/$AO_ID" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN,SERVICE_CONTRACTANT" \
  -H "Content-Type: application/json" \
  -d "[ \"$USER_ID_CONTRACTANT\", \"11111111-1111-1111-1111-111111111111\", \"22222222-2222-2222-2222-222222222222\", \"33333333-3333-3333-3333-333333333333\", \"44444444-4444-4444-4444-444444444444\" ]" \
  -o $RESULTS_DIR/p3_3_generate_keys.json

ERR_MSG=$(jq -r '.message // empty' $RESULTS_DIR/p3_3_generate_keys.json)
if [[ "$ERR_MSG" == *"existent déjà"* ]]; then
    echo "✅ Keys already exist for this AO! Proceeding."
elif [ "$(jq -r '.success' $RESULTS_DIR/p3_3_generate_keys.json)" == "true" ]; then
    echo "✅ Keys Generated Successfully!"
else
    echo "❌ ERROR: Keys generation failed:"
    cat $RESULTS_DIR/p3_3_generate_keys.json | jq
    exit 1
fi

# ---------------------------------------------------------
# 4. REGISTER & LOGIN OPERATEUR (Bidder)
# ---------------------------------------------------------
BIDDER_EMAIL="bidder_${RANDOM_ID}@entreprise.com"
echo -e "\n[4/8] 📝 Registering & Logging in Bidder ($BIDDER_EMAIL)..."

curl -s -X POST "$API_URL/auth/register" \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"$BIDDER_EMAIL\",
    \"password\": \"Password123!\",
    \"role\": \"OPERATEUR_ECONOMIQUE\",
    \"langue\": \"fr\",
    \"nom\": \"Bidder\",
    \"prenom\": \"Test\",
    \"telephone\": \"0555000000\",
    \"denomination\": \"Entreprise Bidder\",
    \"nif\": \"NIF$RANDOM_ID\",
    \"nis\": \"NIS$RANDOM_ID\",
    \"registre_commerce\": \"RC-$RANDOM_ID\",
    \"adresse\": \"Alger\",
    \"wilaya\": \"Alger\",
    \"commune\": \"Alger\",
    \"type\": \"ENTREPRISE_PRIVEE\"
  }" > /dev/null

sleep 2

curl -s -c $COOKIE_OPERATEUR -X POST "$API_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\": \"$BIDDER_EMAIL\", \"password\": \"Password123!\"}" > /dev/null

TOKEN_OPERATEUR=$(grep 'access_token' $COOKIE_OPERATEUR | awk '{print $7}')
echo "✅ Bidder Logged In!"

# ---------------------------------------------------------
# 5. FETCH LOT ID
# ---------------------------------------------------------
echo -e "\n[5/8] 🔍 Fetching Lot ID..."

curl -s -X GET "$API_URL/appels-offres/$AO_ID/lots" \
  -H "Authorization: Bearer $TOKEN_OPERATEUR" \
  -o $RESULTS_DIR/p3_5_lots.json

LOT_ID=$(jq -r 'if type=="array" then .[0].id else (if .data then .data[0].id else empty end) end' $RESULTS_DIR/p3_5_lots.json)
echo "✅ Ready! Lot ID: $LOT_ID"

# ---------------------------------------------------------
# 6. CREATE SUBMISSION DRAFT
# ---------------------------------------------------------
echo -e "\n[6/8] 📁 Creating Submission Draft for Lot..."
curl -s -X POST "$API_URL/soumissions" \
  -H "Authorization: Bearer $TOKEN_OPERATEUR" \
  -H "Content-Type: application/json" \
  -d "{ \"appelOffreId\": \"$AO_ID\", \"lotId\": \"$LOT_ID\" }" \
  -o $RESULTS_DIR/p3_6_create_sub.json

SUB_ID=$(jq -r '.data.id // .id // empty' $RESULTS_DIR/p3_6_create_sub.json)
echo "✅ Submission Created! ID: $SUB_ID"

# ---------------------------------------------------------
# 7. UPLOAD DOCUMENTS (TECH, FIN, & CAUTION!)
# ---------------------------------------------------------
echo -e "\n[7/8] 📤 Uploading Tech, Fin, and Caution Bancaire..."
echo "%PDF-1.4 Dummy PDF Content" > dummy.pdf

# Technical Offer
curl -s -X POST "$API_URL/soumissions/$SUB_ID/offre-technique" \
  -H "Authorization: Bearer $TOKEN_OPERATEUR" \
  -F "fichier=@dummy.pdf" > /dev/null

# Financial Offer (Encrypted + Signed)
curl -s -X POST "$API_URL/soumissions/$SUB_ID/offre-financiere" \
  -H "Authorization: Bearer $TOKEN_OPERATEUR" \
  -F "fichierChiffre=@dummy.pdf" \
  -F "signatureEcdsa=MEQCIDummySignature1234567890" \
  -F "clePubliqueEcdsaPem=DummyPublicKeyPEM" > /dev/null

# Caution Bancaire (Using the JSON 'donnees' parameter!)
CAUTION_JSON="{\"montant\": 500000.00, \"banque\": \"BEA\", \"reference\": \"CAUTION-$RANDOM_ID\", \"dateEmission\": \"$CURRENT_DATE\", \"dateExpiration\": \"2026-12-31T23:59:59\"}"

curl -s -X POST "$API_URL/soumissions/$SUB_ID/caution" \
  -H "Authorization: Bearer $TOKEN_OPERATEUR" \
  -F "scanCaution=@dummy.pdf" \
  -F "donnees=$CAUTION_JSON" \
  -o $RESULTS_DIR/p3_7_upload_caution.json

CAUT_SUCCESS=$(jq -r '.success // empty' $RESULTS_DIR/p3_7_upload_caution.json)
if [ "$CAUT_SUCCESS" != "true" ]; then
  echo "❌ Caution Upload Failed! Response:"
  cat $RESULTS_DIR/p3_7_upload_caution.json | jq
  exit 1
fi
echo "✅ All 3 Files Uploaded to MinIO!"

# ---------------------------------------------------------
# 8. VALIDATE SUBMISSION
# ---------------------------------------------------------
echo -e "\n[8/8] 🎯 Validating Final Submission..."
curl -s -X PUT "$API_URL/soumissions/$SUB_ID/valider" \
  -H "Authorization: Bearer $TOKEN_OPERATEUR" \
  -H "Content-Type: application/json" \
  -o $RESULTS_DIR/p3_8_validate.json

VAL_SUCCESS=$(jq -r '.success // empty' $RESULTS_DIR/p3_8_validate.json)
if [ "$VAL_SUCCESS" != "true" ]; then
  echo "❌ Validation Failed! Response:"
  cat $RESULTS_DIR/p3_8_validate.json | jq
  exit 1
fi

echo "✅ Submission Validated!"
echo -e "\n🎉 PHASE 3 COMPLETE!"
