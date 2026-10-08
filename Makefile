# Each step is a script in scripts/ or bench/; the Makefile only orders them. Env overrides (MODELS, WORK, ...)
# pass straight through, e.g. `make MODELS=/data/models/inkling serve`.
.PHONY: all check image source build weights mtp serve serve-mtp bench clean

all: check image source build weights mtp   ## everything needed to serve both profiles

check:      ; scripts/check-host.sh
image:      ; scripts/build-image.sh
source:     ; scripts/fetch-llama.sh
build:      source ; scripts/build-llama.sh
weights:    ; scripts/download-model.sh
mtp:        source weights ; scripts/make-mtp-gguf.sh
serve:      ; PROFILE=default scripts/serve.sh
serve-mtp:  ; PROFILE=mtp scripts/serve.sh
bench:      ; bench/run-all.sh

clean:      ## removes the llama.cpp checkout/build (not the weights)
	rm -rf work
