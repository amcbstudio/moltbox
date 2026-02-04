SHELL := /bin/sh

.PHONY: test demo

test:
	./tests/run.sh

demo:
	PATH=tests/bin:$$PATH MOLTBOOK_API_KEY=demo MOCK_CURL_FIXTURE=fixtures/status.json MOCK_CURL_STATUS=200 bin/molt status
	PATH=tests/bin:$$PATH MOLTBOOK_API_KEY=demo MOCK_CURL_FIXTURE=fixtures/feed.json MOCK_CURL_STATUS=200 bin/molt feed --sort new --limit 3
	PATH=tests/bin:$$PATH MOLTBOOK_API_KEY=demo MOCK_CURL_FIXTURE=fixtures/search.json MOCK_CURL_STATUS=200 bin/molt search --q "molt" --type posts --limit 2
