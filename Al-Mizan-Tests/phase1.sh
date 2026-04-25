#!/bin/bash

# --- Configuration ---
API_URL="https://api.klodit.app/api/v1"
RESULTS_DIR="results"
COOKIE_JAR="$RESULTS_DIR/cookies.txt"
mkdir -p $RESULTS_DIR

# Generate a random email
RANDOM_ID=$(date +%s)
EMAIL="test_${RANDOM_ID}@klodit.app"
PASSWORD="Password123!"

echo "=================================================="
echo "🚀 STARTING PHASE 1: AUTH & USERS INTEGRATION TEST"
echo "=================================================="

# ---------------------------------------------------------
# 1. REGISTER USER
# ---------------------------------------------------------
echo -e "\n[1/5] 📝 Registering new Operateur Economique ($EMAIL)..."
curl -s -X POST "$API_URL/auth/register" \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"$EMAIL\",
    \"password\": \"$PASSWORD\",
    \"role\": \"OPERATEUR_ECONOMIQUE\",
    \"langue\": \"fr\",
    \"nom\": \"Test\",
    \"prenom\": \"Phase1\",
    \"telephone\": \"0555000000\",
    \"denomination\": \"Entreprise Test $RANDOM_ID\",
    \"nif\": \"$RANDOM_ID\",
    \"type\": \"ENTREPRISE_PRIVEE\"
  }" -o $RESULTS_DIR/1_register.json

USER_ID=$(jq -r '.user_id' $RESULTS_DIR/1_register.json)
echo "✅ Registered! User ID: $USER_ID"

# ---------------------------------------------------------
# 2. LOGIN & SAVE COOKIE
# ---------------------------------------------------------
echo -e "\n[2/5] 🔐 Logging in to get Secure Cookie..."
# Notice the -c (cookie jar) flag!
curl -s -c $COOKIE_JAR -X POST "$API_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"$EMAIL\",
    \"password\": \"$PASSWORD\"
  }" -o $RESULTS_DIR/2_login.json

LOGIN_MSG=$(jq -r '.message' $RESULTS_DIR/2_login.json)

if [[ "$LOGIN_MSG" != *"successfully"* ]]; then
  echo "❌ Login Failed! Check 2_login.json"
  exit 1
fi
echo "✅ Login Successful! Cookie saved."

# ---------------------------------------------------------
# 3. TEST /AUTH/ME
# ---------------------------------------------------------
echo -e "\n[3/5] 👤 Verifying Session via /auth/me..."
# Notice the -b (use cookie) flag!
curl -s -b $COOKIE_JAR -X GET "$API_URL/auth/me" \
  -H "Content-Type: application/json" \
  -o $RESULTS_DIR/3_auth_me.json

echo "✅ Auth/Me verified. Response saved."

# ---------------------------------------------------------
# 4. TEST /USERS/PROFILES/USER/{userId}
# ---------------------------------------------------------
echo -e "\n[4/5] 🐇 Checking if RabbitMQ created the User Profile..."
sleep 2 # Wait for RabbitMQ

curl -s -b $COOKIE_JAR -X GET "$API_URL/users/profiles/user/$USER_ID" \
  -H "Content-Type: application/json" \
  -o $RESULTS_DIR/4_user_profile.json

echo "✅ Profile retrieved. Response saved."

# ---------------------------------------------------------
# 5. TEST /USERS/ORGANISATIONS
# ---------------------------------------------------------
echo -e "\n[5/5] 🏢 Listing Organisations to verify insertion..."
curl -s -b $COOKIE_JAR -X GET "$API_URL/users/organisations" \
  -H "Content-Type: application/json" \
  -o $RESULTS_DIR/5_organisations.json

echo "✅ Organisations retrieved. Response saved."

echo -e "\n🎉 PHASE 1 COMPLETE! Check the '$RESULTS_DIR' folder for outputs."
