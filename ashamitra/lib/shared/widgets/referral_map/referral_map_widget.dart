import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';

class _Place {
  final String name;
  final LatLng pos;
  final String type;
  final double distanceKm;
  final bool isGovt; // PHC/CHC/DH/SNCU are government verified
  _Place({required this.name, required this.pos, required this.type, required this.distanceKm})
      : isGovt = ['PHC', 'CHC', 'DH', 'SNCU'].contains(type);
}

class ReferralMapWidget extends StatefulWidget {
  final String facilityType;
  final double mapHeight;
  final bool isEmergency; // RED band — markers turn red to signal urgency

  const ReferralMapWidget({
    super.key,
    required this.facilityType,
    this.mapHeight = 240,
    this.isEmergency = false,
  });

  @override
  State<ReferralMapWidget> createState() => _ReferralMapWidgetState();
}

class _ReferralMapWidgetState extends State<ReferralMapWidget> {
  final _mapController = MapController();

  Position? _userPos;
  List<_Place> _places = [];
  _Place? _selected;
  bool _loading = true;
  String? _error;

  static const _radii = [25000, 50000, 100000, 200000];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() { _loading = true; _error = null; });
    try {
      final pos = await _getLocation();
      if (pos == null) return;
      List<_Place> places = [];
      for (final r in _radii) {
        places = await _fetchPlaces(pos, r);
        if (places.length >= 5) break;
      }
      if (!mounted) return;
      setState(() {
        _userPos = pos;
        _places = places;
        _selected = places.isNotEmpty ? places.first : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'ডেটা লোড হয়নি'; _loading = false; });
    }
  }

  Future<Position?> _getLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() { _error = 'GPS বন্ধ আছে। সেটিংস থেকে চালু করুন।'; _loading = false; });
      return null;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      if (mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('লোকেশন প্রয়োজন', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            content: const Text('নিকটস্থ স্বাস্থ্যকেন্দ্র খুঁজে পেতে আপনার বর্তমান অবস্থান দরকার।', style: TextStyle(fontSize: 14)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('বাতিল')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('অনুমতি দিন', style: TextStyle(fontWeight: FontWeight.w700))),
            ],
          ),
        );
        if (proceed != true) {
          setState(() { _error = 'লোকেশন অনুমতি দেওয়া হয়নি'; _loading = false; });
          return null;
        }
      }
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      setState(() { _error = 'লোকেশন অনুমতি স্থায়ীভাবে বন্ধ।'; _loading = false; });
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('অনুমতি বন্ধ আছে', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            content: const Text('অ্যাপ সেটিংস থেকে লোকেশন অনুমতি চালু করুন।', style: TextStyle(fontSize: 14)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('বাতিল')),
              TextButton(
                onPressed: () { Navigator.pop(context); Geolocator.openAppSettings(); },
                child: const Text('সেটিংস খুলুন', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
      }
      return null;
    }
    if (perm == LocationPermission.denied) {
      setState(() { _error = 'লোকেশন অনুমতি দেওয়া হয়নি'; _loading = false; });
      return null;
    }
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) {
      Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 60)),
      ).then((fresh) { if (mounted) setState(() => _userPos = fresh); }).catchError((_) {});
      return last;
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 60)),
    );
  }

  Future<List<_Place>> _fetchPlaces(Position pos, int radius) async {
    final lat = pos.latitude;
    final lng = pos.longitude;
    final deg = radius / 111000.0;
    final viewbox = '${lng - deg},${lat + deg},${lng + deg},${lat - deg}';
    final headers = {'User-Agent': 'AshamItraApp/1.0 (health worker app India)'};

    final results = await Future.wait([
      _nominatimSearch('hospital', viewbox, headers),
      _nominatimSearch('clinic', viewbox, headers),
      _nominatimSearch('PHC primary health centre', viewbox, headers),
      _nominatimSearch('CHC community health centre', viewbox, headers),
      _nominatimSearch('district hospital', viewbox, headers),
      _nominatimSearch('SNCU newborn care', viewbox, headers),
    ]);

    final places = <_Place>[];
    for (final list in results) {
      for (final el in list) {
        final elLat = double.tryParse(el['lat']?.toString() ?? '');
        final elLng = double.tryParse(el['lon']?.toString() ?? '');
        if (elLat == null || elLng == null) continue;
        final dist = _distanceKm(lat, lng, elLat, elLng);
        final name = el['display_name']?.toString().split(',').first.trim()
            ?? el['name']?.toString() ?? 'Hospital';
        places.add(_Place(
          name: name,
          pos: LatLng(elLat, elLng),
          type: _classifyPlace(name),
          distanceKm: dist,
        ));
      }
    }

    places.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    final seen = <String>{};
    return places.where((p) {
      final key = '${(p.pos.latitude * 500).round()},${(p.pos.longitude * 500).round()}';
      return seen.add(key);
    }).toList();
  }

  Future<List<dynamic>> _nominatimSearch(String q, String viewbox, Map<String, String> headers) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?format=json&q=${Uri.encodeComponent(q)}'
        '&bounded=1&viewbox=$viewbox&limit=20',
      );
      final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return [];
      return jsonDecode(resp.body) as List? ?? [];
    } catch (_) {
      return [];
    }
  }

  static double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.pow(math.sin(dLng / 2), 2) *
        math.cos(lat1 * math.pi / 180) *
        math.cos(lat2 * math.pi / 180);
    return r * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
  }

  static String _extractFacilityKeyword(String raw) {
    final u = raw.toUpperCase();
    if (u.contains('SNCU')) return 'SNCU';
    if (u.contains('DH') || u.contains('DISTRICT')) return 'DH';
    if (u.contains('FRU')) return 'DH';
    if (u.contains('CHC') || u.contains('COMMUNITY')) return 'CHC';
    if (u.contains('PHC') || u.contains('PRIMARY')) return 'PHC';
    return 'hospital';
  }

  static String _classifyPlace(String name) {
    final n = name.toUpperCase();
    if (n.contains('SNCU') || n.contains('NEWBORN') || n.contains('NICU')) return 'SNCU';
    if (n.contains('DISTRICT') || n.contains(' DH') || n.contains('DISTRICT HOSPITAL')) return 'DH';
    if (n.contains('CHC') || n.contains('COMMUNITY HEALTH')) return 'CHC';
    if (n.contains('PHC') || n.contains('PRIMARY HEALTH') || n.contains('SUB CENTRE') || n.contains('SUBCENTRE')) return 'PHC';
    // Any hospital/clinic that doesn't match above is still a real hospital
    return 'hospital';
  }

  Color _colorForType(String type) {
    if (widget.isEmergency) return AppColors.emergencyRed;
    return switch (type) {
      'PHC'     => const Color(0xFF059669), // emerald green
      'CHC'     => const Color(0xFF0284C7), // sky blue
      'DH'      => const Color(0xFF7C3AED), // purple
      'SNCU'    => const Color(0xFFD97706), // amber
      'hospital'=> const Color(0xFF0F766E), // teal — general hospital (not red!)
      _         => const Color(0xFF0F766E),
    };
  }

  bool _isRecommended(String type) => _extractFacilityKeyword(widget.facilityType) == type;

  static String _typeLabelBn(String type) => switch (type) {
    'PHC'      => 'PHC — প্রাথমিক স্বাস্থ্য',
    'CHC'      => 'CHC — কমিউনিটি হেলথ',
    'DH'       => 'DH — জেলা হাসপাতাল',
    'SNCU'     => 'SNCU — নবজাতক যত্ন',
    'hospital' => 'হাসপাতাল / ক্লিনিক',
    _          => 'স্বাস্থ্যকেন্দ্র',
  };

  String _distanceLabel(double km) {
    if (km < 0.1) return '${(km * 1000).round()} মি';
    if (km < 10) return '${km.toStringAsFixed(1)} কিমি';
    return '${km.round()} কিমি';
  }

  String _travelTime(double km) {
    if (km < 0.05) return '১ মিনিট';
    if (km < 2) {
      final mins = (km / 5 * 60).round();
      return '$mins মিনিট হাঁটা';
    }
    final mins = (km / 30 * 60).round();
    if (mins < 60) return '$mins মিনিট';
    final hrs = mins ~/ 60;
    final rem = mins % 60;
    return rem == 0 ? '$hrs ঘণ্টা' : '$hrs ঘণ্টা $rem মিনিট';
  }

  Future<void> _openDirections(_Place place) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${place.pos.latitude},${place.pos.longitude}',
    );
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE0E7FF)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: widget.isEmergency
                    ? [const Color(0xFFDC2626), const Color(0xFFB91C1C)]
                    : [const Color(0xFF4F46E5), const Color(0xFF7C3AED)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                  child: Icon(
                    widget.isEmergency ? Icons.emergency_rounded : Icons.local_hospital_rounded,
                    color: Colors.white, size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isEmergency ? 'জরুরি রেফার কেন্দ্র' : 'নিকটস্থ রেফার কেন্দ্র',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      Text(
                        widget.isEmergency ? 'এখনই রেফার করুন — সময় নষ্ট করবেন না' : 'আপনার অবস্থান থেকে',
                        style: const TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                if (_loading)
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                else
                  GestureDetector(
                    onTap: _init,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),

          // ── Nearest facility summary bar ──────────────────────────────────
          if (!_loading && _error == null && _selected != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0E7FF)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: _colorForType(_selected!.type),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.local_hospital_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selected!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1E1B4B)),
                        ),
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            _InfoChip(icon: Icons.straighten_rounded, label: _distanceLabel(_selected!.distanceKm)),
                            _InfoChip(
                              icon: _selected!.distanceKm < 2 ? Icons.directions_walk_rounded : Icons.directions_car_rounded,
                              label: _travelTime(_selected!.distanceKm),
                            ),
                            if (_selected!.isGovt)
                              _InfoChip(icon: Icons.verified_rounded, label: 'সরকারি', iconColor: const Color(0xFF059669)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _openDirections(_selected!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)]),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))],
                      ),
                      child: const Row(children: [
                        Icon(Icons.directions_rounded, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text('পথ', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // ── Map ───────────────────────────────────────────────────────────
          if (_loading)
            SizedBox(
              height: widget.mapHeight,
              child: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
            )
          else if (_error != null)
            _ErrorTile(error: _error!, onRetry: _init)
          else if (_userPos != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                height: widget.mapHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE0E7FF)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCameraFit: _selected != null
                              ? CameraFit.bounds(
                                  bounds: LatLngBounds.fromPoints([
                                    LatLng(_userPos!.latitude, _userPos!.longitude),
                                    _selected!.pos,
                                  ]),
                                  padding: const EdgeInsets.all(60),
                                )
                              : CameraFit.bounds(
                                  bounds: LatLngBounds.fromPoints([
                                    LatLng(_userPos!.latitude, _userPos!.longitude),
                                    LatLng(_userPos!.latitude + 0.01, _userPos!.longitude + 0.01),
                                  ]),
                                  padding: const EdgeInsets.all(60),
                                ),
                          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.ashamitra.app',
                          ),
                          if (_selected != null)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: [
                                    LatLng(_userPos!.latitude, _userPos!.longitude),
                                    _selected!.pos,
                                  ],
                                  strokeWidth: 3.5,
                                  color: AppColors.primary.withValues(alpha: 0.8),
                                  pattern: StrokePattern.dashed(segments: [12, 6]),
                                ),
                              ],
                            ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: LatLng(_userPos!.latitude, _userPos!.longitude),
                                width: 40, height: 40,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 3),
                                    boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.5), blurRadius: 10)],
                                  ),
                                  child: const Icon(Icons.person_rounded, color: Colors.white, size: 20),
                                ),
                              ),
                              ..._places.map((p) {
                                final color = _colorForType(p.type);
                                final isSelected = _selected == p;
                                final recommended = _isRecommended(p.type);
                                return Marker(
                                  point: p.pos,
                                  width: isSelected ? 46 : (recommended ? 40 : 34),
                                  height: isSelected ? 46 : (recommended ? 40 : 34),
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() => _selected = p);
                                      _mapController.fitCamera(
                                        CameraFit.bounds(
                                          bounds: LatLngBounds.fromPoints([
                                            LatLng(_userPos!.latitude, _userPos!.longitude),
                                            p.pos,
                                          ]),
                                          padding: const EdgeInsets.all(60),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: isSelected ? color : color.withValues(alpha: 0.85),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.6),
                                          width: isSelected ? 3 : 2,
                                        ),
                                        boxShadow: [BoxShadow(
                                          color: color.withValues(alpha: isSelected ? 0.6 : 0.3),
                                          blurRadius: isSelected ? 14 : 6,
                                        )],
                                      ),
                                      child: Icon(
                                        Icons.local_hospital_rounded,
                                        color: Colors.white,
                                        size: isSelected ? 24 : (recommended ? 20 : 16),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ],
                      ),
                      // ── Dynamic legend overlay ───────────────────────────────────────
                      Positioned(
                        bottom: 8, left: 8,
                        child: _MapLegend(
                          // always show "You" entry
                          entries: [
                            _LegendEntry(color: AppColors.primary, icon: Icons.person_rounded, label: 'আপনি'),
                            // only show types that actually appear in _places
                            ..._places.map((p) => p.type).toSet().map((type) =>
                              _LegendEntry(
                                color: _colorForType(type),
                                icon: Icons.local_hospital_rounded,
                                label: _typeLabelBn(type),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // ── Zoom + re-center controls ──────────────────────────────────────────────────
                      Positioned(
                        top: 8, right: 8,
                        child: Column(
                          children: [
                            _ZoomBtn(
                              icon: Icons.add_rounded,
                              onTap: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1),
                            ),
                            const SizedBox(height: 4),
                            _ZoomBtn(
                              icon: Icons.remove_rounded,
                              onTap: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1),
                            ),
                            const SizedBox(height: 4),
                            _ZoomBtn(
                              icon: Icons.my_location_rounded,
                              tooltip: 'ফিরে যান',
                              onTap: () {
                                if (_selected != null) {
                                  _mapController.fitCamera(
                                    CameraFit.bounds(
                                      bounds: LatLngBounds.fromPoints([
                                        LatLng(_userPos!.latitude, _userPos!.longitude),
                                        _selected!.pos,
                                      ]),
                                      padding: const EdgeInsets.all(60),
                                    ),
                                  );
                                } else {
                                  _mapController.move(
                                    LatLng(_userPos!.latitude, _userPos!.longitude), 14,
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Zero results message ──────────────────────────────────────────
          if (!_loading && _error == null && _places.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
                children: const [
                  Icon(Icons.info_outline_rounded, size: 13, color: AppColors.textSecondary),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '২০০ কিমির মধ্যে কোনো নিবন্ধিত স্বাস্থ্যকেন্দ্র পাওয়া যায়নি।',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),

          // ── Facility list ─────────────────────────────────────────────────
          if (!_loading && _error == null && _places.isNotEmpty) ...[ 
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  const Text('কাছের কেন্দ্রসমূহ',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.onBackground)),
                  const Spacer(),
                  Text('${_places.length}টি পাওয়া গেছে',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ..._places.take(5).map((p) {
              final color = _colorForType(p.type);
              final isSelected = _selected == p;
              final recommended = _isRecommended(p.type);
              return GestureDetector(
                onTap: () {
                setState(() => _selected = p);
                if (_userPos != null) {
                  _mapController.fitCamera(
                    CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints([
                        LatLng(_userPos!.latitude, _userPos!.longitude),
                        p.pos,
                      ]),
                      padding: const EdgeInsets.all(60),
                    ),
                  );
                }
              },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? color.withValues(alpha: 0.08) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? color.withValues(alpha: 0.5) : const Color(0xFFE0E7FF),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Rank badge
                      Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(
                          color: isSelected ? color : const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text(
                            '${_places.indexOf(p) + 1}',
                            style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w800,
                              color: isSelected ? Colors.white : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Flexible(
                                child: Text(p.name,
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w700,
                                      color: isSelected ? color : AppColors.onBackground,
                                    )),
                              ),
                              if (recommended) ...[
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                                  child: const Text('প্রস্তাবিত', style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ]),
                            const SizedBox(height: 4),
                            // type chip
                            Row(children: [
                              Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                              const SizedBox(width: 4),
                              Text(p.type, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                              if (p.isGovt) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.verified_rounded, size: 10, color: Color(0xFF059669)),
                                const SizedBox(width: 2),
                                const Text('সরকারি', style: TextStyle(fontSize: 9, color: Color(0xFF059669), fontWeight: FontWeight.w600)),
                              ],
                            ]),
                            const SizedBox(height: 4),
                            // distance + time always on own row — never overflows
                            Row(children: [
                              _InfoChip(icon: Icons.straighten_rounded, label: _distanceLabel(p.distanceKm)),
                              const SizedBox(width: 6),
                              _InfoChip(
                                icon: p.distanceKm < 2 ? Icons.directions_walk_rounded : Icons.directions_car_rounded,
                                label: _travelTime(p.distanceKm),
                              ),
                            ]),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _openDirections(p),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.directions_rounded, color: color, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],

          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

// ── Info chip ────────────────────────────────────────────────────────────────
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  const _InfoChip({required this.icon, required this.label, this.iconColor = AppColors.textSecondary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: iconColor),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 10, color: iconColor, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Legend entry model ────────────────────────────────────────────────────────────────
class _LegendEntry {
  final Color color;
  final IconData icon;
  final String label;
  const _LegendEntry({required this.color, required this.icon, required this.label});
}

// ── Dynamic map legend overlay ────────────────────────────────────────────────────────
class _MapLegend extends StatefulWidget {
  final List<_LegendEntry> entries;
  const _MapLegend({required this.entries});

  @override
  State<_MapLegend> createState() => _MapLegendState();
}

class _MapLegendState extends State<_MapLegend> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // toggle row
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('সংকেত', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF1E1B4B))),
                const SizedBox(width: 4),
                Icon(
                  _expanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                  size: 14, color: AppColors.primary,
                ),
              ],
            ),
          ),
          // entries — only shown when expanded
          if (_expanded) ...[
            const SizedBox(height: 4),
            ...widget.entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 18, height: 18,
                    decoration: BoxDecoration(color: e.color, shape: BoxShape.circle),
                    child: Icon(e.icon, size: 10, color: Colors.white),
                  ),
                  const SizedBox(width: 6),
                  Text(e.label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFF1E1B4B))),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }
}

// ── Zoom button ───────────────────────────────────────────────────────────────────────────
class _ZoomBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  const _ZoomBtn({required this.icon, required this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final btn = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6)],
        ),
        child: Icon(icon, size: 18, color: AppColors.primary),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: btn) : btn;
  }
}

// ── Error tile ────────────────────────────────────────────────────────────────
class _ErrorTile extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorTile({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3CD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD97706)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFD97706)),
          const SizedBox(width: 8),
          Expanded(child: Text(error, style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)))),
          GestureDetector(
            onTap: onRetry,
            child: const Text('আবার চেষ্টা', style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
