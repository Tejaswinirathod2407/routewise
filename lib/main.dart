import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

const bg = Color(0xFF12151A), surf = Color(0xFF1E232B), accent = Color(0xFFFFB74A);
const green = Color(0xFF4ADE9C), red = Color(0xFFFF6B6B), muted = Color(0xFF8B94A3);

/* ---------------- Models & data ---------------- */
class Vehicle {
  String id, name, type, icon;
  int seats, price;
  Vehicle(this.id, this.name, this.type, this.seats, this.price, this.icon);
}

class Driver {
  String id, name, phone;
  double rating;
  Driver(this.id, this.name, this.phone, this.rating);
}

class Place {
  double lat, lng;
  String label;
  Place(this.lat, this.lng, this.label);
}

class Booking {
  String id, name, email, phone, vehicleId, driverMode, status = 'confirmed', payment = 'paid';
  String? driverId, driverStatus;
  DateTime start, end;
  int hours, total;
  Place pickup, drop;
  double km;
  List<LatLng> route;
  (int, String)? review;
  Booking(this.id, this.name, this.email, this.phone, this.vehicleId, this.driverMode,
      this.driverId, this.driverStatus, this.start, this.end, this.hours, this.pickup,
      this.drop, this.km, this.route, this.total);
}

final vehicles = <Vehicle>[
  Vehicle('V1', 'Maruti Suzuki Swift', 'Hatchback', 5, 1200, '🚗'),
  Vehicle('V2', 'Honda City', 'Sedan', 5, 1550, '🚙'),
  Vehicle('V3', 'Hyundai Creta', 'SUV', 5, 1900, '🚐'),
  Vehicle('V4', 'Toyota Innova Crysta', 'MPV', 7, 2400, '🚐'),
  Vehicle('V5', 'Mahindra Thar', 'Off-Road SUV', 4, 2050, '🚙'),
  Vehicle('V6', 'Royal Enfield Classic 350', 'Bike', 2, 600, '🏍️'),
];

final drivers = <Driver>[
  Driver('D1', 'Ramesh Kumar', '98480 11223', 4.8),
  Driver('D2', 'Suresh Reddy', '99080 44556', 4.6),
  Driver('D3', 'Anitha Rao', '93910 77889', 4.9),
  Driver('D4', 'Vikram Singh', '90000 12121', 4.5),
];

final bookings = <Booking>[];
const basePkgs = {3: 700, 6: 1200, 12: 1800, 24: 2800};
const driverFee = {3: 200, 6: 350, 12: 550, 24: 800};

const known = {
  'banjara hills': [17.4156, 78.4347], 'jubilee hills': [17.4324, 78.4071],
  'hitech city': [17.4483, 78.3915], 'gachibowli': [17.4401, 78.3489],
  'madhapur': [17.4483, 78.3915], 'kondapur': [17.4614, 78.3641],
  'secunderabad': [17.4399, 78.4983], 'begumpet': [17.4436, 78.4636],
  'ameerpet': [17.4374, 78.4482], 'kukatpally': [17.4849, 78.4108],
  'miyapur': [17.4966, 78.3625], 'charminar': [17.3616, 78.4747],
  'abids': [17.3903, 78.4759], 'koti': [17.3833, 78.4808],
  'dilsukhnagar': [17.3687, 78.5247], 'uppal': [17.4008, 78.5590],
  'somajiguda': [17.4256, 78.4557], 'panjagutta': [17.4293, 78.4527],
  'tank bund': [17.4239, 78.4738], 'hussain sagar': [17.4239, 78.4738],
  'rajiv gandhi international airport': [17.2403, 78.4294],
  'rajiv gandhi airport': [17.2403, 78.4294], 'rgia': [17.2403, 78.4294],
  'shamshabad': [17.2403, 78.4294], 'nampally': [17.3871, 78.4661],
  'mehdipatnam': [17.3959, 78.4386], 'tolichowki': [17.3999, 78.4136],
  'manikonda': [17.4064, 78.3822], 'financial district': [17.4157, 78.3406],
};

/* ---------------- Helpers ---------------- */
String money(num n) {
  var s = n.round().toString();
  if (s.length > 3) {
    var l = s.substring(s.length - 3), r = s.substring(0, s.length - 3);
    r = r.replaceAllMapped(RegExp(r'(\d)(?=(\d\d)+$)'), (m) => '${m[1]},');
    s = '$r,$l';
  }
  return '₹$s';
}

String fmt(DateTime d) =>
    '${d.day}/${d.month} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

