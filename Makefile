run_test:
	zig build test --summary all -Dtest_filter="vma"

docker_build:
	docker build -t zig-os-test .

docker_test: docker_build
	docker run --rm -v "$(CURDIR)":/workspace -w /workspace zig-os-test \
		zig build test --summary all -Dtest_filter="vma"

