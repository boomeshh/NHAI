import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/ui/screens/face_detection_validation_screen.dart';

FaceDetectionSample _good({int faceCount = 1}) => FaceDetectionSample(
      faceCount: faceCount,
      brightness: 140,
      sharpness: 60,
      boxLeft: 140,
      boxTop: 190,
      boxWidth: 200,
      boxHeight: 260,
      frameWidth: 480,
      frameHeight: 640,
      yaw: 0,
      pitch: 0,
      roll: 0,
      leftEyeOpen: 0.95,
      rightEyeOpen: 0.95,
      hasLeftEye: true,
      hasRightEye: true,
      hasNose: true,
      hasMouthLeft: true,
      hasMouthRight: true,
    );

FaceDetectionSample _dark() => const FaceDetectionSample(
      faceCount: 1,
      brightness: 20,
      sharpness: 60,
      boxLeft: 140,
      boxTop: 190,
      boxWidth: 200,
      boxHeight: 260,
      frameWidth: 480,
      frameHeight: 640,
      yaw: 0,
      pitch: 0,
      roll: 0,
      leftEyeOpen: 0.95,
      rightEyeOpen: 0.95,
      hasLeftEye: true,
      hasRightEye: true,
      hasNose: true,
      hasMouthLeft: true,
      hasMouthRight: true,
    );

Widget _host(StreamController<FaceDetectionSample> c) => MaterialApp(
      home: FaceDetectionValidationScreen(sampleProvider: () => c.stream),
    );

void main() {
  testWidgets('renders the dashboard scaffold', (tester) async {
    final c = StreamController<FaceDetectionSample>();
    addTearDown(c.close);
    await tester.pumpWidget(_host(c));
    expect(find.byKey(const Key('face_detection_validation_screen')),
        findsOneWidget);
    expect(find.byKey(const Key('detection_status_banner')), findsOneWidget);
  });

  testWidgets('a good frame shows ACCEPTED with a high score', (tester) async {
    final c = StreamController<FaceDetectionSample>();
    addTearDown(c.close);
    await tester.pumpWidget(_host(c));

    c.add(_good());
    await tester.pump();

    expect(find.text('ACCEPTED'), findsOneWidget);
    expect(find.text('Face Count'), findsOneWidget);
    expect(find.text('FPS'), findsOneWidget);
  });

  testWidgets('a dark frame shows REJECTED with the reason', (tester) async {
    final c = StreamController<FaceDetectionSample>();
    addTearDown(c.close);
    await tester.pumpWidget(_host(c));

    c.add(_dark());
    await tester.pump();

    expect(find.text('REJECTED'), findsOneWidget);
    expect(find.text('Move to a brighter area'), findsOneWidget);
  });

  testWidgets('multiple faces are rejected', (tester) async {
    final c = StreamController<FaceDetectionSample>();
    addTearDown(c.close);
    await tester.pumpWidget(_host(c));

    c.add(_good(faceCount: 2));
    await tester.pump();

    expect(find.text('REJECTED'), findsOneWidget);
    expect(find.text('Multiple faces in frame'), findsOneWidget);
  });
}
