import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notifications plugin
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');
  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: DarwinInitializationSettings(),
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  runApp(CrowdSenseApp(notificationsPlugin: flutterLocalNotificationsPlugin));
}

class CrowdSenseApp extends StatelessWidget {
  final FlutterLocalNotificationsPlugin notificationsPlugin;

  const CrowdSenseApp({Key? key, required this.notificationsPlugin}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CrowdSense',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: HomePage(notificationsPlugin: notificationsPlugin),
      debugShowCheckedModeBanner: false,
    );
  }
}

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

class HomePage extends StatefulWidget {
  final FlutterLocalNotificationsPlugin notificationsPlugin;

  const HomePage({Key? key, required this.notificationsPlugin}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  CrowdData? _crowdData;
  List<String> _notifications = [];
  bool _isLoading = true; // Only true for initial load
  bool _isRefreshing = false; // Track background refresh state
  int _currentTabIndex = 0;
  late TabController _tabController;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchData(isInitialLoad: true);

    // Set up periodic data refresh
    _refreshTimer = Timer.periodic(Duration(seconds: 2), (timer) => _fetchData(isInitialLoad: false));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchData({required bool isInitialLoad}) async {
    // Only show loading indicator on initial load
    if (isInitialLoad) {
      setState(() {
        _isLoading = true;
      });
    } else {
      // For subsequent refreshes, don't show loading state
      _isRefreshing = true;
    }

    try {
      final response = await http.get(Uri.parse('http://192.168.1.40:5000/zone_data'));

      if (response.statusCode == 200) {
        // Decode the JSON response
        final jsonData = json.decode(response.body);

        final previousData = _crowdData;
        final newData = CrowdData.fromJson(jsonData);

        // Check for significant changes
        if (previousData != null) {
          for (final zoneId in newData.zones.keys) {
            final newZone = newData.zones[zoneId]!;
            final previousZone = previousData.zones[zoneId];

            if (previousZone != null &&
                previousZone.density != newZone.density &&
                newZone.density.toLowerCase() == 'high') {
              _addNotification('Zone $zoneId is now ${newZone.density}!');
              _showNotification('Zone $zoneId Alert', 'Zone $zoneId is now ${newZone.density}!');
            }
          }
        }

        // Update state with new data
        if (mounted) {
          setState(() {
            _crowdData = newData;
            _isLoading = false;
            _isRefreshing = false;
          });
        }
      } else {
        throw Exception('Failed to load data: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });

        // Only show error message if it's the initial load or a manual refresh
        if (isInitialLoad || !_isRefreshing) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to fetch data: $e')),
          );
        }
      }
    }
  }

  void _addNotification(String message) {
    setState(() {
      _notifications.add('${DateTime.now().toString().substring(11, 19)}: $message');
    });
  }

