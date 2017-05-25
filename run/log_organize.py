#!/usr/bin/python3
import json
import sys


def main():
    """Upload test results from STDIN.

    This script expects to be fed results in the following way:
    cat $LOGFILE \
        | ./run/log_organize.py $WPT_REVISION \
            $BROWSER_NAME $BROWSER_VERSION $OS_NAME $OS_VERSION
    """
    results_filename = sys.argv[1]
    print('Results_filename', results_filename)

    results = {}
    subtest_results_by_file = {}

    for line in sys.stdin:
        test_status = json.loads(line)

        if "test" not in test_status:
            continue
        if "status" not in test_status:
            continue
        if test_status["action"] not in ("test_status", "test_end"):
            continue

        test_file = test_status["test"]
        status = test_status["status"]

        if test_file not in results:
            results[test_file] = [0, 1]
        else:
            results[test_file][1] += 1

        if status == 'PASS':
            results[test_file][0] += 1

    with open(results_filename, 'w') as f:
        json.dump(results, f)

    print("Stdin log scan finished.")

if __name__ == '__main__':
    main()
