# MobileFaceNet model — REQUIRED, NOT yet present

The application loads a face-embedding model from this directory at:

    assets/models/mobilefacenet.tflite

This `.tflite` binary is **NOT** committed to the repository (it must be obtained
separately — see below). Until it is placed here, enrollment / authentication will
fail with a clear runtime error:

    Model file missing: assets/models/mobilefacenet.tflite

## Required model specification

| Property      | Value                                   |
|---------------|-----------------------------------------|
| Architecture  | MobileFaceNet                           |
| Format        | TensorFlow Lite (`.tflite`)             |
| Input tensor  | `[1, 112, 112, 3]` float32, normalized to `[-1, 1]` |
| Output tensor | `[1, 128]` float32 (L2-comparable embedding) |
| File name     | `mobilefacenet.tflite` (exact)          |

These values are enforced in
`lib/core/auth_engine/tflite_model_runner.dart`
(`kInputSize = 112`, `kEmbeddingDim = 128`).

## Where to obtain it

Pick ONE source and drop the resulting file in this folder as `mobilefacenet.tflite`:

1. **Sci-kit / community MobileFaceNet TFLite releases** — e.g. the widely-used
   `MobileFaceNet.tflite` from sirius-ai/MobileFaceNet_TF or
   the `face_recognition` TFLite conversions on GitHub / Kaggle / HuggingFace.
2. **Convert from a source model** (`.pb` / Keras `.h5`) with the TFLite converter,
   ensuring the input is resized to 112×112×3 and the output is a 128-D embedding.
3. **Your organization's approved model registry**, if NHAI provides a vetted build.

After placing the file, verify:

    flutter clean && flutter pub get && flutter build apk --debug
    unzip -l build/app/outputs/flutter-apk/app-debug.apk | findstr mobilefacenet
