#!/bin/bash

# --- Configuration ---
API_URL="https://api.klodit.app/api/v1"
RESULTS_DIR="results"
COOKIE_JAR="$RESULTS_DIR/cookie_contractant.txt"
mkdir -p $RESULTS_DIR

RANDOM_ID=$(date +%s)
EMAIL="acheteur_${RANDOM_ID}@ministere.dz"
PASSWORD="Password123!"

echo "=================================================="
echo "🚀 STARTING PHASE 2: TENDERS (APPELS D'OFFRES)"
echo "=================================================="

# ---------------------------------------------------------
# 1. REGISTER SERVICE CONTRACTANT
# ---------------------------------------------------------
echo -e "\n[1/5] 📝 Registering Service Contractant ($EMAIL)..."
curl -s -X POST "$API_URL/auth/register" \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"$EMAIL\",
    \"password\": \"$PASSWORD\",
    \"role\": \"SERVICE_CONTRACTANT\",
    \"langue\": \"fr\",
    \"nom\": \"Directeur\",
    \"prenom\": \"Achat\",
    \"telephone\": \"021000000\",
    \"denomination\": \"Ministère des Finances $RANDOM_ID\",
    \"type\": \"MINISTERE\",
    \"nif\": \"$RANDOM_ID\",
    \"nis\": \"$RANDOM_ID\",
    \"code_service\": \"SRV-$RANDOM_ID\",
    \"secteur_activite\": \"Finances\",
    \"ordonnateur\": \"Ministre\"
  }" -o $RESULTS_DIR/p2_1_register.json

echo "✅ Registered!"
sleep 2

# ---------------------------------------------------------
# 2. LOGIN & EXTRACT TOKENS
# ---------------------------------------------------------
echo -e "\n[2/5] 🔐 Logging in as Contractant..."
curl -s -c $COOKIE_JAR -X POST "$API_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"$EMAIL\",
    \"password\": \"$PASSWORD\"
  }" -o $RESULTS_DIR/p2_2_login.json

TOKEN=$(grep 'access_token' $COOKIE_JAR | awk '{print $7}')
USER_ID=$(jq -r '.user.userId' $RESULTS_DIR/p2_2_login.json)

if [ -z "$TOKEN" ] || [ "$USER_ID" == "null" ]; then
  echo "❌ Login Failed! Could not extract Token or User ID."
  exit 1
fi
echo "✅ Login Successful! User ID: $USER_ID"

# ---------------------------------------------------------
# 3. CREATE TENDER (Appel d'Offres)
# ---------------------------------------------------------
echo -e "\n[3/5] 📄 Creating an Appel d'Offres..."
curl -s -X POST "$API_URL/appels-offres/" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"reference\": \"AO-${RANDOM_ID}\",
    \"objet\": \"Fourniture de 100 PC portables pour le ministère\",
    \"typeProcedure\": \"AO_OUVERT\",
    \"montantEstime\": 15000000.00,
    \"dateLimiteSoumission\": \"2026-12-31T23:59:59Z\",
    \"dateLimiteRetraitCdc\": \"2026-12-15T23:59:59Z\",
    \"serviceContractantId\": \"$USER_ID\",
    \"wilaya\": \"Alger\",
    \"secteurActivite\": \"Informatique\"
  }" -o $RESULTS_DIR/p2_3_create_ao.json

AO_ID=$(jq -r '.id // empty' $RESULTS_DIR/p2_3_create_ao.json)

if [ -z "$AO_ID" ]; then
  echo "⚠️ Could not extract Tender ID. Validation Error:"
  cat $RESULTS_DIR/p2_3_create_ao.json | jq
  exit 1
fi
echo "✅ Tender Created! ID: $AO_ID"

# ---------------------------------------------------------
# 4. ADD A LOT
# ---------------------------------------------------------
echo -e "\n[4/5] 📦 Adding a Lot to the Tender..."
curl -s -X POST "$API_URL/appels-offres/$AO_ID/lots" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"numero\": \"1\",
    \"designation\": \"PC Portables Hautes Performances\",
    \"montantEstime\": 15000000.00
  }" -o $RESULTS_DIR/p2_4_add_lot.json

echo "✅ Lot Added!"

# ---------------------------------------------------------
# 5. ADD EVALUATION CRITERIA
# ---------------------------------------------------------
echo -e "\n[5/5] ⚖️ Adding Evaluation Criteria..."
curl -s -X POST "$API_URL/appels-offres/$AO_ID/criteres-evaluation" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"libelle\": \"Qualité Technique\",
    \"categorie\": \"TECHNIQUE\",
    \"poids\": 60
  }" -o $RESULTS_DIR/p2_5_add_criteria.json

echo "✅ Criterion Added!"

echo -e "\n🎉 PHASE 2 COMPLETE!"
