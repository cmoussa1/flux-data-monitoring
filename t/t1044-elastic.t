#!/bin/bash

test_description='test fetching jobs and updating the fair share values for a group of users'

. $(dirname $0)/sharness.sh

DB_PATH=$(pwd)/FluxAccountingTest.db

export FLUX_CONF_DIR=$(pwd)
test_under_flux 16 job

flux setattr log-stderr-level 1

test_expect_success 'create flux-accounting DB' '
	flux account -p $(pwd)/FluxAccountingTest.db create-db
'

test_expect_success 'start flux-accounting service' '
	flux account-service -p ${DB_PATH} -t
'

test_expect_success 'add some banks to the DB' '
	flux account add-bank root 1 &&
	flux account add-bank --parent-bank=root bankA 1
'

test_expect_success 'add some users to the DB' '
	username=$(whoami) &&
	uid=$(id -u) &&
	flux account add-user \
		--username=$username \
		--userid=$uid \
		--bank=bankA \
		--shares=1
'

test_expect_success 'submit some jobs' '
	jobid1=$(flux submit -N 1 --setattr=system.bank=bankA hostname) &&
	jobid2=$(flux submit -N 1 --setattr=system.bank=bankA hostname) &&
	jobid3=$(flux submit -N 2 --setattr=system.bank=bankA hostname) &&
	jobid4=$(flux submit -N 1 --setattr=system.bank=bankA hostname)
'

test_expect_success 'submit some sleep 1 jobs under one user' '
	jobid1=$(flux submit -N 1 --setattr=system.bank=bankA sleep 1) &&
	jobid2=$(flux submit -N 1 --setattr=system.bank=bankA sleep 1) &&
	jobid3=$(flux submit -n 2 -N 2 --setattr=system.bank=bankA sleep 1)
'

test_expect_success 'submit a job that gets canceled' '
	jobid4=$(flux submit -N 1 --setattr=system.bank=bankA sleep 60) &&
	flux cancel ${jobid4} &&
	flux job wait-event -vt 3 ${jobid4} clean
	flux job info ${jobid4} eventlog
'

test_expect_success 'run fetch-job-records script' '
	flux account-create-elastic-logs --output-file last_completed
'

# test_expect_success 'fail on purpose' '
# 	test 1 -eq 0
# '

test_expect_success 'remove flux-accounting DB' '
	rm $(pwd)/FluxAccountingTest.db
'

test_expect_success 'shut down flux-accounting service' '
	flux python -c "import flux; flux.Flux().rpc(\"accounting.shutdown_service\").get()"
'

test_done
