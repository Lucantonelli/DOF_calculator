import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math';

void main() {
  runApp(const DofApp());
}

class DofApp extends StatelessWidget {
  const DofApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DoF Calculator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1a1a2e)),
        useMaterial3: true,
      ),
      home: const DofScreen(),
    );
  }
}

// --- Modelli dati ---

class CameraFormat {
  final String name;
  final double coc;
  const CameraFormat(this.name, this.coc);
}

const formats = [
  CameraFormat('35mm', 0.029),
  CameraFormat('APS-C', 0.019),
  CameraFormat('6×4.5', 0.047),
  CameraFormat('6×6', 0.059),
  CameraFormat('4×5"', 0.100),
];

const apertures = [1.4, 2.0, 2.8, 4.0, 5.6, 8.0, 11.0, 16.0];
const snapFocals = [14, 24, 28, 35, 50, 75, 85, 90, 105, 135, 150, 200, 300];
const double snapRadius = 6.0;

class Preset {
  final String name;
  final int formatIndex;
  final double focal;
  final int apertureIndex;
  final double dist;

  Preset({
    required this.name,
    required this.formatIndex,
    required this.focal,
    required this.apertureIndex,
    required this.dist,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'formatIndex': formatIndex,
        'focal': focal,
        'apertureIndex': apertureIndex,
        'dist': dist,
      };

  factory Preset.fromJson(Map<String, dynamic> j) => Preset(
        name: j['name'],
        formatIndex: j['formatIndex'],
        focal: j['focal'],
        apertureIndex: j['apertureIndex'],
        dist: j['dist'],
      );
}

// --- Calcoli ---

class DofResult {
  final double near;
  final double far;
  final double total;
  final double hyperfocal;
  const DofResult({
    required this.near,
    required this.far,
    required this.total,
    required this.hyperfocal,
  });
}

DofResult calcDof(double focalMm, double fNumber, double distM, double cocMm) {
  final f = focalMm;
  final d = distM * 1000;
  final H = (f * f) / (fNumber * cocMm) + f;
  final near = (d * (H - f)) / (H + d - 2 * f) / 1000;
  final double far;
  if (d >= H - f) {
    far = double.infinity;
  } else {
    far = (d * (H - f)) / (H - d) / 1000;
  }
  final total = far == double.infinity ? double.infinity : far - near;
  return DofResult(near: near, far: far, total: total, hyperfocal: H / 1000);
}

String fmtM(double m) {
  if (m == double.infinity || m > 9999) return '∞';
  if (m >= 100) return '${m.toStringAsFixed(0)} m';
  if (m >= 10) return '${m.toStringAsFixed(1)} m';
  return '${m.toStringAsFixed(2)} m';
}

double applySnap(double value) {
  for (final snap in snapFocals) {
    if ((value - snap).abs() <= snapRadius) return snap.toDouble();
  }
  return value;
}

// Scala logaritmica distanza: 0.3 m → 500 m
double sliderToMeters(double t) {
  const minLog = -0.5228787452803376; // log10(0.3)
  const maxLog = 2.6989700043360187;  // log10(500)
  return pow(10, minLog + t * (maxLog - minLog)).toDouble();
}

double metersToSlider(double m) {
  const minLog = -0.5228787452803376;
  const maxLog = 2.6989700043360187;
  return (log(m) / ln10 - minLog) / (maxLog - minLog);
}

// --- Schermata principale ---

class DofScreen extends StatefulWidget {
  const DofScreen({super.key});
  @override
  State<DofScreen> createState() => _DofScreenState();
}

class _DofScreenState extends State<DofScreen> {
  int _formatIndex = 0;
  double _focal = 50;
  int _apertureIndex = 4;
  double _dist = 3.0;
  List<Preset> _presets = [];

  static const _dark = Color(0xFF1a1a2e);
  static const _gold = Color(0xFFe8c97a);
  static const _prefsKey = 'dof_presets';

  @override
  void initState() {
    super.initState();
    _loadPresets();
  }

  // --- Persistenza ---