Vehicle? vById(String id) => vehicles.where((v) => v.id == id).firstOrNull;
Driver? dById(String? id) => drivers.where((d) => d.id == id).firstOrNull;
String vName(String id) => vById(id)?.name ?? '—';
String dName(Booking b) =>
    b.driverMode == 'driver' ? (dById(b.driverId)?.name ?? '—') : 'Self drive';

int pkgPrice(Vehicle v, int h) =>
    ((basePkgs[h]! * v.price / 1200) / 50).round() * 50;

double haversine(Place a, Place b) {
  double r(double x) => x * pi / 180;
  final h = pow(sin(r(b.lat - a.lat) / 2), 2) +
      cos(r(a.lat)) * cos(r(b.lat)) * pow(sin(r(b.lng - a.lng) / 2), 2);
  return 2 * 6371 * asin(sqrt(h));
}

DateTime? busyUntil(String vid) {
  final now = DateTime.now();
  DateTime? best;
  for (final b in bookings.where((b) =>
      b.vehicleId == vid &&
      (b.status == 'confirmed' || b.status == 'ongoing'))) {
    if (b.end.isAfter(now) && (best == null || b.end.isAfter(best))) {
      best = b.end;
    }
  }
  return best;
}

/* ---------------- Geocoding ---------------- */
Future<Place?> geocode(String q) async {
  for (final s in ['$q, Hyderabad, India', '$q, India', q]) {
    try {
      final r = await http.get(
        Uri.https('nominatim.openstreetmap.org', '/search', {
          'format': 'json',
          'limit': '1',
          'q': s,
        }),
        headers: {'User-Agent': 'routewise-demo'},
      );
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as List;
        if (d.isNotEmpty) {
          return Place(
            double.parse(d[0]['lat']),
            double.parse(d[0]['lon']),
            q,
          );
        }
      }
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 350));
  }

  try {
    final r = await http.get(Uri.https(
      'photon.komoot.io',
      '/api/',
      {'limit': '1', 'q': '$q Hyderabad India'},
    ));
    if (r.statusCode == 200) {
      final f = jsonDecode(r.body)['features'] as List;
      if (f.isNotEmpty) {
        final c = f[0]['geometry']['coordinates'];
        return Place(
          (c[1] as num).toDouble(),
          (c[0] as num).toDouble(),
          q,
        );
      }
    }
  } catch (_) {}

  final k = q.trim().toLowerCase();
  if (k.isEmpty) return null;
  final key = known.keys.where((n) => n == k).firstOrNull ??
      known.keys.where((n) => k.contains(n) || n.contains(k)).firstOrNull;
  return key == null ? null : Place(known[key]![0], known[key]![1], q);
}

/* ---------------- App state ---------------- */
class AppState extends ChangeNotifier {
  String role = 'customer',
      page = 'home',
      adminTab = 'Vehicles',
      typeFilter = 'All',
      statusFilter = 'All';
  Map<String, String>? customer;
  String? driverId, dId, pickupText, dropText, lastId;
  bool adminAuthed = false, withDriver = false;
  Vehicle? veh;
  int? hours;
  int seq = 1001;
  Place? pickup, drop;
  double km = 0, mins = 0;
  List<LatLng> route = [];
  List<(bool, String)> chat = [];
  String step = 'pickup';

  void u(VoidCallback f) {
    f();
    notifyListeners();
  }

  void go(String p) => u(() => page = p);

  void setRole(String r) => u(() {
        role = r;
        page = 'home';
      });

  void startBooking(Vehicle v) {
    veh = v;
    withDriver = false;
    dId = null;
    hours = null;
    pickup = drop = null;
    chat = [(true, 'Hi! Where should we pick you up? (e.g. "Banjara Hills")')];
    step = 'pickup';
    go('locations');
  }

  void chatSend(String t) {
    chat.add((false, t));
    if (step == 'pickup') {
      pickupText = t;
      chat.add((true, 'Got it. And where would you like to be dropped off?'));
      step = 'drop';
      notifyListeners();
    } else if (step == 'drop') {
      dropText = t;
      step = 'searching';
      notifyListeners();
      resolve();
    }
  }

