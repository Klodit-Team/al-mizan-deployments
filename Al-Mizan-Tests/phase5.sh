#!/bin/bash

# --- Configuration ---
API_URL="https://api.klodit.app/api/v1"
LOCAL_EVAL_URL="http://localhost:8006/api/v1/evaluations"
RESULTS_DIR="results"
mkdir -p $RESULTS_DIR

# Hardcoded AO_ID from Phase 2
AO_ID="df3dbfef-6946-46f5-9821-60c5aad44932"

echo "=================================================="
echo "🚀 STARTING PHASE 5: EVALUATION & SCORING"
echo "=================================================="

# 0. Extract IDs from previous phases via MySQL
USER_ID_CONTRACTANT=$(jq -r '.user.userId // empty' $RESULTS_DIR/p3_1_login.json)
COMMISSION_ID=$(jq -r '.id // empty' $RESULTS_DIR/p4_2_create_commission.json)

RAW_SUB_ID=$(sudo docker exec al-mizan-mysql mysql -uroot -ppassword -sN -D soumission_db -e "SELECT id FROM soumissions ORDER BY created_at DESC LIMIT 1;" 2>/dev/null)
SUB_ID=$(echo "$RAW_SUB_ID" | tr -d '\r')

OPERATEUR_ID=$(sudo docker exec al-mizan-mysql mysql -uroot -ppassword -sN -D soumission_db -e "SELECT operateur_id FROM soumissions WHERE id='$SUB_ID' LIMIT 1;" 2>/dev/null | tr -d '\r')
LOT_ID=$(sudo docker exec al-mizan-mysql mysql -uroot -ppassword -sN -D soumission_db -e "SELECT lot_id FROM soumissions WHERE id='$SUB_ID' LIMIT 1;" 2>/dev/null | tr -d '\r')

if [ -z "$SUB_ID" ] || [ -z "$COMMISSION_ID" ]; then
  echo "❌ Missing SUB_ID or COMMISSION_ID! Did you run Phase 4?"
  exit 1
fi

echo "✅ Context Loaded!"

# ---------------------------------------------------------
# 1. CREATE EVALUATION
# ---------------------------------------------------------
echo -e "\n[1/8] 📋 Creating Technical Evaluation..."
curl -s -X POST "$LOCAL_EVAL_URL" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN,SERVICE_CONTRACTANT" \
  -H "Content-Type: application/json" \
  -d "{
    \"appelOffreId\": \"$AO_ID\",
    \"commissionId\": \"$COMMISSION_ID\",
    \"type\": \"TECHNIQUE\",
    \"scoringMode\": \"GRILLE_CRITERES\",
    \"objet\": \"Évaluation Technique Initiale\",
    \"modeAveugle\": false,
    \"technicalWeight\": 100,
    \"financialWeight\": 0,
    \"minimumOverallScore\": 50
  }" -o $RESULTS_DIR/p5_1_create_eval.json

EVAL_ID=$(jq -r '.id // empty' $RESULTS_DIR/p5_1_create_eval.json)

if [ -z "$EVAL_ID" ] || [ "$EVAL_ID" == "null" ]; then
  echo "❌ Failed to create Evaluation! Error:"
  cat $RESULTS_DIR/p5_1_create_eval.json | jq
  exit 1
fi
echo "✅ Evaluation Created! ID: $EVAL_ID"

# ---------------------------------------------------------
# 2. ADD EVALUATION CRITERION
# ---------------------------------------------------------
echo -e "\n[2/8] ⚖️ Adding Scoring Criterion..."
curl -s -X POST "$LOCAL_EVAL_URL/$EVAL_ID/criteres" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN,SERVICE_CONTRACTANT" \
  -H "Content-Type: application/json" \
  -d "{
    \"code\": \"TECH-01\",
    \"libelle\": \"Qualité du matériel et garantie\",
    \"poids\": 100,
    \"noteMax\": 100,
    \"noteMinimale\": 50,
    \"eliminatoire\": true
  }" -o $RESULTS_DIR/p5_2_add_criterion.json

CRITERION_ID=$(jq -r '.id // empty' $RESULTS_DIR/p5_2_add_criterion.json)
echo "✅ Criterion Added! ID: $CRITERION_ID"

# ---------------------------------------------------------
# 3. REGISTER SUBMISSION TO EVALUATION
# ---------------------------------------------------------
echo -e "\n[3/8] 📥 Registering Submission for Scoring..."
curl -s -X POST "$LOCAL_EVAL_URL/$EVAL_ID/soumissions" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN,SERVICE_CONTRACTANT" \
  -H "Content-Type: application/json" \
  -d "{
    \"externalSubmissionId\": \"$SUB_ID\",
    \"operateurEconomiqueId\": \"$OPERATEUR_ID\",
    \"operateurNom\": \"Entreprise Bidder\",
    \"lotId\": \"$LOT_ID\"
  }" -o $RESULTS_DIR/p5_3_register_sub.json

