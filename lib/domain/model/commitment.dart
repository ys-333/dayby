import 'package:freezed_annotation/freezed_annotation.dart';

import '../time/civil_date.dart';

part 'commitment.freezed.dart';

/// Lifecycle of a commitment. Archiving never deletes history — an archived
/// commitment keeps every event and every past number it produced.
enum CommitmentState { active, paused, archived }

@freezed
abstract class Commitment with _$Commitment {
  const factory Commitment({
    required String id,
    required String name,
    required CivilDate startedOn,
    String? description,
    String? icon,
    String? categoryId,
    @Default(CommitmentState.active) CommitmentState state,
    CivilDate? archivedOn,
  }) = _Commitment;
}
