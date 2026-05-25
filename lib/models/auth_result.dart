enum AuthClassification { verified, failed }

class AuthResult {
  final AuthClassification classification;
  final double trustScore; // 0.0–1.0 cosine similarity
  final String? matchedEmployeeId; // null if FAILED
  final String? failureReason; // null if VERIFIED

  const AuthResult({
    required this.classification,
    required this.trustScore,
    this.matchedEmployeeId,
    this.failureReason,
  });
}
