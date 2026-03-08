import 'dart:async';
import 'dart:math';

import 'package:duration/duration.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart'
    hide TileLayer, Theme;
import 'services/logger.dart';
import 'pages/log_page.dart';

void main() async {
  AppLogger.info('Uber Clone App starting...', tag: 'MAIN');

  try {
    AppLogger.info('Initializing Supabase...', tag: 'MAIN');
    await Supabase.initialize(
      url: 'https://ktrvyfoystnlhkptqkkn.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt0cnZ5Zm95c3RubGhrcHRxa2tuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI5NTYwMzEsImV4cCI6MjA4ODUzMjAzMX0.ECXICfr5Ft7oPtV4n9xMf5eHbufJQa7ap2ahsghv69s',
    );
    AppLogger.logSupabaseOperation('Supabase initialization', success: true);
  } catch (e, stackTrace) {
    AppLogger.logSupabaseOperation('Supabase initialization',
        success: false, error: e.toString());
    AppLogger.error('Failed to initialize Supabase',
        tag: 'MAIN', error: e, stackTrace: stackTrace);
  }

  AppLogger.info('Starting app...', tag: 'MAIN');
  runApp(const MainApp());
}

final supabase = Supabase.instance.client;

const String _protoMapsApiKey = '304ade3415cb29f6';

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: UberCloneMainScreen()),
    );
  }
}

enum AppState {
  choosingLocation,
  confirmingFare,
  waitingForPickup,
  riding,
  postRide,
}

enum RideStatus { picking_up, riding, completed }

class Ride {
  final String id;
  final String driverId;
  final String passengerId;
  final int fare;
  final RideStatus status;

  Ride({
    required this.id,
    required this.driverId,
    required this.passengerId,
    required this.fare,
    required this.status,
  });

  factory Ride.fromJson(Map<String, dynamic> json) {
    return Ride(
      id: json['id'],
      driverId: json['driver_id'],
      passengerId: json['passenger_id'],
      fare: json['fare'],
      status: RideStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
      ),
    );
  }
}

class Driver {
  final String id;
  final String model;
  final String number;
  final bool isAvailable;
  final LatLng location;

  Driver({
    required this.id,
    required this.model,
    required this.number,
    required this.isAvailable,
    required this.location,
  });

  factory Driver.fromJson(Map<String, dynamic> json) {
    return Driver(
      id: json['id'],
      model: json['model'],
      number: json['number'],
      isAvailable: json['is_available'],
      location: LatLng(json['latitude'], json['longitude']),
    );
  }
}

class UberCloneMainScreen extends StatefulWidget {
  const UberCloneMainScreen({super.key});

  @override
  UberCloneMainScreenState createState() => UberCloneMainScreenState();
}

class UberCloneMainScreenState extends State<UberCloneMainScreen> {
  AppState _appState = AppState.choosingLocation;
  MapController _mapController = MapController();
  LatLng _initialCenter = const LatLng(37.7749, -122.4194);
  double _initialZoom = 14.0;

  LatLng? _selectedDestination;
  LatLng? _currentLocation;
  final List<Polyline> _polylines = [];
  final List<Marker> _markers = [];

  /// Fare in cents
  int? _fare;
  StreamSubscription<dynamic>? _driverSubscription;
  StreamSubscription<dynamic>? _rideSubscription;
  Driver? _driver;

  LatLng? _previousDriverLocation;
  // BitmapDescriptor? _pinIcon;
  // BitmapDescriptor? _carIcon;

  // Vector tiles style
  Style? _vectorStyle;
  bool _styleLoading = true;
  String? _vectorError;
  bool _useOpenStreetMapFallback = false;

  @override
  void initState() {
    super.initState();
    AppLogger.info('Initializing UberCloneMainScreen', tag: 'UI');

    _signInIfNotSignedIn();
    _checkLocationPermission();
    _loadIcons();
    _loadVectorStyle();

    AppLogger.info('UberCloneMainScreen initialization complete', tag: 'UI');
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    super.dispose();
  }

