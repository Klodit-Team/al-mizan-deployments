#!/bin/bash

# --- Configuration ---
API_URL="https://api.klodit.app/api/v1"
LOCAL_RECOURS_URL="http://localhost:8008/recours-service/v1/recours"
RESULTS_DIR="results"
COOKIE_PERDANT="$RESULTS_DIR/cookie_perdant.txt"
COOKIE_CONTROLEUR="$RESULTS_DIR/cookie_controleur.txt"
mkdir -p $RESULTS_DIR

# Hardcoded IDs from previous phases
AO_ID="df3dbfef-6946-46f5-9821-60c5aad44932"
ATTR_ID=$(jq -r '.id // empty' $RESULTS_DIR/p6_2_create_attribution.json)

if [ -z "$ATTR_ID" ] || [ "$ATTR_ID" == "null" ]; then
  echo "❌ Attribution ID missing! Did you run Phase 6?"
  exit 1
fi

RANDOM_ID=$(date +%s)
EMAIL_PERDANT="perdant_${RANDOM_ID}@entreprise.com"
EMAIL_CONTROLEUR="controleur_${RANDOM_ID}@arf.dz"

echo "=================================================="
echo "🚀 STARTING PHASE 7: APPEALS (RECOURS)"
echo "=================================================="

# ---------------------------------------------------------
# 1. REGISTER & LOGIN LOSING BIDDER
# ---------------------------------------------------------
echo -e "\n[1/5] 📝 Registering Losing Bidder ($EMAIL_PERDANT)..."
curl -s -X POST "$API_URL/auth/register" \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"$EMAIL_PERDANT\",
    \"password\": \"Password123!\",
    \"role\": \"OPERATEUR_ECONOMIQUE\",
    \"langue\": \"fr\",
    \"nom\": \"Losing\",
    \"prenom\": \"Bidder\",
    \"telephone\": \"0555000000\",
    \"denomination\": \"Entreprise Perdante\",
    \"nif\": \"NIF$RANDOM_ID\",
    \"nis\": \"NIS$RANDOM_ID\",
    \"registre_commerce\": \"RC-$RANDOM_ID\",
    \"adresse\": \"Alger\",
    \"wilaya\": \"Alger\",
    \"commune\": \"Alger\",
    \"type\": \"ENTREPRISE_PRIVEE\"
  }" > /dev/null

sleep 2

curl -s -c $COOKIE_PERDANT -X POST "$API_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\": \"$EMAIL_PERDANT\", \"password\": \"Password123!\"}" -o $RESULTS_DIR/p7_1_login_bidder.json

TOKEN_PERDANT=$(grep 'access_token' $COOKIE_PERDANT | awk '{print $7}')
USER_ID_PERDANT=$(jq -r '.user.userId // empty' $RESULTS_DIR/p7_1_login_bidder.json)
echo "✅ Losing Bidder Ready! ID: $USER_ID_PERDANT"

# ---------------------------------------------------------
# 2. REGISTER CONTROLEUR
# ---------------------------------------------------------
echo -e "\n[2/5] 👮 Registering Official Controleur ($EMAIL_CONTROLEUR)..."
curl -s -X POST "$API_URL/auth/register" \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"$EMAIL_CONTROLEUR\",
    \"password\": \"Password123!\",
    \"role\": \"SERVICE_CONTRACTANT\",
    \"langue\": \"fr\",
    \"nom\": \"Juge\",
    \"prenom\": \"Arbitre\",
    \"telephone\": \"0210000000\",
    \"denomination\": \"Autorité de Régulation\",
    \"type\": \"MINISTERE\",
    \"nif\": \"$RANDOM_ID\",
    \"nis\": \"$RANDOM_ID\",
    \"code_service\": \"ARF-$RANDOM_ID\",
    \"secteur_activite\": \"Controle\",
    \"ordonnateur\": \"President ARF\"
  }" -o $RESULTS_DIR/p7_2_register_controleur.json

USER_ID_CONTROLEUR=$(jq -r '.user_id // empty' $RESULTS_DIR/p7_2_register_controleur.json)
echo "✅ Controleur Registered! ID: $USER_ID_CONTROLEUR"
sleep 2

