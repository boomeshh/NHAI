class FaceEmbedding {
  final List<double> vector; // exactly 128 float values
  const FaceEmbedding(this.vector);

  Map<String, dynamic> toJson() => {'vector': vector};
  factory FaceEmbedding.fromJson(Map<String, dynamic> json) =>
      FaceEmbedding(List<double>.from(json['vector'] as List));

  @override
  bool operator ==(Object other) =>
      other is FaceEmbedding &&
      vector.length == other.vector.length &&
      List.generate(vector.length, (i) => vector[i] == other.vector[i])
          .every((e) => e);

  @override
  int get hashCode => Object.hashAll(vector);
}
