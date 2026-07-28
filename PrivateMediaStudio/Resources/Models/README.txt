This folder holds the bundled whisper.cpp ggml model (ggml-base.en.bin by
default). The .github/workflows/ios-ci.yml pipeline downloads it here before
every build, so it's not committed to git (see .gitignore).

To change model size/language coverage, edit WHISPER_MODEL in the CI workflow
and the default modelName parameter in Captions/WhisperEngine.swift. Larger
models (small, medium) transcribe more accurately but take longer and use more
memory — base.en is a reasonable default for on-device use.