  Future<void> _showNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'crowd_sense_channel',
      'CrowdSense Alerts',  
      channelDescription: 'Alerts about crowd density changes',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await widget.notificationsPlugin.show(
      0,
      title,
      body,
      platformDetails,
    );
  }

  String _getRecommendation() {
    if (_crowdData == null) return '';

    // Find the most crowded zone
    String? mostCrowdedZone;
    int maxCount = 0;

    // Find the least crowded zone
    String? leastCrowdedZone;
    int minCount = double.maxFinite.toInt();

    _crowdData!.zones.forEach((zoneId, data) {
      if (data.count > maxCount) {
        maxCount = data.count;
        mostCrowdedZone = zoneId;
      }
      if (data.count < minCount) {
        minCount = data.count;
        leastCrowdedZone = zoneId;
      }
    });

    if (mostCrowdedZone != null && leastCrowdedZone != null && mostCrowdedZone != leastCrowdedZone) {
      final maxZone = _crowdData!.zones[mostCrowdedZone]!;
      if (maxZone.density.toLowerCase() == 'high') {
        return 'Redirect people from Zone $mostCrowdedZone to Zone $leastCrowdedZone for safety';
      }
    }

    return _crowdData!.recommendations.isNotEmpty
        ? _crowdData!.recommendations.first
        : 'Monitor crowd distribution';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.people_alt, size: 24),
            SizedBox(width: 8),
            Text('CrowdSense'),
          ],
        ),
        actions: [
          // Add refresh indicator that shows when refreshing
          _isRefreshing
              ? Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          )
              : IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () => _fetchData(isInitialLoad: false),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(icon: Icon(Icons.dashboard), text: 'Dashboard'),
            Tab(icon: Icon(Icons.map), text: 'Zones'),
            Tab(icon: Icon(Icons.notifications), text: 'Alerts'),
          ],
          onTap: (index) {
            setState(() {
              _currentTabIndex = index;
            });
          },
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          _buildDashboardTab(),
          _buildZonesTab(),
          _buildAlertsTab(),
        ],
      ),
    );
  }

  Widget _buildDashboardTab() {
    if (_crowdData == null) {
      return Center(child: Text('No data available'));
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total people count
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total People',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.people, size: 32),
                      SizedBox(width: 16),
                      Text(
                        '${_crowdData!.totalPeople}',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 16),

          // Recommendation
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recommendation',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    _getRecommendation(),
                    style: TextStyle(
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 16),

          // Zone summary
          Text(
            'Zone Status',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: _crowdData!.zones.length,
              itemBuilder: (context, index) {
                final zoneId = _crowdData!.zones.keys.elementAt(index);
                final zoneData = _crowdData!.zones[zoneId]!;

                return Card(
                  margin: EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: zoneData.displayColor,
                      child: Text(
                        zoneId,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text('Zone $zoneId'),
                    subtitle: Text('${zoneData.count} people · ${zoneData.density} density'),
                    trailing: Icon(
                      zoneData.statusIcon,
                      color: zoneData.density == 'high'
                          ? Colors.red
                          : zoneData.density == 'medium'
                          ? Colors.orange
                          : Colors.green,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZonesTab() {
    if (_crowdData == null) {
      return Center(child: Text('No zone data available'));
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _crowdData!.zones.length,
              itemBuilder: (context, index) {
                final zoneId = _crowdData!.zones.keys.elementAt(index);
                final zoneData = _crowdData!.zones[zoneId]!;

                return Card(
                  margin: EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: zoneData.displayColor,
                      child: Text(
                        zoneId,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text('Zone $zoneId'),
                    subtitle: Text('${zoneData.count} people · ${zoneData.density} density'),
                    trailing: Icon(
                      zoneData.statusIcon,
                      color: zoneData.density == 'high'
                          ? Colors.red
                          : zoneData.density == 'medium'
                          ? Colors.orange
                          : Colors.green,
                    ),
                  ),
                );
                
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getZoneRecommendation(String zoneId) {
    if (_crowdData == null) return '';

    final zoneData = _crowdData!.zones[zoneId]!;

    if (zoneData.density.toLowerCase() == 'high') {
      // Find the least crowded zone
      String? leastCrowdedZone;
      int minCount = double.maxFinite.toInt();

      _crowdData!.zones.forEach((id, data) {
        if (id != zoneId && data.count < minCount) {
          minCount = data.count;
          leastCrowdedZone = id;
        }
      });

      if (leastCrowdedZone != null) {
        return 'Move people from Zone $zoneId to Zone $leastCrowdedZone';
      } else {
        return 'Reduce crowd in Zone $zoneId';
      }
    } else if (zoneData.density.toLowerCase() == 'medium') {
      return 'Monitor crowd in Zone $zoneId';
    } else {
      // Low density
      return 'Zone $zoneId can accept more people';
    }
  }

  Widget _buildAlertsTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Alerts & Notifications',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: _notifications.isNotEmpty
                    ? () => setState(() => _notifications = [])
                    : null,
                child: Text('Clear All'),
              ),
            ],
          ),
          SizedBox(height: 8),
          Expanded(
            child: _notifications.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No alerts yet',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              itemCount: _notifications.length,
              itemBuilder: (context, index) {
                final notification = _notifications[_notifications.length - 1 - index];
                return Card(
                  margin: EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(Icons.notification_important),
                    title: Text(notification),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}