#!/bin/bash

# --- Configuration ---
API_URL="https://api.klodit.app/api/v1"
LOCAL_AO_URL="http://localhost:8003/api/v1"
LOCAL_COMMISSION_URL="http://localhost:8007/api/v1"
RESULTS_DIR="results"
COOKIE_CONTRACTANT="$RESULTS_DIR/cookie_contractant.txt"
mkdir -p $RESULTS_DIR

# Hardcoded AO_ID from Phase 2
AO_ID="df3dbfef-6946-46f5-9821-60c5aad44932"
RANDOM_ID=$(date +%s)

# Dates formatting (ISO 8601)
DATE_TODAY=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DATE_FIN_RECOURS=$(date -u -d "+10 days" +"%Y-%m-%dT%H:%M:%SZ")

echo "=================================================="
echo "🚀 STARTING PHASE 6: ATTRIBUTIONS & MARCHÉS"
echo "=================================================="

# 0. Extract IDs from previous phases via MySQL
RAW_SUB_ID=$(sudo docker exec al-mizan-mysql mysql -uroot -ppassword -sN -D soumission_db -e "SELECT id FROM soumissions ORDER BY created_at DESC LIMIT 1;" 2>/dev/null)
SUB_ID=$(echo "$RAW_SUB_ID" | tr -d '\r')

if [ -z "$SUB_ID" ] || [ "$SUB_ID" == "null" ]; then
  echo "❌ Missing SUB_ID! Did you run Phase 4/5?"
  exit 1
fi

# ---------------------------------------------------------
# 1. RE-AUTHENTICATE CONTRACTANT
# ---------------------------------------------------------
EMAIL_CONTRACTANT="acheteur_${RANDOM_ID}@ministere.dz"
echo -e "\n[1/5] 📝 Re-authenticating Contractant..."

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

sleep 2 # Wait for RabbitMQ

curl -s -c $COOKIE_CONTRACTANT -X POST "$API_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\": \"$EMAIL_CONTRACTANT\", \"password\": \"Password123!\"}" -o $RESULTS_DIR/p6_1_login.json

USER_ID_CONTRACTANT=$(jq -r '.user.userId // empty' $RESULTS_DIR/p6_1_login.json)
echo "✅ Contractant Ready! ID: $USER_ID_CONTRACTANT"

# ---------------------------------------------------------
# 2. CREATE ATTRIBUTION (PROVISOIRE)
# ---------------------------------------------------------
echo -e "\n[2/5] 🏆 Awarding Contract (Attribution Provisoire)..."
curl -s -X POST "$LOCAL_AO_URL/attributions" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN,SERVICE_CONTRACTANT" \
  -H "Content-Type: application/json" \
  -d "{
    \"aoId\": \"$AO_ID\",
    \"soumissionId\": \"$SUB_ID\",
    \"type\": \"PROVISOIRE\",
    \"dateAttribution\": \"$DATE_TODAY\",
    \"dateFinRecours\": \"$DATE_FIN_RECOURS\",
    \"montantAttribue\": 15000000
  }" -o $RESULTS_DIR/p6_2_create_attribution.json

ATTR_ID=$(jq -r '.id // empty' $RESULTS_DIR/p6_2_create_attribution.json)

if [ -z "$ATTR_ID" ] || [ "$ATTR_ID" == "null" ]; then
  echo "❌ Failed to create Attribution! Error:"
  cat $RESULTS_DIR/p6_2_create_attribution.json | jq
  exit 1
fi
echo "✅ Attribution Created! ID: $ATTR_ID"

# ---------------------------------------------------------
# 3. CREATE COMMISSION DES MARCHÉS
# ---------------------------------------------------------
echo -e "\n[3/5] 🏛️ Creating Commission des Marchés..."
curl -s -X POST "$LOCAL_COMMISSION_URL/commissions-marche" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN,SERVICE_CONTRACTANT" \
  -H "Content-Type: application/json" \
  -d "{
    \"intitule\": \"Commission des Marchés - Validation IT\",
    \"typeMarche\": \"FOURNITURES\",
    \"montantEstime\": 15000000,
    \"presidentId\": \"$USER_ID_CONTRACTANT\",
    \"soumissionnairesCount\": 1
  }" -o $RESULTS_DIR/p6_3_create_commission_marche.json

COMM_MARCHE_ID=$(jq -r '.id // empty' $RESULTS_DIR/p6_3_create_commission_marche.json)

if [ -z "$COMM_MARCHE_ID" ] || [ "$COMM_MARCHE_ID" == "null" ]; then
  echo "❌ Failed to create Commission des Marchés! Error:"
  cat $RESULTS_DIR/p6_3_create_commission_marche.json | jq
  exit 1
fi
echo "✅ Commission des Marchés Created! ID: $COMM_MARCHE_ID"

# ---------------------------------------------------------
# 4. RECORD DELIBERATION & AWARD THE MARKET
# ---------------------------------------------------------
echo -e "\n[4/5] 📝 Recording Deliberation PV and Final Award..."

# Deliberation PV
curl -s -X POST "$LOCAL_COMMISSION_URL/commissions-marche/$COMM_MARCHE_ID/deliberation" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN,SERVICE_CONTRACTANT" \
  -H "Content-Type: application/json" \
  -d "{
    \"pvDeliberation\": \"La commission déclare le soumissionnaire conforme et valide l'attribution.\",
    \"soumissionnairesCount\": 1
  }" > /dev/null

# Final Attribution decision by the Commission
curl -s -X PATCH "$LOCAL_COMMISSION_URL/commissions-marche/$COMM_MARCHE_ID/attribution" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN,SERVICE_CONTRACTANT" \
  -H "Content-Type: application/json" \
  -d "{
    \"soumissionnairesRetenu\": \"Entreprise Bidder\"
  }" > /dev/null

echo "✅ Deliberation Recorded and Market Awarded by Commission!"

# ---------------------------------------------------------
# 5. CREATE THE FINAL MARCHÉ (CONTRACT)
# ---------------------------------------------------------
echo -e "\n[5/5] 📜 Signing the Final Contract (Le Marché)..."
curl -s -X POST "$LOCAL_AO_URL/marches" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN,SERVICE_CONTRACTANT" \
  -H "Content-Type: application/json" \
  -d "{
    \"aoId\": \"$AO_ID\",
    \"attributionId\": \"$ATTR_ID\",
    \"referenceMarche\": \"MARCHE-$RANDOM_ID\",
    \"montantSigne\": 15000000,
    \"dateSignature\": \"$DATE_TODAY\",
    \"delaiExecution\": 180
  }" -o $RESULTS_DIR/p6_5_create_marche.json

MARCHE_ID=$(jq -r '.id // empty' $RESULTS_DIR/p6_5_create_marche.json)

if [ -z "$MARCHE_ID" ] || [ "$MARCHE_ID" == "null" ]; then
  echo "❌ Failed to create Final Contract! Error:"
  cat $RESULTS_DIR/p6_5_create_marche.json | jq
  exit 1
fi
echo "✅ Final Contract (Marché) Officially Signed! ID: $MARCHE_ID"

echo -e "\n🎉 PHASE 6 COMPLETE!"
