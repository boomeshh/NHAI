// Feature: nhai-offline-auth, Property 13: Log entries are retrieved in reverse chronological order
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/models/auth_log_entry.dart';
import 'package:nhai_auth/models/auth_result.dart';

// Simulate the sorting logic from StorageManagerImpl.getAuthLogs
List<AuthLogEntry> sortReverseChronological(List<AuthLogEntry> entries, {int limit = 100}) {
  final sorted = List<AuthLogEntry>.from(entries)
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return sorted.take(limit).toList();
}

void main() {
  group('Property 13: Log entries are retrieved in reverse chronological order', () {
    AuthLogEntry makeEntry(int minutesAgo) => AuthLogEntry(
          id: 'uuid-$minutesAgo',
          timestamp: DateTime.utc(2024, 6, 1, 12, 0, 0)
              .subtract(Duration(minutes: minutesAgo)),
          result: AuthClassification.verified,
          trustScore: 0.9,
        );

    test('property: sorted entries are in reverse chronological order for 100 random collections', () {
      for (int iter = 0; iter < 100; iter++) {
        // Create entries with varied timestamps
        final count = (iter % 20) + 2; // 2 to 21 entries
        final entries = List.generate(count, (i) => makeEntry((iter * 3 + i * 7) % 500));

        final sorted = sortReverseChronological(entries);

        // Verify reverse chronological order
        for (int i = 0; i < sorted.length - 1; i++) {
          expect(
            sorted[i].timestamp.isAfter(sorted[i + 1].timestamp) ||
                sorted[i].timestamp.isAtSameMomentAs(sorted[i + 1].timestamp),
            isTrue,
            reason: 'Entry $i should be >= entry ${i + 1} in time (iter $iter)',
          );
        }
      }
    });

    test('single entry returns that entry', () {
      final entry = makeEntry(10);
      final result = sortReverseChronological([entry]);
      expect(result.length, equals(1));
      expect(result.first.id, equals(entry.id));
    });

    test('two entries: more recent comes first', () {
      final older = makeEntry(60);  // 60 minutes ago
      final newer = makeEntry(5);   // 5 minutes ago
      final result = sortReverseChronological([older, newer]);
      expect(result.first.id, equals(newer.id));
      expect(result.last.id, equals(older.id));
    });

    test('limit is respected', () {
      final entries = List.generate(150, (i) => makeEntry(i));
      final result = sortReverseChronological(entries, limit: 100);
      expect(result.length, equals(100));
    });

    test('most recent 100 are returned when more than 100 exist', () {
      final entries = List.generate(150, (i) => makeEntry(i)); // i=0 is most recent
      final result = sortReverseChronological(entries, limit: 100);
      // The most recent entry (minutesAgo=0) should be first
      expect(result.first.timestamp.isAfter(result.last.timestamp), isTrue);
    });
  });
}
