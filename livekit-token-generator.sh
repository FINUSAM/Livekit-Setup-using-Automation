#!/bin/bash

# Configuration
API_KEY="APIkbSL89cHqVXY"
API_SECRET="LNFIALFMmdkUTFRFCvp88BAvifFFF3toPg6I1f41ctK"
ROOM="test_room"
IDENTITY="test_user"
DURATION="1h"

# 1. Ensure jq is installed (required by the LiveKit installer)
if ! command -v jq &> /dev/null
then
    echo "jq not found. Installing jq..."
    sudo apt-get update && sudo apt-get install -y jq
fi

# 2. Check if lk CLI is installed
if ! command -v lk &> /dev/null
then
    echo "LiveKit CLI (lk) not found. Installing now..."
    # Run the installer with sudo to allow writing to /usr/local/bin
    curl -sSL https://get.livekit.io/cli | sudo bash

    if [ $? -ne 0 ]; then
        echo "Installation failed. Please check your internet connection."
        exit 1
    fi
    echo "LiveKit CLI installed successfully."
fi

# 3. Generate the token
echo "Generating token for:"
echo "-- Room: $ROOM"
echo "-- User: $IDENTITY"

TOKEN=$(lk token create \
    --api-key "$API_KEY" \
    --api-secret "$API_SECRET" \
    --join \
    --room "$ROOM" \
    --identity "$IDENTITY" \
    --valid-for "$DURATION")

# 4. Output the results
echo "-----------------------------------------------"
echo "Your LiveKit Token:"
echo "$TOKEN"
echo "-----------------------------------------------"