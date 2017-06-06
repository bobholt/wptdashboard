set -ex

BROWSER_NAME="chrome"
OS_NAME="debian"
OS_VERSION="8"

# TODO(jeffcarp) install chrome if needed
CHROME_BINARY=/usr/bin/google-chrome-unstable

# TODO(jeffcarp) install chromedriver if needed
CHROMEDRIVER_BINARY=/usr/local/bin/chromedriver

GSUTIL_BINARY=$HOME/google-cloud-sdk/bin/gsutil

# TODO(jeffcarp) install wptrunner if needed
WPTRUNNER_PATH=/usr/local/bin/wptrunner

# TODO(jeffcarp) this should be an argument
WPTD_PATH="$(dirname $(readlink -f $0))/.."
WPTD_PROD_HOST="https://wptdashboard.appspot.com"
WPT_DIR="/home/jeffcarp/build/wpt"
WORKING_DIR=/home/jeffcarp/build

run_some_wpt () {
    RUN_PATH="battery-status"
    $WPTRUNNER_PATH \
        --product=chrome \
        --binary=$CHROME_BINARY \
        --webdriver-binary=$CHROMEDRIVER_BINARY \
        --meta $WPT_DIR \
        --tests $WPT_DIR \
        --log-raw=$LOGFILE \
        --log-mach=- \
        $RUN_PATH
}

run_all_wpt () {
    $WPTRUNNER_PATH \
        --product=chrome \
        --binary=$CHROME_BINARY \
        --webdriver-binary=$CHROMEDRIVER_BINARY \
        --meta $WPT_DIR \
        --tests $WPT_DIR \
        --log-raw=$LOGFILE \
        --log-mach=-
}

get_chrome_version () {
    $CHROME_BINARY --version | grep -ioE " [0-9]{1,3}.[0-9]{1,3}" | grep -ioE "\S+"
}

main () {
    date
    # echo "[WPTD] Starting xvfb"
    # Xvfb :99.0 -screen 0 1024x768x16 &
    echo "[WPTD] ASSUMING XVFB ON DISPLAY 99.0"
    export DISPLAY=:99.0

    BROWSER_VERSION=$(get_chrome_version)

    echo "Platform: $BROWSER_NAME $BROWSER_VERSION $OS_NAME $OS_VERSION"

    (cd $WPT_DIR \
     && git reset --hard HEAD \
     && git checkout master \
     && git pull \
     && git checkout $CURRENT_WPT_SHA \
     && ./manifest --work \
     && git apply $WPTD_PATH/util/keep-wpt-running.patch)
    if [ $? -ne 0 ]; then
        echo "Failed to check out current WPT and generate MANIFEST.json"
        exit 1
    fi

    CURRENT_WPT_SHA=$(cd $WPT_DIR && git rev-parse HEAD)
    SHORT_SHA=$(echo $CURRENT_WPT_SHA | cut -c1-10)
    PLATFORM_ID="$BROWSER_NAME-$BROWSER_VERSION-$OS_NAME-$OS_VERSION"
    GS_FILEPATH="gs://wptdashboard.appspot.com/results/$SHORT_SHA/$PLATFORM_ID.json"
    GS_GZ_FILEPATH="gs://wptdashboard.appspot.com/results/$SHORT_SHA/$PLATFORM_ID.json.gz"

    $GSUTIL_BINARY stat $GS_FILEPATH && echo "Results file already exists. Stopping.\nPath: $GS_FILEPATH" \
        exit 1

    echo "[WPTD] Installing wptrunner"
    (cd $WPT_DIR/tools/wptrunner && pip install --user -e .)

    LOGFILE="$WORKING_DIR/wptd-${SHORT_SHA}-$PLATFORM_ID.log"

    echo "[WPTD] Running WPT"

    # Using || to prevent script from stopping due to set -e
    # run_some_wpt || echo "[WPTD] Run finished"
    run_all_wpt || echo "[WPTD] Run finished"

    NUM_TEST_STATUSES=$(cat $LOGFILE | grep "test_status" | wc -l)
    echo "[WPTD] Number of sub-test results: $NUM_TEST_STATUSES"

    if [ $NUM_TEST_STATUSES -eq 0 ]; then
        echo "[WPTD] Something went wrong. 0 test_statuses. Exiting."
        exit 1
    fi

    echo "[WPTD] Test run finished. Uploading results."

    # ! From here we're assuming we've run the entire test set
    RESULTS_FILENAME="$WORKING_DIR/results-$SHORT_SHA-$PLATFORM_ID.json"
    cat $LOGFILE | $WPTD_PATH/run/log_organize.py $RESULTS_FILENAME
    $GSUTIL_BINARY cp -z json -a public-read $RESULTS_FILENAME $GS_GZ_FILEPATH

    HTTP_RESULTS_URL="https://storage.googleapis.com/wptdashboard.appspot.com/results/$SHORT_SHA/$PLATFORM_ID.json.gz"
    echo "[WPTD] Results available: $HTTP_RESULTS_URL"


    echo "[WPTD] Creating TestRun..."
    curl \
        -X POST  \
        $WPTD_PROD_HOST/test-runs \
        -d "{
            \"browser_name\": \"$BROWSER_NAME\",
            \"browser_version\": \"$BROWSER_VERSION\",
            \"os_name\": \"$OS_NAME\",
            \"os_version\": \"$OS_VERSION\",
            \"revision\": \"$SHORT_SHA\",
            \"results_url\": \"$HTTP_RESULTS_URL\"
        }"
    echo "\n[WPTD] TestRun created."
}

main "$@"