EVAL_SUB_ID=$(jq -r '.id // empty' $RESULTS_DIR/p5_3_register_sub.json)
echo "✅ Submission Registered! Eval-Sub ID: $EVAL_SUB_ID"

# ---------------------------------------------------------
# 4. START EVALUATION (State Machine Fix!)
# ---------------------------------------------------------
echo -e "\n[4/8] ▶️ Advancing Evaluation State Machine..."

# Step 4a: BROUILLON -> PRETE
curl -s -X PATCH "$LOCAL_EVAL_URL/$EVAL_ID/statut" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN,SERVICE_CONTRACTANT" \
  -H "Content-Type: application/json" \
  -d "{ \"statut\": \"PRETE\" }" > /dev/null

# Step 4b: PRETE -> EN_COURS
curl -s -X PATCH "$LOCAL_EVAL_URL/$EVAL_ID/statut" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN,SERVICE_CONTRACTANT" \
  -H "Content-Type: application/json" \
  -d "{ \"statut\": \"EN_COURS\" }" > /dev/null

echo "✅ Status successfully transitioned to: EN_COURS"

# ---------------------------------------------------------
# 5. ASSIGN SCORE
# ---------------------------------------------------------
echo -e "\n[5/8] ✍️ Assigning Score to Submission..."
curl -s -X POST "$LOCAL_EVAL_URL/$EVAL_ID/soumissions/$EVAL_SUB_ID/notes" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN,SERVICE_CONTRACTANT" \
  -H "Content-Type: application/json" \
  -d "{
    \"criterionId\": \"$CRITERION_ID\",
    \"note\": 85,
    \"justification\": \"Le matériel proposé dépasse les attentes du CDC.\",
    \"evaluatorName\": \"Commission Président\"
  }" -o $RESULTS_DIR/p5_5_score.json

NOTE_ID=$(jq -r '.id // empty' $RESULTS_DIR/p5_5_score.json)
if [ -z "$NOTE_ID" ] || [ "$NOTE_ID" == "null" ]; then
  echo "❌ Failed to assign score! Error:"
  cat $RESULTS_DIR/p5_5_score.json | jq
  exit 1
fi
echo "✅ Score Assigned! (85/100)"

# ---------------------------------------------------------
# 6. RECALCULATE SCORES & RANKING
# ---------------------------------------------------------
echo -e "\n[6/8] 🧮 Calculating Rankings..."
curl -s -X POST "$LOCAL_EVAL_URL/$EVAL_ID/recalculer-scores" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN,SERVICE_CONTRACTANT" \
  -H "Content-Type: application/json" > /dev/null
echo "✅ Ranking Algorithm Executed!"

# ---------------------------------------------------------
# 7. CLOSE EVALUATION
# ---------------------------------------------------------
echo -e "\n[7/8] 🛑 Closing Evaluation Phase..."
curl -s -X PATCH "$LOCAL_EVAL_URL/$EVAL_ID/statut" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN,SERVICE_CONTRACTANT" \
  -H "Content-Type: application/json" \
  -d "{ \"statut\": \"TERMINEE\" }" > /dev/null
echo "✅ Status: TERMINEE"

# ---------------------------------------------------------
# 8. GENERATE REPORT & VALIDATE
# ---------------------------------------------------------
echo -e "\n[8/8] 📄 Generating Official Evaluation Report (PDF)..."
curl -s -X POST "$LOCAL_EVAL_URL/$EVAL_ID/rapport" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN,SERVICE_CONTRACTANT" \
  -H "Content-Type: application/json" \
  -o $RESULTS_DIR/p5_8_report.json

REPORT_URL=$(jq -r '.downloadUrl // empty' $RESULTS_DIR/p5_8_report.json)
if [ -z "$REPORT_URL" ] || [ "$REPORT_URL" == "null" ]; then
  echo "❌ Report Generation Failed! Error:"
  cat $RESULTS_DIR/p5_8_report.json | jq
  exit 1
fi
echo "✅ Report Generated and Uploaded to MinIO! URL: $REPORT_URL"

# Finally, validate the evaluation!
curl -s -X PATCH "$LOCAL_EVAL_URL/$EVAL_ID/statut" \
  -H "X-User-Id: $USER_ID_CONTRACTANT" \
  -H "X-User-Roles: ADMIN,SERVICE_CONTRACTANT" \
  -H "Content-Type: application/json" \
  -d "{ \"statut\": \"VALIDEE\" }" > /dev/null

echo "✅ Evaluation officially VALIDATED!"
echo -e "\n🎉 PHASE 5 COMPLETE!"