  Future<void> resolve() async {
    final p = await geocode(pickupText!);
    final d = await geocode(dropText!);
    if (p == null || d == null) {
      chat.add((true,
          'Sorry, I couldn\'t find "${p == null ? pickupText : dropText}" in Hyderabad. Try a more specific name.'));
      step = 'error';
      notifyListeners();
      return;
    }

    pickup = p;
    drop = d;
    try {
      final r = await http.get(Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/${p.lng},${p.lat};${d.lng},${d.lat}?overview=full&geometries=geojson'));
      final rt = jsonDecode(r.body)['routes'][0];
      km = (rt['distance'] as num) / 1000;
      mins = (rt['duration'] as num) / 60;
      route = (rt['geometry']['coordinates'] as List)
          .map((c) => LatLng(
                (c[1] as num).toDouble(),
                (c[0] as num).toDouble(),
              ))
          .toList();
    } catch (_) {
      km = haversine(p, d);
      mins = km / 30 * 60;
      route = [LatLng(p.lat, p.lng), LatLng(d.lat, d.lng)];
    }

    chat.add((true,
        'Found both! ${p.label} → ${d.label}, about ${km.toStringAsFixed(1)} km.'));
    step = 'done';
    notifyListeners();
  }

  int get fee => withDriver ? driverFee[hours]! : 0;
  int get total => pkgPrice(veh!, hours!) + fee;

  void pay() {
    final now = DateTime.now();
    final b = Booking(
      'RW${seq++}',
      customer!['name']!,
      customer!['email']!,
      customer!['phone']!,
      veh!.id,
      withDriver ? 'driver' : 'self',
      dId,
      withDriver ? 'pending' : null,
      now,
      now.add(Duration(hours: hours!)),
      hours!,
      pickup!,
      drop!,
      km,
      route,
      total,
    );
    bookings.add(b);
    lastId = b.id;
    go('confirm');
  }
}

final app = AppState();

/* ---------------- UI helpers ---------------- */
Widget h(String t, [double s = 22]) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(t,
          style: TextStyle(fontSize: s, fontWeight: FontWeight.w600)),
    );

Widget box(Widget c, {Color? border, VoidCallback? onTap}) => Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: border ?? const Color(0xFF2C323C)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(16), child: c),
      ),
    );

Widget kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(color: muted)),
          Flexible(
            child: Text(v,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

Widget badge(String s) {
  final c = {
        'confirmed': green,
        'ongoing': const Color(0xFF78AAFF),
        'completed': muted,
        'cancelled': red,
        'pending': accent,
        'paid': green
      }[s] ??
      muted;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
        color: c.withAlpha(40), borderRadius: BorderRadius.circular(20)),
    child: Text(s.toUpperCase(),
        style: TextStyle(
            color: c, fontSize: 11, fontWeight: FontWeight.bold)),
  );
}

Widget tf(TextEditingController c, String l, {bool num = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: num ? TextInputType.number : null,
        decoration: InputDecoration(
            labelText: l, border: const OutlineInputBorder()),
      ),
    );

Widget btn(String t, VoidCallback? f,
        {bool danger = false, bool primary = true}) =>
    danger
        ? OutlinedButton(
            onPressed: f,
            style: OutlinedButton.styleFrom(
                foregroundColor: red,
                side: const BorderSide(color: red)),
            child: Text(t))
        : primary
            ? FilledButton(onPressed: f, child: Text(t))
            : OutlinedButton(onPressed: f, child: Text(t));

void toast(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
    class RouteMap extends StatelessWidget {
  final Place a, b;
  final List<LatLng> pts;
  final double height;

  const RouteMap(this.a, this.b, this.pts, {super.key, this.height = 300});

  @override
  Widget build(BuildContext context) {
    final p = pts.length < 2
        ? [LatLng(a.lat, a.lng), LatLng(b.lat, b.lng)]
        : pts;

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(p),
              padding: const EdgeInsets.all(30),
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.routewise',
            ),
            PolylineLayer(
              polylines: [
                Polyline(points: p, strokeWidth: 4, color: accent),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(a.lat, a.lng),
                  width: 40,
                  height: 40,
                  child: const Icon(
                    Icons.location_on,
                    color: green,
                    size: 36,
                  ),
                ),
                Marker(
                  point: LatLng(b.lat, b.lng),
                  width: 40,
                  height: 40,
                  child: const Icon(
                    Icons.flag,
                    color: red,
                    size: 32,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AddForm extends StatefulWidget {
  final String title;
  final List<String> labels;
  final void Function(List<String>) onAdd;

  const AddForm(this.title, this.labels, this.onAdd, {super.key});

  @override
  State<AddForm> createState() => _AddFormState();
}

class _AddFormState extends State<AddForm> {
  late final cs =
      widget.labels.map((_) => TextEditingController()).toList();

  @override
  Widget build(BuildContext context) => box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            h(widget.title, 17),
            for (var i = 0; i < cs.length; i++)
              tf(cs[i], widget.labels[i]),
            btn('Add', () {
              final v = cs.map((c) => c.text.trim()).toList();
              if (v.any((x) => x.isEmpty)) {
                return toast(context, 'Fill in all fields');
              }
              widget.onAdd(v);
              for (final c in cs) {
                c.clear();
              }
            }),
          ],
        ),
      );
}

/* ---------------- Root ---------------- */
void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'RouteWise',
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: bg,
          colorScheme: const ColorScheme.dark(
            primary: accent,
            onPrimary: bg,
            surface: surf,
          ),
          cardColor: surf,
          cardTheme: const CardThemeData(color: surf),
        ),
        home: const Shell(),
      );
}

