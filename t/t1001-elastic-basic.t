#!/bin/bash

test_description='test fetching jobs and creating logs to be ingested by Elastic'

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

test_expect_success 'run fetch-job-records script' '
	flux account-create-elastic-logs --output-file job1.ndjson &&
	cat job1.ndjson | jq
'

# we need to convert the format of the job ID from f58 format to decimal
# format in order to compare it with what format the log stores the job ID in.
test_expect_success 'check event metadata' '
	jq -e ".event.dataset == \"flux.joblog\"" job1.ndjson &&
	jq -e ".job.id == $(flux job id -t dec ${job1})" job1.ndjson
'

test_expect_success 'check job resource counts' '
	jq -e ".job.node.count == 1" <job1.ndjson &&
	jq -e ".job.task.count == 1" <job1.ndjson &&
	jq -e ".job.proc.count == 1" <job1.ndjson &&
	jq -e ".job.requested_duration == 3600" <job1.ndjson
'

test_expect_success 'check job attributes' '
	jq -e ".job.bank == \"bankA\"" <job1.ndjson &&
	jq -e ".job.queue == \"pdebug\"" <job1.ndjson &&
	jq -e ".job.project == \"project1\"" <job1.ndjson
'

test_expect_success 'remove last_completed timestamp file' '
	rm /var/log/flux/last_completed
'

test_done
