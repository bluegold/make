test: test-golang test-python test-typescript test-ruby

test-golang:
	mkdir -p /tmp/go-build
	cd golang && GOCACHE=/tmp/go-build go test ./...

test-python:
	python3 python/level1/test/test_runner.py
	python3 python/level2/test/test_runner.py
	python3 python/level3/test/test_runner.py

test-typescript:
	echo "no test"

test-ruby:
	ruby ruby/level1/test/test_task_runner.rb
	ruby ruby/level4/test/test_task_runner_unit.rb

evaluate: evaluate-golang evaluate-python evaluate-typescript evaluate-ruby

evaluate-golang:
	mkdir -p /tmp/go-build
	GOCACHE=/tmp/go-build ruby tools/evaluate.rb golang level1

evaluate-python:
	ruby tools/evaluate.rb python level3

evaluate-typescript:
	ruby tools/evaluate.rb typescript level3

evaluate-ruby:
	ruby tools/evaluate.rb ruby level4