# ---------------------------------------------------------
# 3. PROMOTE CONTROLEUR TO ADMIN
# ---------------------------------------------------------
echo -e "\n[3/5] 👑 Promoting Controleur to ADMIN before Login..."
sudo docker exec al-mizan-mysql mysql -uroot -ppassword -e "
USE al_mizan_users;
SET @adminRoleId = (SELECT id FROM roles WHERE name='ADMIN' LIMIT 1);
INSERT IGNORE INTO user_roles (id, user_id, role_id, assigned_at) VALUES (UUID(), '$USER_ID_CONTROLEUR', @adminRoleId, NOW());
" > /dev/null 2>&1
echo "✅ Promoted to Admin!"

# ---------------------------------------------------------
# 4. FILE AN APPEAL (DEPOSER VIA GATEWAY)
# ---------------------------------------------------------
echo -e "\n[4/5] ⚖️ Filing an Appeal against Attribution..."
curl -s -X POST "$API_URL/recours" \
  -H "Authorization: Bearer $TOKEN_PERDANT" \
  -H "Content-Type: application/json" \
  -d "{
    \"appelOffreId\": \"$AO_ID\",
    \"operateurId\": \"$USER_ID_PERDANT\",
    \"attributionProvisoireId\": \"$ATTR_ID\",
    \"motif\": \"Les critères de notation n'ont pas été correctement appliqués selon le cahier des charges section 3.2. L'entreprise gagnante ne possède pas la certification ISO 9001 requise.\",
    \"piecesJointesUrls\": [\"https://minio.klodit.app/docs/preuve.pdf\"]
  }" -o $RESULTS_DIR/p7_4_deposer.json

RECOURS_ID=$(jq -r '.data.id // .id // empty' $RESULTS_DIR/p7_4_deposer.json)

if [ -z "$RECOURS_ID" ] || [ "$RECOURS_ID" == "null" ]; then
  echo "❌ Failed to file appeal! Error:"
  cat $RESULTS_DIR/p7_4_deposer.json | jq
  exit 1
fi
echo "✅ Appeal Filed! ID: $RECOURS_ID"

# ---------------------------------------------------------
# 5. EXAMINE & DECIDE (DIRECT TO MICROSERVICE!)
# ---------------------------------------------------------
echo -e "\n[5/5] 🔍 Examining and Deciding the Appeal..."

# EXAMINER (Pass from DEPOSE to EN_EXAMEN)
curl -s -X PATCH "$LOCAL_RECOURS_URL/$RECOURS_ID/examiner" \
  -H "x-user-id: $USER_ID_CONTROLEUR" \
  -H "x-user-roles: [\"ADMIN\",\"CONTROLEUR\"]" \
  -H "Content-Type: application/json" \
  -d "{
    \"examinateurId\": \"$USER_ID_CONTROLEUR\",
    \"notes\": \"Dossier complet, les preuves fournies méritent une enquête approfondie.\",
    \"recommandation\": \"Recours fondé, recommande l'annulation de l'attribution.\"
  }" -o $RESULTS_DIR/p7_5_examiner.json

EXAMEN_STATUS=$(jq -r '.data.statut // .statut // empty' $RESULTS_DIR/p7_5_examiner.json)

if [ "$EXAMEN_STATUS" != "EN_EXAMEN" ]; then
  echo "❌ Examination failed! Error:"
  cat $RESULTS_DIR/p7_5_examiner.json | jq
  exit 1
fi
echo "✅ Appeal is now: EN_EXAMEN"

# STATUER (Pass from EN_EXAMEN to ACCEPTE)
curl -s -X PATCH "$LOCAL_RECOURS_URL/$RECOURS_ID/statuer" \
  -H "x-user-id: $USER_ID_CONTROLEUR" \
  -H "x-user-roles: [\"ADMIN\",\"CONTROLEUR\"]" \
  -H "Content-Type: application/json" \
  -d "{
    \"decision\": \"ACCEPTE\",
    \"motifDecision\": \"Après enquête de la Commission des Marchés, il a été prouvé que le soumissionnaire gagnant ne disposait pas de la certification requise. Le recours est accepté.\",
    \"commentaire\": \"L'attribution sera annulée.\"
  }" -o $RESULTS_DIR/p7_5_statuer.json

FINAL_STATUS=$(jq -r '.data.statut // .statut // empty' $RESULTS_DIR/p7_5_statuer.json)

if [ "$FINAL_STATUS" != "ACCEPTE" ]; then
  echo "❌ Decision failed! Error:"
  cat $RESULTS_DIR/p7_5_statuer.json | jq
  exit 1
fi

echo "✅ Final Decision Reached: $FINAL_STATUS"
echo -e "\n🎉 PHASE 7 COMPLETE!"