  Future<void> _signInIfNotSignedIn() async {
    AppLogger.info('Checking authentication status...', tag: 'AUTH');

    if (supabase.auth.currentSession == null) {
      try {
        AppLogger.info('No active session, signing in anonymously...',
            tag: 'AUTH');
        await supabase.auth.signInAnonymously();
        AppLogger.logSupabaseOperation('Anonymous sign-in', success: true);
        AppLogger.info('Successfully signed in anonymously', tag: 'AUTH');
      } catch (e) {
        AppLogger.logSupabaseOperation('Anonymous sign-in',
            success: false, error: e.toString());
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
        }
      }
    } else {
      AppLogger.info('User already authenticated', tag: 'AUTH');
    }
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return _askForLocationPermission();
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return _askForLocationPermission();
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      return _askForLocationPermission();
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    _getCurrentLocation();
  }

  /// Shows a modal to ask for location permission.
  Future<void> _askForLocationPermission() async {
    return showDialog(
      barrierDismissible: false,
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Location Permission'),
          content: const Text(
            'This app needs location permission to work properly.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                SystemChannels.platform.invokeMethod('SystemNavigator.pop');
              },
              child: const Text('Close App'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await Geolocator.openLocationSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _getCurrentLocation() async {
    AppLogger.info('Getting current location...', tag: 'LOCATION');

    try {
      Position position = await Geolocator.getCurrentPosition();
      AppLogger.logLocationOperation('Get current location',
          success: true,
          data: {
            'latitude': position.latitude,
            'longitude': position.longitude,
            'accuracy': position.accuracy,
          });

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _initialCenter = _currentLocation!;
        _initialZoom = 14.0;
      });
      _mapController.move(_initialCenter, _initialZoom);

      AppLogger.info('Location set successfully', tag: 'LOCATION');
    } catch (e) {
      AppLogger.logLocationOperation('Get current location',
          success: false, error: e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error occured while getting the current location'),
          ),
        );
      }
    }
  }

  /// Loads the icon images used for markers
  Future<void> _loadIcons() async {
    // Commented out as we're using flutter_map markers instead
    // const imageConfiguration = ImageConfiguration(size: Size(48, 48));
    // _pinIcon = await BitmapDescriptor.asset(
    //   imageConfiguration,
    //   'assets/images/pin.png',
    // );
    // _carIcon = await BitmapDescriptor.asset(
    //   imageConfiguration,
    //   'assets/images/car.png',
    // );
  }

  Future<void> _loadVectorStyle() async {
    AppLogger.info('Loading vector map style...', tag: 'MAP');

    try {
      final reader = StyleReader(
        uri:
            'https://api.protomaps.com/styles/v2/light.json?key=$_protoMapsApiKey',
        apiKey: _protoMapsApiKey,
      );
      _vectorStyle = await reader.read();
      AppLogger.logMapOperation('Vector style loading', success: true);
      AppLogger.info('Map style loaded successfully', tag: 'MAP');
    } catch (e) {
      AppLogger.logMapOperation('ProtoMaps loading failed, trying fallback',
          success: false, error: e.toString());
      AppLogger.warning('ProtoMaps failed, attempting OpenStreetMap fallback',
          tag: 'MAP');

      // Fallback to OpenStreetMap tiles if ProtoMaps fails
      try {
        // Create a simple tile layer as fallback
        _useOpenStreetMapFallback = true;
        AppLogger.logMapOperation('OpenStreetMap fallback', success: true);
        AppLogger.info('Using OpenStreetMap fallback tiles', tag: 'MAP');
      } catch (fallbackError) {
        _vectorError =
            'Both ProtoMaps and OpenStreetMap fallback failed. ProtoMaps error: ${e.toString()}, Fallback error: ${fallbackError.toString()}';
        AppLogger.logMapOperation('All map loading methods failed',
            success: false, error: _vectorError!);
        AppLogger.error('All map loading methods failed',
            tag: 'MAP', error: fallbackError);
      }
    } finally {
      if (mounted) {
        setState(() {
          _styleLoading = false;
        });
      }
    }
  }

  void _goToNextState() {
    setState(() {
      if (_appState == AppState.postRide) {
        _appState = AppState.values[_appState.index + 1];
      } else {
        _appState = AppState.choosingLocation;
      }
    });
  }

  Future<void> _confirmLocation() async {
    AppLogger.info('Confirming location and calculating route...', tag: 'RIDE');

    if (_selectedDestination != null && _currentLocation != null) {
      try {
        AppLogger.info('Calling route function...', tag: 'RIDE');
        final response = await supabase.functions.invoke(
          'route',
          body: {
            'origin': {
              'latitude': _currentLocation!.latitude,
              'longitude': _currentLocation!.longitude,
            },
            'destination': {
              'latitude': _selectedDestination!.latitude,
              'longitude': _selectedDestination!.longitude,
            },
          },
        );

        AppLogger.logSupabaseOperation('Route function call',
            success: true, data: response.data);

        final data = response.data as Map<String, dynamic>;
        final coordinates = data['legs'][0]['polyline']['geoJsonLinestring']
            ['coordinates'] as List<dynamic>;
        final duration = parseDuration(data['duration'] as String);
        _fare = ((duration.inMinutes * 40)).ceil();

        AppLogger.logRideOperation('Route calculation', success: true, data: {
          'duration': duration.toString(),
          'fare': _fare,
          'coordinates_count': coordinates.length,
        });

        final List<LatLng> polylineCoordinates = coordinates.map((coord) {
          return LatLng(coord[1], coord[0]);
        }).toList();

        setState(() {
          _polylines.add(
            Polyline(
              points: polylineCoordinates,
              color: Colors.black,
              strokeWidth: 5.0,
            ),
          );

          _markers.add(
            Marker(
              point: _selectedDestination!,
              child:
                  const Icon(Icons.location_pin, color: Colors.red, size: 48),
              width: 48,
              height: 48,
            ),
          );
        });
        LatLngBounds bounds = LatLngBounds.fromPoints(polylineCoordinates);
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(50),
          ),
        );
        _goToNextState();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
        }
      }
    }
  }

  /// Finds a nearby driver
  ///
  /// When a driver is found, it subscribes to the driver's location and ride status.
  Future<void> _findDriver() async {
    AppLogger.info('Finding nearby driver...', tag: 'DRIVER');

    try {
      AppLogger.info('Calling find_driver RPC...', tag: 'DRIVER');
      final response = await supabase.rpc(
        'find_driver',
        params: {
          'origin':
              'POINT(${_currentLocation!.longitude} ${_currentLocation!.latitude})',
          'destination':
              'POINT(${_selectedDestination!.longitude} ${_selectedDestination!.latitude})',
          'fare': _fare,
        },
      ) as List<dynamic>;

      AppLogger.logSupabaseOperation('find_driver RPC',
          success: true, data: response);

      if (response.isEmpty) {
        AppLogger.warning('No drivers found in the area', tag: 'DRIVER');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No driver found. Please try again later.'),
            ),
          );
        }
        return;
      }

      String driverId = response.first['driver_id'];
      String rideId = response.first['ride_id'];

      AppLogger.logDriverOperation('Driver found', success: true, data: {
        'driver_id': driverId,
        'ride_id': rideId,
        'response_data': response.first,
      });

      _driverSubscription = supabase
          .from('drivers')
          .stream(primaryKey: ['id'])
          .eq('id', driverId)
          .listen((List<Map<String, dynamic>> data) {
            if (data.isNotEmpty) {
              setState(() {
                _driver = Driver.fromJson(data[0]);
              });
              _updateDriverMarker(_driver!);
              _adjustMapView(
                target: _appState == AppState.waitingForPickup
                    ? _currentLocation!
                    : _selectedDestination!,
              );
            }
          });

      _rideSubscription = supabase
          .from('rides')
          .stream(primaryKey: ['id'])
          .eq('id', rideId)
          .listen((List<Map<String, dynamic>> data) {
            if (data.isNotEmpty) {
              setState(() {
                final ride = Ride.fromJson(data[0]);
                if (ride.status == RideStatus.riding &&
                    _appState != AppState.riding) {
                  _appState = AppState.riding;
                } else if (ride.status == RideStatus.completed &&
                    _appState != AppState.postRide) {
                  _appState = AppState.postRide;
                  _cancelSubscriptions();
                  _showCompletionModal();
                }
              });
            }
          });

      _goToNextState();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }

  void _updateDriverMarker(Driver driver) {
    setState(() {
      // Remove all existing markers (since we can't identify by key)
      _markers.clear();

      // Re-add destination marker if it exists
      if (_selectedDestination != null) {
        _markers.add(
          Marker(
            point: _selectedDestination!,
            child: const Icon(Icons.location_pin, color: Colors.red, size: 48),
            width: 48,
            height: 48,
          ),
        );
      }

      double rotation = 0;
      if (_previousDriverLocation != null) {
        rotation = _calculateRotation(
          _previousDriverLocation!,
          driver.location,
        );
      }

      _markers.add(
        Marker(
          point: driver.location,
          child: Transform.rotate(
            angle: rotation * pi / 180,
            alignment: Alignment.center,
            child: const Icon(
              Icons.directions_car,
              color: Colors.blue,
              size: 48,
            ),
          ),
          width: 48,
          height: 48,
        ),
      );

      _previousDriverLocation = driver.location;
    });
  }

  void _adjustMapView({required LatLng target}) {
    if (_driver != null && _selectedDestination != null) {
      LatLngBounds bounds = LatLngBounds(
        LatLng(
          min(_driver!.location.latitude, target.latitude),
          min(_driver!.location.longitude, target.longitude),
        ),
        LatLng(
          max(_driver!.location.latitude, target.latitude),
          max(_driver!.location.longitude, target.longitude),
        ),
      );
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(100),
        ),
      );
    }
  }

  double _calculateRotation(LatLng start, LatLng end) {
    double latDiff = end.latitude - start.latitude;
    double lngDiff = end.longitude - start.longitude;
    double angle = atan2(lngDiff, latDiff);
    return angle * 180 / pi;
  }

  void _cancelSubscriptions() {
    _driverSubscription?.cancel();
    _rideSubscription?.cancel();
  }

  /// Shows a modal to indicate that the ride has been completed.
  void _showCompletionModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Ride Completed'),
          content: const Text(
            'Thank you for using our service! We hope you had a great ride.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
                _resetAppState();
              },
            ),
          ],
        );
      },
    );
  }

  void _resetAppState() {
    setState(() {
      _appState = AppState.choosingLocation;
      _selectedDestination = null;
      _driver = null;
      _fare = null;
      _polylines.clear();
      _markers.clear();
      _previousDriverLocation = null;
    });
    _getCurrentLocation();
  }

  String _getAppBarTitle() {
    switch (_appState) {
      case AppState.choosingLocation:
        return 'Choose Location';
      case AppState.confirmingFare:
        return 'Confirm Fare';
      case AppState.waitingForPickup:
        return 'Waiting for Pickup';
      case AppState.riding:
        return 'On the Way';
      case AppState.postRide:
        return 'Ride Completed';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getAppBarTitle()),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () {
              AppLogger.info('Navigating to log page', tag: 'UI');
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const LogPage()),
              );
            },
            tooltip: 'View Logs',
          ),
        ],
      ),
      body: Stack(
        children: [
          _currentLocation == null || _styleLoading
              ? const Center(child: CircularProgressIndicator())
              : (_vectorError != null && !_useOpenStreetMapFallback)
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning,
                                color: Colors.orange, size: 48),
                            const SizedBox(height: 16),
                            const Text(
                              'Map Loading Error',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _vectorError!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Using basic map tiles instead.',
                              style:
                                  TextStyle(fontSize: 14, color: Colors.blue),
                            ),
                          ],
                        ),
                      ),
                    )
                  : FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _initialCenter,
                        initialZoom: _initialZoom,
                        minZoom: 2.0,
                        maxZoom: 18.0,
                        onPositionChanged: (position, hasGesture) {
                          if (_appState == AppState.choosingLocation &&
                              hasGesture) {
                            _selectedDestination = position.center;
                          }
                        },
                      ),
                      children: [
                        if (_useOpenStreetMapFallback)
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.uber',
                          )
                        else if (_vectorStyle != null)
                          VectorTileLayer(
                            theme: _vectorStyle!.theme,
                            sprites: _vectorStyle!.sprites,
                            tileProviders: _vectorStyle!.providers,
                          ),
                        PolylineLayer(polylines: _polylines),
                        MarkerLayer(markers: _markers),
                      ],
                    ),
          if (_appState == AppState.choosingLocation)
            Center(
              child: Image.asset(
                'assets/images/center-pin.png',
                width: 96,
                height: 96,
              ),
            ),
        ],
      ),
      floatingActionButton: _appState == AppState.choosingLocation
          ? FloatingActionButton.extended(
              onPressed: _confirmLocation,
              label: const Text('Confirm Destination'),
              icon: const Icon(Icons.check),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomSheet: _appState == AppState.confirmingFare ||
              _appState == AppState.waitingForPickup
          ? Container(
              width: MediaQuery.of(context).size.width,
              padding: const EdgeInsets.all(
                16,
              ).copyWith(bottom: 16 + MediaQuery.of(context).padding.bottom),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.5),
                    spreadRadius: 5,
                    blurRadius: 7,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_appState == AppState.confirmingFare) ...[
                    Text(
                      'Confirm Fare',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Estimated fare: ${NumberFormat.currency(
                        symbol:
                            '\$', // You can change this to your preferred currency symbol
                        decimalDigits: 2,
                      ).format(_fare! / 100)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _findDriver,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: const Text('Confirm Fare'),
                    ),
                  ],
                  if (_appState == AppState.waitingForPickup &&
                      _driver != null) ...[
                    Text(
                      'Your Driver',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Car: ${_driver!.model}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Plate Number: ${_driver!.number}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Your driver is on the way. Please wait at the pickup location.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
