import 'package:json_annotation/json_annotation.dart';

import '../../domain/entities/dashboard_aggregate.dart';

part 'dashboard_aggregate_dto.g.dart';

/// `dashboard.aggregate.get`'s own `data.totals.sources`/
/// `data.buckets[].sources` shape (`openapi.yaml:1582-1688`) — decoded in
/// full even though [DashboardAggregate] (the domain entity this DTO maps
/// into) never reads a single one of these fields, same "mirror the full
/// contract" precedent `ExportJobStatusDto` already sets for its own
/// unused fields.
@JsonSerializable()
class DashboardSourcesDto {
  const DashboardSourcesDto({
    required this.manual,
    required this.audio,
    required this.photo,
    required this.chat,
  });

  final int manual;
  final int audio;
  final int photo;
  final int chat;

  factory DashboardSourcesDto.fromJson(Map<String, dynamic> json) =>
      _$DashboardSourcesDtoFromJson(json);

  Map<String, dynamic> toJson() => _$DashboardSourcesDtoToJson(this);
}

/// One `data.buckets[]` entry.
@JsonSerializable(explicitToJson: true)
class DashboardBucketDto {
  const DashboardBucketDto({
    required this.date,
    required this.count,
    required this.sources,
  });

  final String date;
  final int count;
  final DashboardSourcesDto sources;

  factory DashboardBucketDto.fromJson(Map<String, dynamic> json) =>
      _$DashboardBucketDtoFromJson(json);

  Map<String, dynamic> toJson() => _$DashboardBucketDtoToJson(this);
}

/// `data.totals`.
@JsonSerializable(explicitToJson: true)
class DashboardTotalsDto {
  const DashboardTotalsDto({required this.count, required this.sources});

  final int count;
  final DashboardSourcesDto sources;

  factory DashboardTotalsDto.fromJson(Map<String, dynamic> json) =>
      _$DashboardTotalsDtoFromJson(json);

  Map<String, dynamic> toJson() => _$DashboardTotalsDtoToJson(this);
}

/// `dashboard.aggregate.get`'s own response `data` (`openapi.yaml:1582-
/// 1688`) — decodes every field the contract declares (Code Map: "mirrors
/// the full contract... same precedent as `ExportJobStatusDto`"), even
/// though [toDomain] only ever reads `totals.count` and each bucket's own
/// `count`.
@JsonSerializable(explicitToJson: true)
class DashboardAggregateDto {
  const DashboardAggregateDto({required this.buckets, required this.totals});

  final List<DashboardBucketDto> buckets;
  final DashboardTotalsDto totals;

  factory DashboardAggregateDto.fromJson(Map<String, dynamic> json) =>
      _$DashboardAggregateDtoFromJson(json);

  Map<String, dynamic> toJson() => _$DashboardAggregateDtoToJson(this);

  /// Code Map: domain `DashboardAggregate` exposes only `totalCount`/
  /// `bucketCounts` — [buckets]' own order is preserved verbatim (the
  /// backend's own chronological order), since `DashboardChartSection`'s
  /// condensation logic depends on it.
  DashboardAggregate toDomain() => DashboardAggregate(
    totalCount: totals.count,
    bucketCounts: buckets.map((bucket) => bucket.count).toList(),
  );
}
