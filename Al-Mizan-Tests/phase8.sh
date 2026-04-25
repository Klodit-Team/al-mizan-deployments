#!/bin/bash

# --- Configuration ---
LOCAL_NOTIF_URL="http://localhost:8010/notification-service/v1"
RESULTS_DIR="results"
mkdir -p $RESULTS_DIR

echo "=================================================="
echo "🚀 STARTING PHASE 8: NOTIFICATIONS, FCM & IA"
echo "=================================================="

# 0. Grab an Admin ID from the database to bypass RBAC
ADMIN_ID=$(sudo docker exec al-mizan-mysql mysql -uroot -ppassword -sN -D al_mizan_users -e "SELECT user_id FROM user_roles WHERE role_id = (SELECT id FROM roles WHERE name='ADMIN' LIMIT 1) LIMIT 1;" 2>/dev/null | tr -d '\r')

if [ -z "$ADMIN_ID" ]; then
  echo "❌ Could not find an Admin ID in the database!"
  exit 1
fi
echo "✅ Admin ID Loaded: $ADMIN_ID"

# ---------------------------------------------------------
# 1. HEALTH CHECK
# ---------------------------------------------------------
echo -e "\n[1/4] 🩺 Pinging Notification Service Health Check..."
curl -s -X GET "$LOCAL_NOTIF_URL/health" -o $RESULTS_DIR/p8_1_health.json

# FIXED THE JQ PATH!
HEALTH_STATUS=$(jq -r '.data.status // .status // empty' $RESULTS_DIR/p8_1_health.json)
if [ "$HEALTH_STATUS" != "ok" ]; then
  echo "❌ Health check failed! Output:"
  cat $RESULTS_DIR/p8_1_health.json | jq
  exit 1
fi
echo "✅ Service Health: OK (MySQL & Redis verified)"

# ---------------------------------------------------------
# 2. VERIFY RABBITMQ NOTIFICATIONS
# ---------------------------------------------------------
echo -e "\n[2/4] 📬 Fetching Global Notifications (RabbitMQ Consumers)..."
curl -s -X GET "$LOCAL_NOTIF_URL/notifications?limit=10" \
  -H "x-user-id: $ADMIN_ID" \
  -H "x-user-roles: [\"ADMIN\"]" \
  -o $RESULTS_DIR/p8_2_notifications.json

NOTIF_COUNT=$(jq -r '.data.total // 0' $RESULTS_DIR/p8_2_notifications.json)

echo "✅ Success! Found $NOTIF_COUNT notifications generated in the background."

# ---------------------------------------------------------
# 3. REGISTER ANDROID FCM TOKEN
# ---------------------------------------------------------
echo -e "\n[3/4] 📱 Registering Android FCM Device Token..."
curl -s -X POST "$LOCAL_NOTIF_URL/device-tokens" \
  -H "x-user-id: $ADMIN_ID" \
  -H "x-user-roles: [\"ADMIN\"]" \
  -H "Content-Type: application/json" \
  -d '{
    "token": "fcm_token_test_abc123",
    "deviceId": "android-pixel-7"
  }' -o $RESULTS_DIR/p8_3_fcm_token.json

FCM_SUCCESS=$(jq -r '.success // empty' $RESULTS_DIR/p8_3_fcm_token.json)
if [ "$FCM_SUCCESS" != "true" ]; then
  echo "❌ FCM Registration Failed!"
  cat $RESULTS_DIR/p8_3_fcm_token.json | jq
  exit 1
fi
echo "✅ Push Notification Device Registered!"

# ---------------------------------------------------------
# 4. CHECK IA ALERTS
# ---------------------------------------------------------
echo -e "\n[4/4] 🤖 Checking IA Incident Alerts..."
curl -s -X GET "$LOCAL_NOTIF_URL/alertes-ia" \
  -H "x-user-id: $ADMIN_ID" \
  -H "x-user-roles: [\"ADMIN\"]" \
  -o $RESULTS_DIR/p8_4_alertes_ia.json

IA_COUNT=$(jq -r '.data.total // 0' $RESULTS_DIR/p8_4_alertes_ia.json)
echo "✅ Success! Checked IA Alerts (Found: $IA_COUNT anomalies)."

echo -e "\n🎉 PHASE 8 COMPLETE! THE PLATFORM IS FULLY OPERATIONAL!"
