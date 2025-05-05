import 'package:flutter/material.dart';

class CrowdData {
  final List<String> recommendations;
  final int totalPeople;
  final Map<String, ZoneData> zones;

  CrowdData({
    required this.recommendations,
    required this.totalPeople,
    required this.zones,
  });

  factory CrowdData.fromJson(Map<String, dynamic> json) {
    Map<String, ZoneData> zoneMap = {};

    (json['zones'] as Map<String, dynamic>).forEach((key, value) {
      zoneMap[key] = ZoneData.fromJson(value);
    });

    return CrowdData(
      recommendations: List<String>.from(json['recommendations']),
      totalPeople: json['total_people'],
      zones: zoneMap,
    );
  }
}

class ZoneData {
  final List<int> color;
  final List<double> coords;
  final int count;
  final String density;

  ZoneData({
    required this.color,
    required this.coords,
    required this.count,
    required this.density,
  });

  factory ZoneData.fromJson(Map<String, dynamic> json) {
    return ZoneData(
      color: List<int>.from(json['color']),
      coords: List<double>.from(json['coords']),
      count: json['count'],
      density: json['density'],
    );
  }

  Color get displayColor => Color.fromRGBO(color[0], color[1], color[2], 1.0);

  String get status {
    switch (density.toLowerCase()) {
      case 'low':
        return 'Safe';
      case 'medium':
        return 'Caution';
      case 'high':
        return 'Warning';
      default:
        return 'Unknown';
    }
  }

  IconData get statusIcon {
    switch (density.toLowerCase()) {
      case 'low':
        return Icons.check_circle;
      case 'medium':
        return Icons.warning;
      case 'high':
        return Icons.error;
      default:
        return Icons.help;
    }
  }
}
