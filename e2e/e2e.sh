#!/usr/bin/env bash

set -e

#Always compile ytsync
make
#Always compile supporty
cd e2e/supporty && make && cd ../..

#OVERRIDE this in your .env file if running from mac. Check docker-compose.yml for details
export LOCAL_TMP_DIR="/var/tmp:/var/tmp"

#Private Variables Set in local installations: SLACK_TOKEN,YOUTUBE_API_KEY,AWS_S3_ID,AWS_S3_SECRET,AWS_S3_REGION,AWS_S3_BUCKET
touch -a .env && set -o allexport; source ./.env; set +o allexport
echo "LOCAL_TMP_DIR=$LOCAL_TMP_DIR"
# Compose settings - docker only
export SLACK_CHANNEL="ytsync-travis"
export LBRY_API_TOKEN="ytsyntoken"
export LBRY_WEB_API="http://localhost:15400"
export LBRYNET_ADDRESS="http://localhost:15100"
export LBRYCRD_STRING="tcp://lbry:lbry@localhost:15200"
export LBRYNET_USE_DOCKER=true
export REFLECT_BLOBS=false
export CLEAN_ON_STARTUP=true
export REGTEST=true
# Local settings
export BLOBS_DIRECTORY="$(pwd)/e2e/blobsfiles"
export LBRYNET_DIR="$(pwd)/e2e/persist/.lbrynet/.local/share/lbry/lbrynet/"
export LBRYNET_WALLETS_DIR="$(pwd)/e2e/persist/.lbrynet/.local/share/lbry/lbryum"
export TMP_DIR="/var/tmp"
export UID

cd ./e2e
docker-compose stop
docker-compose rm -f
echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
docker-compose pull
if [[ -d persist ]]; then rm -rf persist; fi
mkdir  -m 0777 -p ./persist
mkdir -m 777 -p ./persist/.walletserver
mkdir -m 777 -p ./persist/.lbrynet
#sudo chown -Rv 999:999 ./persist/.walletserver
#sudo chown -Rv 1000:1000 ./persist/.lbrynet
docker-compose up -d
printf 'waiting for internal apis'
until curl --output /dev/null --silent --head --fail http://localhost:15400; do
    printf '.'
    sleep 1
done
echo "successfully started..."

#Data Setup for test
./data_setup.sh

# Execute the sync test!
./../bin/ytsync --channelID UCCyr5j8akeu9j4Q7urV0Lqw #Force channel intended...just in case. This channel lines up with the api container
status=$(mysql -u lbry -plbry -ss -D lbry -h "127.0.0.1" -P 15500 -e 'SELECT status FROM youtube_data WHERE id=1')
videoStatus=$(mysql -u lbry -plbry -ss -D lbry -h "127.0.0.1" -P 15500 -e 'SELECT status FROM synced_video WHERE id=1')
videoClaimID=$(mysql -u lbry -plbry -ss -D lbry -h "127.0.0.1" -P 15500 -e 'SELECT claim_id FROM synced_video WHERE id=1')
videoClaimAddress=$(mysql -u lbry -plbry -ss -D chainquery -h "127.0.0.1" -P 15600 -e 'SELECT claim_address FROM claim WHERE id=2')
# Create Supports for published claim
./supporty/supporty @BeamerTest "${videoClaimID}" "${videoClaimAddress}" lbrycrd_regtest 1.0
./supporty/supporty @BeamerTest "${videoClaimID}" "${videoClaimAddress}" lbrycrd_regtest 2.0
./supporty/supporty @BeamerTest "${videoClaimID}" "${videoClaimAddress}" lbrycrd_regtest 3.0
./supporty/supporty @BeamerTest "${videoClaimID}" "${videoClaimAddress}" lbrycrd_regtest 3.0
curl --data-binary '{"jsonrpc":"1.0","id":"curltext","method":"generate","params":[1]}' -H 'content-type:text/plain;' --user lbry:lbry http://localhost:15200
# Reset status for tranfer test
mysql -u lbry -plbry -ss -D lbry -h "127.0.0.1" -P 15500 -e "UPDATE youtube_data SET status = 'queued' WHERE id = 1"
# Trigger transfer api
curl -i -H 'Accept: application/json' -H 'Content-Type: application/json' 'http://localhost:15400/yt/transfer?auth_token=youtubertoken&address=n1Ygra2pyD6cpESv9GtPM9kDkr4bPeu1Dc'
# Execute the transfer test!
./../bin/ytsync --channelID UCCyr5j8akeu9j4Q7urV0Lqw #Force channel intended...just in case. This channel lines up with the api container
# Check that the channel and the video are marked as transferred and that all supports are spent
channelTransferStatus=$(mysql -u lbry -plbry -ss -D lbry -h "127.0.0.1" -P 15500 -e 'SELECT transfer_state FROM youtube_data WHERE id=1')
videoTransferStatus=$(mysql -u lbry -plbry -ss -D lbry -h "127.0.0.1" -P 15500 -e 'SELECT transferred FROM synced_video WHERE id=1')
nrUnspentSupports=$(mysql -u lbry -plbry -ss -D chainquery -h "127.0.0.1" -P 15600 -e 'SELECT COUNT(*) FROM chainquery.support INNER JOIN output ON output.transaction_hash = support.transaction_hash_id AND output.vout = support.vout WHERE output.is_spent = 0')
if [[ $status != "synced" || $videoStatus != "published" || $channelTransferStatus != "2" || $videoTransferStatus != "1" || $nrUnspentSupports != "1" ]]; then
    echo "~~!!!~~~FAILED~~~!!!~~"
    echo "Channel Status: $status"
    echo "Video Status: $videoStatus"
    echo "Channel Transfer Status: $channelTransferStatus"
    echo "Video Transfer Status: $videoTransferStatus"
    echo "Nr Unspent Supports: $nrUnspentSupports"
    #docker-compose logs --tail="all" lbrycrd
    #docker-compose logs --tail="all" walletserver
    #docker-compose logs --tail="all" lbrynet
    #docker-compose logs --tail="all" internalapis
    exit 1;
    else
      echo "SUCCESSSSSSSSSSSSS!"
fi;