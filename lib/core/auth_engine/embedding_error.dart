enum EmbeddingErrorCode {
  noFaceDetected,
  lowQualityFrame,
  modelInferenceFailed,
}

class EmbeddingError implements Exception {
  final EmbeddingErrorCode code;
  final String message;

  const EmbeddingError(this.code, this.message);

  @override
  String toString() => 'EmbeddingError(${code.name}): $message';
}
