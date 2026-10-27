import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/services/native_v553_reroll_xp.dart';

void main() {
  NativeV553RerollXpResult project({
    required List<NativeV553Recommendation> history,
    required List<NativeV553DraftEntry> entries,
    bool itemized = false,
    bool enabled = true,
  }) {
    return NativeV553RerollXp.project(
      recommendationHistory: history,
      respectedSlotLimit: 1,
      draftEntries: entries,
      itemized: itemized,
      library: const [
        NativeV553LibraryTitle(id: 'reroll-a', categoryId: 'anime'),
        NativeV553LibraryTitle(id: 'reroll-b', categoryId: 'anime'),
        NativeV553LibraryTitle(id: 'initial', categoryId: 'anime'),
      ],
      categories: const {
        'anime': NativeV553Category(id: 'anime', unit: 'episodes'),
      },
      settings: NativeV553LevelingSettings(
        enabled: enabled,
        unitXp: const {'episodes': 10, 'chapters': 3, 'movies': 30},
      ),
      base: const NativeV553BaseProjection(
        eligible: true,
        total: 100,
        dayMultiplier: 1.5,
        categories: [
          NativeV553XpCategoryRow(
            id: 'anime',
            rotation: 1.2,
            consumption: 40,
            respect: 0,
          ),
        ],
      ),
    );
  }

  const history = [
    NativeV553Recommendation(libraryId: 'initial', title: 'Initial recommendation'),
    NativeV553Recommendation(libraryId: 'reroll-a', title: 'Reroll A'),
    NativeV553Recommendation(libraryId: 'reroll-b', title: 'Reroll B'),
  ];

  test('matches v553 per-unit XP, category rotation and day-streak rounding', () {
    final result = project(
      history: history,
      entries: const [
        NativeV553DraftEntry(
          libraryId: 'reroll-a',
          title: 'Reroll A',
          quantity: 3,
        ),
      ],
    );

    expect(result.units, 3);
    expect(result.baseXp, 30);
    expect(result.rotationXp, 6);
    expect(result.streakXp, 18);
    expect(result.awardXp, 54);
    expect(result.totalXp, 154);
    expect(result.titles, ['Reroll A']);
  });

  test('does not award reroll XP for the initial recommendation', () {
    final result = project(
      history: history,
      entries: const [
        NativeV553DraftEntry(
          libraryId: 'initial',
          title: 'Initial recommendation',
          quantity: 5,
        ),
      ],
    );

    expect(result.units, 0);
    expect(result.awardXp, 0);
    expect(result.totalXp, 100);
  });

  test('itemized mode counts actual unit records instead of draft quantity', () {
    final result = project(
      history: history,
      itemized: true,
      entries: const [
        NativeV553DraftEntry(
          libraryId: 'reroll-b',
          title: 'Reroll B',
          quantity: 99,
          itemizedUnits: [
            {'number': 1},
            {'number': 2},
          ],
        ),
      ],
    );

    expect(result.units, 2);
    expect(result.baseXp, 20);
    expect(result.rotationXp, 4);
    expect(result.streakXp, 12);
    expect(result.awardXp, 36);
    expect(result.totalXp, 136);
  });

  test('respects disabled leveling and ineligible base previews', () {
    final disabled = project(
      history: history,
      enabled: false,
      entries: const [
        NativeV553DraftEntry(
          libraryId: 'reroll-a',
          title: 'Reroll A',
          quantity: 3,
        ),
      ],
    );
    expect(disabled.awardXp, 0);

    final ineligible = NativeV553RerollXp.project(
      recommendationHistory: history,
      respectedSlotLimit: 1,
      draftEntries: const [
        NativeV553DraftEntry(libraryId: 'reroll-a', title: 'Reroll A', quantity: 3),
      ],
      itemized: false,
      library: const [NativeV553LibraryTitle(id: 'reroll-a', categoryId: 'anime')],
      categories: const {'anime': NativeV553Category(id: 'anime', unit: 'episodes')},
      settings: const NativeV553LevelingSettings(enabled: true, unitXp: {'episodes': 10}),
      base: const NativeV553BaseProjection(
        eligible: false,
        total: 100,
        dayMultiplier: 1.5,
        categories: [],
      ),
    );
    expect(ineligible.awardXp, 0);
    expect(ineligible.totalXp, 100);
  });
}