  Future<void> _loadPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      final List decoded = jsonDecode(raw);
      setState(() {
        _presets = decoded.map((e) => Preset.fromJson(e)).toList();
      });
    }
  }

  Future<void> _savePresets() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKey, jsonEncode(_presets.map((p) => p.toJson()).toList()));
  }

  void _addPreset(String name) {
    setState(() {
      _presets.add(Preset(
        name: name,
        formatIndex: _formatIndex,
        focal: _focal,
        apertureIndex: _apertureIndex,
        dist: _dist,
      ));
    });
    _savePresets();
  }

  void _loadPreset(Preset p) {
    setState(() {
      _formatIndex = p.formatIndex;
      _focal = p.focal;
      _apertureIndex = p.apertureIndex;
      _dist = p.dist;
    });
  }

  void _deletePreset(int index) {
    setState(() => _presets.removeAt(index));
    _savePresets();
  }

  // --- Dialog salva preset ---

  void _showSaveDialog() {
    final controller = TextEditingController();
    controller.text =
        '${formats[_formatIndex].name} ${_focal.toStringAsFixed(0)}mm f/${apertures[_apertureIndex]}';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Salva preset',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Nome del preset',
            hintStyle: const TextStyle(color: Colors.black38),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.black12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF1a1a2e)),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla',
                style: TextStyle(color: Colors.black45)),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                _addPreset(name);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Preset "$name" salvato'),
                    backgroundColor: _dark,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('Salva',
                style: TextStyle(
                    color: Color(0xFF1a1a2e),
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // --- Dialog conferma eliminazione ---

  void _showDeleteDialog(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Elimina preset',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        content: Text('Eliminare "${_presets[index].name}"?',
            style: const TextStyle(color: Colors.black54)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla',
                style: TextStyle(color: Colors.black45)),
          ),
          TextButton(
            onPressed: () {
              _deletePreset(index);
              Navigator.pop(ctx);
            },
            child: const Text('Elimina',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final fmt = formats[_formatIndex];
    final result =
        calcDof(_focal, apertures[_apertureIndex], _dist, fmt.coc);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildFormatCard(),
              const SizedBox(height: 12),
              _buildParamsCard(),
              const SizedBox(height: 12),
              _buildResultsCard(result),
              const SizedBox(height: 12),
              if (_presets.isNotEmpty) _buildPresetsCard(),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'CoC: ${fmt.coc} mm · formula classica',
                  style:
                      const TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: _dark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.camera, color: _gold, size: 26),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DoF Calculator',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w500)),
                SizedBox(height: 2),
                Text('Profondità di campo',
                    style:
                        TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          GestureDetector(
            onTap: _showSaveDialog,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: _gold.withOpacity(0.4), width: 0.5),
              ),
              child: Row(
                children: const [
                  Icon(Icons.bookmark_add_outlined,
                      color: _gold, size: 15),
                  SizedBox(width: 5),
                  Text('Salva',
                      style: TextStyle(
                          color: _gold,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatCard() {
    return _Card(
      label: 'FOTOCAMERA',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(formats.length, (i) {
          final selected = i == _formatIndex;
          return GestureDetector(
            onTap: () => setState(() => _formatIndex = i),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? _dark : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: selected ? _dark : Colors.black26,
                    width: 0.5),
              ),
              child: Text(formats[i].name,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: selected ? _gold : Colors.black54)),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildParamsCard() {
    return _Card(
      label: 'PARAMETRI OTTICI',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- FOCALE ---
          _ParamRow(
            icon: Icons.center_focus_strong_outlined,
            label: 'Focale',
            value: '${_focal.toStringAsFixed(0)} mm',
            isSnapped: snapFocals.contains(_focal.toInt()) &&
                _focal == _focal.roundToDouble(),
          ),
          Slider(
            value: _focal,
            min: 14,
            max: 300,
            divisions: 286,
            activeColor: _dark,
            onChanged: (v) => setState(() => _focal = applySnap(v)),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: snapFocals.map((f) {
                final isActive = _focal.toInt() == f &&
                    _focal == _focal.roundToDouble();
                return GestureDetector(
                  onTap: () => setState(() => _focal = f.toDouble()),
                  child: Text('$f',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color:
                              isActive ? _dark : Colors.black26)),
                );
              }).toList(),
            ),
          ),

          // --- DIAFRAMMA ---
          _ParamRow(
            icon: Icons.camera_outlined,
            label: 'Diaframma',
            value: 'f/${apertures[_apertureIndex]}',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(apertures.length, (i) {
              final selected = i == _apertureIndex;
              return GestureDetector(
                onTap: () => setState(() => _apertureIndex = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? _dark : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: selected ? _dark : Colors.black26,
                        width: 0.5),
                  ),
                  child: Text('f/${apertures[i]}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: selected ? _gold : Colors.black54)),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),

          // --- DISTANZA (scala logaritmica 0.3–500 m) ---
          _ParamRow(
            icon: Icons.straighten_outlined,
            label: 'Distanza',
            value: '${_dist.toStringAsFixed(1)} m',
          ),
          Slider(
            value: metersToSlider(_dist).clamp(0.0, 1.0),
            min: 0.0,
            max: 1.0,
            activeColor: _dark,
            onChanged: (v) =>
                setState(() => _dist = sliderToMeters(v)),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('0.3 m',
                    style:
                        TextStyle(fontSize: 9, color: Colors.black26)),
                Text('1 m',
                    style:
                        TextStyle(fontSize: 9, color: Colors.black26)),
                Text('10 m',
                    style:
                        TextStyle(fontSize: 9, color: Colors.black26)),
                Text('100 m',
                    style:
                        TextStyle(fontSize: 9, color: Colors.black26)),
                Text('500 m',
                    style:
                        TextStyle(fontSize: 9, color: Colors.black26)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsCard(DofResult r) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _dark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PROFONDITÀ DI CAMPO',
                      style: TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                          letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(fmtM(r.total),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w500)),
                  const Text('totale',
                      style: TextStyle(
                          color: Colors.white38, fontSize: 12)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('IPERFOCALE',
                      style: TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                          letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(fmtM(r.hyperfocal),
                      style: const TextStyle(
                          color: _gold,
                          fontSize: 18,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 28),
          _ResultRow(label: '↑ Piano anteriore', value: fmtM(r.near)),
          const SizedBox(height: 6),
          _ResultRow(
              label: '↓ Piano posteriore', value: fmtM(r.far)),
          const SizedBox(height: 20),
          const Text('ZONA A FUOCO',
              style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  letterSpacing: 1)),
          const SizedBox(height: 8),
          _buildScaleBar(r),
        ],
      ),
    );
  }

  Widget _buildScaleBar(DofResult r) {
    final double scaleMax = r.far == double.infinity
        ? _dist * 2.5
        : (r.far * 1.15).clamp(_dist * 2.0, 9999);
    final double nearPct = (r.near / scaleMax).clamp(0.0, 1.0);
    final double farPct = r.far == double.infinity
        ? 1.0
        : (r.far / scaleMax).clamp(0.0, 1.0);
    final double focusPct = (_dist / scaleMax).clamp(0.0, 1.0);

    return Column(
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final w = constraints.maxWidth;
          return Stack(children: [
            Container(
              height: 8,
              decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(4)),
            ),
            Positioned(
              left: nearPct * w,
              width: (farPct - nearPct) * w,
              top: 0,
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                    color: const Color(0xFFe8c97a).withOpacity(0.7),
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
            Positioned(
              left: (focusPct * w - 1.5).clamp(0, w - 3),
              top: -3,
              child: Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ]);
        }),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('0',
                style:
                    TextStyle(color: Colors.white38, fontSize: 10)),
            Text(
              r.far == double.infinity
                  ? '${fmtM(r.near)} — ∞'
                  : '${fmtM(r.near)} — ${fmtM(r.far)}',
              style: const TextStyle(
                  color: Color(0xFFe8c97a), fontSize: 10),
            ),
            Text(fmtM(scaleMax),
                style: const TextStyle(
                    color: Colors.white38, fontSize: 10)),
          ],
        ),
      ],
    );
  }

  Widget _buildPresetsCard() {
    return _Card(
      label: 'PRESET SALVATI',
      child: Column(
        children: List.generate(_presets.length, (i) {
          final p = _presets[i];
          return GestureDetector(
            onLongPress: () => _showDeleteDialog(i),
            onTap: () {
              _loadPreset(p);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Preset "${p.name}" caricato'),
                  backgroundColor: _dark,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8F8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12, width: 0.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bookmark_outline,
                      size: 16, color: Color(0xFF8b7fd4)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(p.name,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ),
                  Text(
                    '${formats[p.formatIndex].name} · '
                    '${p.focal.toStringAsFixed(0)}mm · '
                    'f/${apertures[p.apertureIndex]} · '
                    '${p.dist.toStringAsFixed(1)}m',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.black38),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

// --- Widget helper ---

class _Card extends StatelessWidget {
  final String label;
  final Widget child;
  const _Card({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.black45,
                  letterSpacing: 1)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ParamRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isSnapped;
  const _ParamRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isSnapped = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF8b7fd4)),
        const SizedBox(width: 10),
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: Colors.black54))),
        if (isSnapped)
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1a1a2e),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text('●',
                style: TextStyle(
                    fontSize: 7, color: Color(0xFFe8c97a))),
          ),
        Text(value,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;
  const _ResultRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 12, color: Colors.white38)),
        Text(value,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFFe8c97a))),
      ],
    );
  }
}
