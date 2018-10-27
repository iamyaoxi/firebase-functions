#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status.
set -e

function usage {
  echo "Usage: $0 <project_id>"
  exit 1
}

# The first parameter is required and is the Firebase project id.
if [[ $1 == "" ]]; then
  usage
fi
PROJECT_ID=$1

# Directory where this script lives.
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

function announce {
  echo -e "\n\n##### $1"
}

function build_sdk {
  announce "Building SDK..."
  cd $DIR/..
  rm -f firebase-functions-*.tgz
  npm run build:pack
  mv firebase-functions-*.tgz integration_test/functions/firebase-functions.tgz
}

function pick_node6 {
  cd $DIR
  cp package.node6.json functions/package.json
}

function pick_node8 {
  cd $DIR
  cp package.node8.json functions/package.json
}

function install_deps {
  announce "Installing dependencies..."
  cd $DIR/functions
  rm -rf node_modules/firebase-functions
  npm install
}

function delete_all_functions {
  announce "Deleting all functions in project..."
  cd $DIR
  # Try to delete, if there are errors it is because the project is already empty,
  # in that case do nothing. 
  firebase functions:delete callableTests createUserTests databaseTests deleteUserTests firestoreTests integrationTests pubsubTests remoteConfigTests --project=$PROJECT_ID -f || :
  announce "Project emptied."
}

function deploy {
  cd $DIR
  ./functions/node_modules/.bin/tsc -p functions/
  # Deploy functions, and security rules for database and Firestore
  firebase deploy --project=$PROJECT_ID --only functions,database,firestore
}

function run_tests {
  announce "Running the integration tests..."

  # Construct the URL for the test function. This may change in the future,
  # causing this script to start failing, but currently we don't have a very
  # reliable way of determining the URL dynamically.
  TEST_DOMAIN="cloudfunctions.net"
  if [[ $FIREBASE_FUNCTIONS_URL == "https://preprod-cloudfunctions.sandbox.googleapis.com" ]]; then
    TEST_DOMAIN="txcloud.net"
  fi
  TEST_URL="https://us-central1-$PROJECT_ID.$TEST_DOMAIN/integrationTests"
  echo $TEST_URL

  curl --fail $TEST_URL
}

function cleanup {
  announce "Performing cleanup..."
  delete_all_functions
  rm $DIR/functions/firebase-functions.tgz
  rm $DIR/functions/package.json
  rm -f $DIR/functions/firebase-debug.log
  rm -rf $DIR/functions/node_modules/firebase-functions
}

build_sdk
pick_node8
install_deps
delete_all_functions
announce "Deploying functions to Node 8 runtime ..."
deploy
run_tests
pick_node6
announce "Re-deploying the same functions to Node 6 runtime ..."
deploy
run_tests
cleanup
announce "All tests pass!"