class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (c, _) => Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runSpacing: 10,
                      children: [
                        const Text(
                          'RouteWise',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: accent,
                          ),
                        ),
                        SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: 'customer',
                              label: Text('Customer'),
                            ),
                            ButtonSegment(
                              value: 'driver',
                              label: Text('Driver'),
                            ),
                            ButtonSegment(
                              value: 'admin',
                              label: Text('Admin'),
                            ),
                          ],
                          selected: {app.role},
                          onSelectionChanged: (s) => app.setRole(s.first),
                        ),
                      ],
                    ),
                    const Divider(height: 30),
                    app.role == 'driver'
                        ? const DriverView()
                        : app.role == 'admin'
                            ? const AdminView()
                            : const CustomerView(),
                    const SizedBox(height: 40),
                    const Center(
                      child: Text(
                        'PROTOTYPE — in-memory data · OSM/Nominatim/Photon/OSRM · payments simulated',
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

/* =========================================================
   CUSTOMER
   ========================================================= */
Future<void> loginDialog(BuildContext c, VoidCallback then) async {
  final n = TextEditingController();
  final e = TextEditingController();
  final p = TextEditingController();

  await showDialog(
    context: c,
    builder: (d) => AlertDialog(
      title: const Text('Continue as guest'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          tf(n, 'Full name'),
          tf(e, 'Email'),
          tf(p, 'Phone'),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () {
            if ([n, e, p].any((x) => x.text.trim().isEmpty)) return;

            app.customer = {
              'name': n.text.trim(),
              'email': e.text.trim(),
              'phone': p.text.trim(),
            };

            Navigator.pop(d);
            then();
          },
          child: const Text('Continue'),
        ),
      ],
    ),
  );
}

class CustomerView extends StatelessWidget {
  const CustomerView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = app.customer;
    final page = c == null && app.page != 'home' ? 'home' : app.page;

    final body = switch (page) {
      'locations' => const Locations(),
      'duration' => const Duration_(),
      'payment' => const Payment(),
      'confirm' => const Confirm(),
      'mybookings' => const MyBookings(),
      _ => const Home(),
    };

    final steps = ['locations', 'duration', 'payment', 'confirm'];
    final idx = steps.indexOf(page);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            btn('Home', () => app.go('home'), primary: page == 'home'),
            btn(
              'My Bookings',
              () => c == null
                  ? loginDialog(context, () => app.go('mybookings'))
                  : app.go('mybookings'),
              primary: page == 'mybookings',
            ),
            if (c != null)
              btn(
                '${c['name']!.split(' ')[0]} · Log out',
                () => app.u(() {
                  app.customer = null;
                  app.page = 'home';
                }),
                primary: false,
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (idx >= 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < steps.length; i++)
                  Chip(
                    backgroundColor:
                        i < idx ? green : i == idx ? accent : surf,
                    label: Text(
                      '${i < idx ? '✓' : i + 1} ${steps[i][0].toUpperCase()}${steps[i].substring(1)}',
                      style: TextStyle(
                        color: i <= idx ? bg : muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        body,
      ],
    );
  }
}

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) {
    final types = ['All', ...{...vehicles.map((v) => v.type)}];
    final list = vehicles.where(
      (v) => app.typeFilter == 'All' || v.type == app.typeFilter,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TELL US WHERE → WE\'LL DO THE REST',
          style: TextStyle(color: accent, fontSize: 12, letterSpacing: 1.5),
        ),
        h('Find your next ride across Hyderabad.', 34),
        const Text(
          'Pick a vehicle, then type your pickup and drop like you\'re texting a friend. We\'ll pin both on the map and price it by the hour.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            h('Available vehicles'),
            DropdownButton<String>(
              value: app.typeFilter,
              items: [
                for (final t in types)
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: (v) => app.u(() => app.typeFilter = v!),
            ),
          ],
        ),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final v in list)
              SizedBox(
                width: 280,
                child: box(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Text(v.icon, style: const TextStyle(fontSize: 48)),
                      ),
                      h(v.name, 18),
                      Text(
                        '${v.type} · ${v.seats} seats',
                        style: const TextStyle(color: muted),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Pricing shown after you set pickup & drop',
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: btn(
                          'Select this vehicle',
                          () => app.customer == null
                              ? loginDialog(context, () => app.startBooking(v))
                              : app.startBooking(v),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class Locations extends StatefulWidget {
  const Locations({super.key});

  @override
  State<Locations> createState() => _LocationsState();
}

class _LocationsState extends State<Locations> {
  final c = TextEditingController();

  void send() {
    final t = c.text.trim();
    if (t.isEmpty) return;
    c.clear();
    app.chatSend(t);
  }

  @override
  Widget build(BuildContext context) {
    final s = app.step;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        h('Where to, for the ${app.veh!.name}?'),
        box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final m in app.chat)
                Align(
                  alignment:
                      m.$1 ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: m.$1
                          ? const Color(0xFF242A33)
                          : accent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      m.$2,
                      style: TextStyle(color: m.$1 ? null : bg),
                    ),
                  ),
                ),
              if (s == 'searching')
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'Looking up locations…',
                    style: TextStyle(color: muted),
                  ),
                ),
              if (s == 'pickup' || s == 'drop')
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: c,
                        onSubmitted: (_) => send(),
                        decoration: InputDecoration(
                          hintText: s == 'pickup'
                              ? 'Type your pickup location…'
                              : 'Type your drop location…',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    btn('Send', send),
                  ],
                ),
              if (s == 'error')
                btn(
                  'Start over',
                  () => app.startBooking(app.veh!),
                  primary: false,
                ),
            ],
          ),
        ),
        if (s == 'done') ...[
          const SizedBox(height: 14),
          RouteMap(
            app.pickup!,
            app.drop!,
            app.route,
            key: ValueKey(
              '${app.pickup!.lat}${app.drop!.lat}${app.km}',
            ),
          ),
          box(
            Column(
              children: [
                kv('Pickup', app.pickup!.label),
                kv('Drop', app.drop!.label),
                kv('Distance', '${app.km.toStringAsFixed(1)} km'),
                kv('Approx. drive time', '${app.mins.round()} min'),
              ],
            ),
          ),
          btn('Continue to pricing', () => app.go('duration')),
        ],
      ],
    );
  }
}

