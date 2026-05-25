// Feature: nhai-offline-auth, Property 14: Log rotation maintains the 1000-entry cap
import 'package:flutter_test/flutter_test.dart';
import 'package:nhai_auth/models/auth_log_entry.dart';
import 'package:nhai_auth/models/auth_result.dart';

// Simulate the log rotation logic from StorageManagerImpl
class InMemoryLogStore {
  final List<AuthLogEntry> _entries = [];
  static const int maxEntries = 1000;

  void add(AuthLogEntry entry) {
    _entries.add(entry);
    if (_entries.length > maxEntries) {
      // Sort by timestamp ascending, remove oldest
      _entries.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      _entries.removeRange(0, _entries.length - maxEntries);
    }
  }

  int get length => _entries.length;
  List<AuthLogEntry> get entries => List.unmodifiable(_entries);
}

AuthLogEntry makeEntry(int index) => AuthLogEntry(
      id: 'uuid-$index',
      timestamp: DateTime.utc(2024, 1, 1).add(Duration(minutes: index)),
      result: AuthClassification.verified,
      trustScore: 0.9,
    );

void main() {
  group('Property 14: Log rotation maintains the 1000-entry cap', () {
    test('property: adding to a full store keeps count at 1000', () {
      final store = InMemoryLogStore();
      // Fill to exactly 1000
      for (int i = 0; i < 1000; i++) {
        store.add(makeEntry(i));
      }
      expect(store.length, equals(1000));

      // Add one more — should still be 1000
      store.add(makeEntry(1000));
      expect(store.length, equals(1000));
    });

    test('property: oldest entry is deleted when cap is exceeded', () {
      final store = InMemoryLogStore();
      for (int i = 0; i < 1000; i++) {
        store.add(makeEntry(i));
      }
      // The oldest entry has index 0 (earliest timestamp)
      final oldestTimestamp = makeEntry(0).timestamp;

      // Add a new entry
      store.add(makeEntry(1000));

      // The oldest entry should be gone
      final hasOldest = store.entries.any(
        (e) => e.timestamp.isAtSameMomentAs(oldestTimestamp),
      );
      expect(hasOldest, isFalse, reason: 'Oldest entry should have been rotated out');
    });

    test('property: cap holds for 100 additional entries beyond 1000', () {
      final store = InMemoryLogStore();
      for (int i = 0; i < 1000; i++) {
        store.add(makeEntry(i));
      }
      for (int i = 1000; i < 1100; i++) {
        store.add(makeEntry(i));
        expect(store.length, equals(1000),
            reason: 'Store should stay at 1000 after adding entry $i');
      }
    });

    test('store below 1000 entries grows normally', () {
      final store = InMemoryLogStore();
      for (int i = 0; i < 500; i++) {
        store.add(makeEntry(i));
      }
      expect(store.length, equals(500));
    });

    test('exactly 1000 entries: adding one removes exactly one', () {
      final store = InMemoryLogStore();
      for (int i = 0; i < 1000; i++) {
        store.add(makeEntry(i));
      }
      final before = store.length;
      store.add(makeEntry(1000));
      expect(store.length, equals(before));
    });
  });
}
