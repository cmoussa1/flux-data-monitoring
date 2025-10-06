#!/bin/bash

test_description='test fetching jobs of different job states'

. $(dirname $0)/sharness.sh

mkdir -p conf.d

export FLUX_CONF_DIR=$(pwd)
test_under_flux 16 job -o,--config-path=$(pwd)/conf.d

flux setattr log-stderr-level 1

test_expect_success 'allow guest access to testexec' '
	flux config load <<-EOF
	[exec.testexec]
	allow-guests = true
	EOF
'

test_expect_success 'configure flux with queues' '
	cat >conf.d/queues.toml <<-EOT &&
	[queues.pbatch]
	[queues.pdebug]
	[policy.jobspec.defaults.system]
	queue = "pdebug"
	EOT
	flux config reload &&
	flux queue start --all
'

test_expect_success 'submit a 1-node job' '
	job1=$(flux submit -N 1 \
		--setattr=system.bank=bankA \
		--setattr=system.project=project1 \
		--queue=pdebug \
		--setattr=system.duration=3600 \
		hostname)
'

test_expect_success 'submit a job that gets cancelled' '
    job2=$(flux submit -N 2 \
        --setattr=system.bank=bankA \
        --setattr=system.project=project1 \
        --queue=pdebug \
        --setattr=system.duration=3600 \
        sleep 3600) &&
    flux job wait-event -vt 5 ${job2} alloc &&
    flux cancel ${job2} &&
    flux job wait-event -vt 5 ${job2} clean
'

test_expect_success 'run fetch-job-records script' '
	flux account-create-elastic-logs --output-file jobs.ndjson
'

test_expect_success 'check value of .event.outcome for job1 == COMPLETED' '
    test_debug "jq -S . <jobs.ndjson" &&
    jq -e \
        ".job.id == $(flux job id -t dec ${job1})
         and .event.outcome == \"COMPLETED\"" <jobs.ndjson | grep -q true
'

test_expect_success 'check value of .event.outcome for job2 == CANCELLED' '
    test_debug "jq -S . <jobs.ndjson" &&
    jq -e \
        ".job.id == $(flux job id -t dec ${job2})
         and .event.outcome == \"CANCELLED\"" <jobs.ndjson | grep -q true
'

test_expect_success 'remove last_completed timestamp file' '
	rm /var/log/flux/last_completed
'

test_done