class Duration_ extends StatelessWidget {
  const Duration_({super.key});

  @override
  Widget build(BuildContext context) {
    final v = app.veh!;
    final busy = busyUntil(v.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        h('Choose your rental duration'),
        if (busy != null)
          box(
            Text(
              'This vehicle is on a trip until ${fmt(busy)}. Pick another vehicle or check back later.',
              style: const TextStyle(color: red),
            ),
            border: red,
          ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 260,
              child: box(
                const Text('🧭 Self Drive\nYou drive, no extra fee.'),
                border: !app.withDriver ? accent : null,
                onTap: () => app.u(() {
                  app.withDriver = false;
                  app.dId = null;
                  app.hours = null;
                }),
              ),
            ),
            SizedBox(
              width: 260,
              child: box(
                const Text('🧑‍✈️ With Driver\nProfessional driver included.'),
                border: app.withDriver ? accent : null,
                onTap: () => app.u(() {
                  app.withDriver = true;
                  app.hours = null;
                }),
              ),
            ),
          ],
        ),
        if (app.withDriver) ...[
          h('Choose a driver', 17),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final d in drivers)
                SizedBox(
                  width: 200,
                  child: box(
                    Text('${d.name}\n★ ${d.rating} · ${d.phone}'),
                    border: app.dId == d.id ? accent : null,
                    onTap: () => app.u(() => app.dId = d.id),
                  ),
                ),
            ],
          ),
        ],
        h('Select a package', 17),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final hrs in basePkgs.keys)
              Builder(
                builder: (_) {
                  final fee = app.withDriver ? driverFee[hrs]! : 0;
                  final disabled =
                      busy != null || (app.withDriver && app.dId == null);

                  return Opacity(
                    opacity: disabled ? .5 : 1,
                    child: SizedBox(
                      width: 200,
                      child: box(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$hrs hrs',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              money(pkgPrice(v, hrs) + fee),
                              style: const TextStyle(
                                color: accent,
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              fee > 0
                                  ? 'incl. ${money(fee)} driver fee'
                                  : 'self drive',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        border: app.hours == hrs ? accent : null,
                        onTap: disabled
                            ? null
                            : () => app.u(() => app.hours = hrs),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 20),
        btn(
          'Continue to payment',
          app.hours == null ? null : () => app.go('payment'),
        ),
      ],
    );
  }
}
class Payment extends StatefulWidget {
  const Payment({super.key});

  @override
  State<Payment> createState() => _PaymentState();
}

class _PaymentState extends State<Payment> {
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final v = app.veh!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        h('Review & pay'),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: 480,
              child: box(
                Column(
                  children: [
                    kv('Vehicle', v.name),
                    kv('Pickup', app.pickup!.label),
                    kv('Drop', app.drop!.label),
                    kv('Distance', '${app.km.toStringAsFixed(1)} km'),
                    kv('Duration', '${app.hours} hrs'),
                    kv(
                      'Driver',
                      app.withDriver ? dById(app.dId)!.name : 'Self drive',
                    ),
                    const Divider(),
                    kv(
                      '${app.hours}-hour package',
                      money(pkgPrice(v, app.hours!)),
                    ),
                    if (app.fee > 0) kv('Driver fee', money(app.fee)),
                    kv('Total', money(app.total)),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 480,
              child: box(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    h('Card details', 17),
                    const TextField(
                      decoration: InputDecoration(
                        labelText: 'Card number',
                        hintText: '4242 4242 4242 4242',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              labelText: 'Expiry',
                              hintText: 'MM/YY',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              labelText: 'CVV',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: btn(
                        busy ? 'Processing…' : 'Pay ${money(app.total)}',
                        busy
                            ? null
                            : () {
                                setState(() => busy = true);
                                Future.delayed(
                                  const Duration(milliseconds: 900),
                                  () {
                                    app.pay();
                                    if (context.mounted) {
                                      toast(
                                        context,
                                        'Payment successful — booking confirmed!',
                                      );
                                    }
                                  },
                                );
                              },
                      ),
                    ),
                    const Text(
                      'Simulated payment — no real card is charged.',
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class Confirm extends StatelessWidget {
  const Confirm({super.key});

  @override
  Widget build(BuildContext context) {
    final b = bookings.firstWhere((b) => b.id == app.lastId);

    return box(
      Column(
        children: [
          const Text('✅', style: TextStyle(fontSize: 44)),
          h('Booking confirmed'),
          Text(
            'Booking ID ${b.id}',
            style: const TextStyle(
              color: accent,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          kv('Vehicle', vName(b.vehicleId)),
          kv('Pickup → Drop', '${b.pickup.label} → ${b.drop.label}'),
          kv('Starts', fmt(b.start)),
          kv('Total paid', money(b.total)),
          const SizedBox(height: 14),
          btn('Go to My Bookings', () => app.go('mybookings')),
        ],
      ),
    );
  }
}

class MyBookings extends StatelessWidget {
  const MyBookings({super.key});

  @override
  Widget build(BuildContext context) {
    final list = bookings
        .where((b) => b.email == app.customer!['email'])
        .toList()
        .reversed
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        h('My bookings'),
        if (list.isEmpty)
          const Text(
            'No bookings yet — head to Home to book a vehicle.',
            style: TextStyle(color: muted),
          ),
        for (final b in list)
          box(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: h('${vName(b.vehicleId)} · ${b.id}', 17)),
                    badge(b.status),
                  ],
                ),
                Text(
                  '${b.pickup.label} → ${b.drop.label} · ${b.hours} hrs from ${fmt(b.start)} · ${dName(b)} · ${money(b.total)}',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    btn(
                      'Track booking',
                      () => showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: Text('Track ${b.id}'),
                          content: Text(
                            b.status == 'cancelled'
                                ? 'This booking was cancelled.'
                                : 'Status: ${b.status.toUpperCase()}\n(confirmed → ongoing → completed)',
                          ),
                        ),
                      ),
                      primary: false,
                    ),
                    if (b.status == 'confirmed')
                      btn(
                        'Cancel',
                        () => app.u(() => b.status = 'cancelled'),
                        danger: true,
                      ),
                    if (b.status == 'completed' && b.review == null)
                      btn('Leave a review', () => reviewDialog(context, b)),
                    if (b.review != null)
                      Text(
                        '★ ${b.review!.$1} — "${b.review!.$2}"',
                        style: const TextStyle(color: muted),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

void reviewDialog(BuildContext c, Booking b) {
  int stars = 0;
  final t = TextEditingController();

  showDialog(
    context: c,
    builder: (d) => StatefulBuilder(
      builder: (_, set) => AlertDialog(
        title: const Text('Leave a review'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    onPressed: () => set(() => stars = i),
                    icon: Icon(
                      i <= stars ? Icons.star : Icons.star_border,
                      color: accent,
                    ),
                  ),
              ],
            ),
            tf(t, 'How was your trip?'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              if (stars == 0) return;
              app.u(() => b.review = (stars, t.text.trim()));
              Navigator.pop(d);
            },
            child: const Text('Submit review'),
          ),
        ],
      ),
    ),
  );
}

/* =========================================================
   DRIVER
   ========================================================= */
class DriverView extends StatelessWidget {
  const DriverView({super.key});

  @override
  Widget build(BuildContext context) {
    final dr = dById(app.driverId);

    if (dr == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          h('Driver Portal — pick your profile', 26),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final d in drivers)
                SizedBox(
                  width: 250,
                  child: box(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        h(d.name, 17),
                        Text(
                          '★ ${d.rating} · ${d.phone}',
                          style: const TextStyle(color: muted),
                        ),
                        const SizedBox(height: 10),
                        btn(
                          'Login as ${d.name.split(' ')[0]}',
                          () => app.u(() => app.driverId = d.id),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
    }

    final mine = bookings.where((b) => b.driverId == dr.id);
    final active = mine.where(
      (b) => b.status != 'cancelled' && b.status != 'completed',
    );
    final hist = mine.where(
      (b) => b.status == 'completed' || b.status == 'cancelled',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            h('Welcome, ${dr.name}', 24),
            btn(
              'Log out',
              () => app.u(() => app.driverId = null),
              primary: false,
            ),
          ],
        ),
        h('Assigned trips'),
        if (active.isEmpty)
          const Text(
            'No trips assigned right now.',
            style: TextStyle(color: muted),
          ),
        for (final b in active)
          box(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: h('${vName(b.vehicleId)} · ${b.id}', 17)),
                    badge(b.status),
                  ],
                ),
                Text(
                  '${b.pickup.label} → ${b.drop.label} · ${b.hours} hrs from ${fmt(b.start)}',
                  style: const TextStyle(color: muted),
                ),
                Text('Customer: ${b.name} · ${b.phone}'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (b.driverStatus == 'pending') ...[
                      btn(
                        'Accept trip',
                        () => app.u(() => b.driverStatus = 'accepted'),
                      ),
                      btn(
                        'Reject',
                        () => app.u(() {
                          b.driverStatus = 'rejected';
                          b.status = 'cancelled';
                        }),
                        danger: true,
                      ),
                    ],
                    if (b.driverStatus == 'accepted' &&
                        b.status == 'confirmed')
                      btn(
                        'Start trip',
                        () => app.u(() => b.status = 'ongoing'),
                      ),
                    if (b.status == 'ongoing')
                      btn(
                        'Mark ride completed',
                        () => app.u(() => b.status = 'completed'),
                      ),
                    btn(
                      '📍 Navigate',
                      () => showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Pickup → Drop'),
                          content: SizedBox(
                            width: 500,
                            child: RouteMap(
                              b.pickup,
                              b.drop,
                              b.route,
                              height: 320,
                            ),
                          ),
                        ),
                      ),
                      primary: false,
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (hist.isNotEmpty) ...[
          h('Trip history'),
          for (final b in hist)
            ListTile(
              title: Text('${b.id} · ${vName(b.vehicleId)}'),
              subtitle: Text('${b.pickup.label} → ${b.drop.label}'),
              trailing: badge(b.status),
            ),
        ],
      ],
    );
  }
}

/* =========================================================
   ADMIN
   ========================================================= */
class AdminView extends StatefulWidget {
  const AdminView({super.key});

  @override
  State<AdminView> createState() => _AdminViewState();
}

class _AdminViewState extends State<AdminView> {
  final pass = TextEditingController();

  @override
  Widget build(BuildContext context) {
    if (!app.adminAuthed) {
      return Center(
        child: SizedBox(
          width: 380,
          child: box(
            Column(
              children: [
                h('Admin access'),
                const Text(
                  'Demo passcode: admin123',
                  style: TextStyle(color: accent),
                ),
                const SizedBox(height: 12),
                tf(pass, 'Passcode'),
                SizedBox(
                  width: double.infinity,
                  child: btn(
                    'Enter dashboard',
                    () => pass.text == 'admin123'
                        ? app.u(() => app.adminAuthed = true)
                        : toast(context, 'Incorrect passcode'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    const tabs = [
      'Vehicles',
      'Drivers',
      'Bookings',
      'Customers',
      'Payments',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            h('Admin dashboard', 24),
            btn(
              'Log out',
              () => app.u(() => app.adminAuthed = false),
              primary: false,
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final t in tabs)
              ChoiceChip(
                label: Text(t),
                selected: app.adminTab == t,
                onSelected: (_) => app.u(() => app.adminTab = t),
              ),
          ],
        ),
        const SizedBox(height: 14),
        switch (app.adminTab) {
          'Vehicles' => vehiclesTab(),
          'Drivers' => driversTab(),
          'Bookings' => bookingsTab(),
          'Customers' => customersTab(),
          _ => paymentsTab(),
        },
      ],
    );
  }

  Widget vehiclesTab() => Column(
        children: [
          AddForm(
            'Add vehicle (6-hr base price drives all packages)',
            ['Vehicle name', 'Type', 'Seats', '6-hour price (₹)'],
            (v) {
              app.u(
                () => vehicles.add(
                  Vehicle(
                    'V${DateTime.now().millisecondsSinceEpoch}',
                    v[0],
                    v[1],
                    int.tryParse(v[2]) ?? 4,
                    int.tryParse(v[3]) ?? 1200,
                    '🚘',
                  ),
                ),
              );
            },
          ),
          for (final v in vehicles)
            ListTile(
              title: Text('${v.icon} ${v.name}'),
              subtitle: Text(
                '${v.type} · ${v.seats} seats · 12h ${money(pkgPrice(v, 12))} · 24h ${money(pkgPrice(v, 24))}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 90,
                    child: TextFormField(
                      key: ValueKey('${v.id}${v.price}'),
                      initialValue: '${v.price}',
                      keyboardType: TextInputType.number,
                      onFieldSubmitted: (x) => app.u(
                        () => v.price = int.tryParse(x) ?? v.price,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: red),
                    onPressed: () => app.u(() => vehicles.remove(v)),
                  ),
                ],
              ),
            ),
        ],
      );

  Widget driversTab() => Column(
        children: [
          AddForm(
            'Add driver',
            ['Driver name', 'Phone'],
            (v) => app.u(
              () => drivers.add(
                Driver(
                  'D${DateTime.now().millisecondsSinceEpoch}',
                  v[0],
                  v[1],
                  5.0,
                ),
              ),
            ),
          ),
          for (final d in drivers)
            ListTile(
              title: Text(d.name),
              subtitle: Text('${d.phone} · ★ ${d.rating}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: red),
                onPressed: () => app.u(() => drivers.remove(d)),
              ),
            ),
        ],
      );

  Widget bookingsTab() {
    final list = bookings
        .where(
          (b) => app.statusFilter == 'All' || b.status == app.statusFilter,
        )
        .toList()
        .reversed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButton<String>(
          value: app.statusFilter,
          items: [
            for (final s in [
              'All',
              'confirmed',
              'ongoing',
              'completed',
              'cancelled',
            ])
              DropdownMenuItem(value: s, child: Text(s)),
          ],
          onChanged: (v) => app.u(() => app.statusFilter = v!),
        ),
        if (list.isEmpty)
          const Text(
            'No bookings found.',
            style: TextStyle(color: muted),
          ),
        for (final b in list)
          ListTile(
            title: Text('${b.id} · ${b.name} · ${vName(b.vehicleId)}'),
            subtitle: Text(
              '${b.pickup.label} → ${b.drop.label} · ${b.hours}h · ${dName(b)} · ${money(b.total)}',
            ),
            trailing: badge(b.status),
          ),
      ],
    );
  }

  Widget customersTab() {
    final m = <String, (String, String, int, int)>{};

    for (final b in bookings) {
      final o = m[b.email];
      m[b.email] = (
        b.name,
        b.phone,
        (o?.$3 ?? 0) + 1,
        (o?.$4 ?? 0) + b.total,
      );
    }

    return Column(
      children: [
        if (m.isEmpty)
          const Text(
            'No customers yet.',
            style: TextStyle(color: muted),
          ),
        for (final e in m.entries)
          ListTile(
            title: Text(e.value.$1),
            subtitle: Text('${e.key} · ${e.value.$2}'),
            trailing: Text(
              '${e.value.$3} bookings · ${money(e.value.$4)}',
            ),
          ),
      ],
    );
  }

  Widget paymentsTab() => Column(
        children: [
          box(
            kv(
              'Total revenue collected',
              money(
                bookings
                    .where((b) => b.payment == 'paid')
                    .fold(0, (s, b) => s + b.total),
              ),
            ),
          ),
          for (final b in bookings.reversed)
            ListTile(
              title: Text('${b.id} · ${b.name}'),
              subtitle: Text(money(b.total)),
              trailing: badge(b.payment),
            ),
        ],
      );
}