import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';

class MapWarehouse {
  final String name;
  final double lat, lng;
  const MapWarehouse(this.name, this.lat, this.lng);
}

/// خريطة OpenStreetMap (بتشتغل على Windows و Android من غير API key)
class RepsMap extends StatelessWidget {
  final List<RepLive> reps;
  final List<MapWarehouse> warehouses;
  final ValueChanged<RepLive>? onTapRep;
  final double zoom;
  const RepsMap({super.key, required this.reps, this.warehouses = const [], this.onTapRep, this.zoom = 12});

  static const _cairo = LatLng(30.0444, 31.2357);

  @override
  Widget build(BuildContext context) {
    final points = [
      for (final r in reps)
        if (r.lat != null && r.lng != null) LatLng(r.lat!, r.lng!),
      for (final w in warehouses) LatLng(w.lat, w.lng),
    ];
    final center = points.isEmpty
        ? _cairo
        : LatLng(points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length,
            points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length);
    final fit = points.length > 1 ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(48), maxZoom: 15) : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: FlutterMap(
        options: MapOptions(initialCenter: center, initialZoom: zoom, initialCameraFit: fit),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.madar.app',
          ),
          MarkerLayer(markers: [
            for (final w in warehouses)
              Marker(
                point: LatLng(w.lat, w.lng),
                width: 40,
                height: 40,
                child: Tooltip(
                  message: w.name,
                  child: Container(
                    decoration: BoxDecoration(color: MC.ink, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.warehouse_rounded, color: MC.orange, size: 22),
                  ),
                ),
              ),
            for (final r in reps)
              if (r.lat != null && r.lng != null)
                Marker(
                  point: LatLng(r.lat!, r.lng!),
                  width: 150,
                  height: 34,
                  child: GestureDetector(
                    onTap: onTapRep == null ? null : () => onTapRep!(r),
                    child: _Pin(rep: r),
                  ),
                ),
          ]),
          const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
        ],
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  final RepLive rep;
  const _Pin({required this.rep});
  @override
  Widget build(BuildContext context) {
    final color = switch (rep.status) {
      RepStatus.moving => MC.burnt,
      RepStatus.lost => MC.crimson,
      RepStatus.stopped => MC.muted,
      _ => MC.teal,
    };
    final note = switch (rep.status) {
      RepStatus.lost => 'GPS مقطوع',
      RepStatus.stopped => 'متوقف',
      _ => timeAgo(rep.lastSeen),
    };
    return Align(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 10, 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(99),
          boxShadow: const [BoxShadow(color: Color(0x2622101C), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Text(rep.initial, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 6),
          Flexible(child: Text(note, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }
}
