import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:math_expressions/math_expressions.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CalculatorApp());
}

class CalculatorApp extends StatelessWidget {
  const CalculatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kalkulator Pro UI/UX',
      theme: ThemeData(
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      ),
      home: const CalculatorScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  // Variabel jauh lebih ramping dan bersih
  String _history = "";         // Baris 1: Susunan lengkap
  String _previewResult = "";   // Baris 2: Jawaban sementara
  String _output = "0";         // Baris 3: Tampilan utama
  String _expression = "";      // String mentah untuk dihitung engine math_expressions
  
  bool _isResultDisplayed = false;
  bool _isLandscapeLocked = false;

  final Color textDark = const Color(0xFF8F8F8F);
  final Color textLight = const Color(0xFFB3B3B3);
  final Color bgWhite = Colors.white;
  final Color bgKeypad = const Color(0xFFFFFFFF);

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _triggerSound(String type) async {
    AudioPlayer player = AudioPlayer();
    await player.play(
      AssetSource('audio/clickeffect.wav'),
      mode: PlayerMode.lowLatency,
    );
    player.onPlayerComplete.listen((event) {
      player.dispose();
    });
  }

  Future<void> _copyToClipboard() async {
    if (_output == "Error" || _output == "0") return;

    try {
      await Clipboard.setData(ClipboardData(text: _output));
      _triggerSound("click");
      if (!mounted) return;
      bool isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
      double screenWidth = MediaQuery.of(context).size.width;

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Disalin!',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF00C853),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(
            bottom: isPortrait ? 30 : 10,
            left: isPortrait ? screenWidth * 0.3 : screenWidth * 0.4,
            right: isPortrait ? screenWidth * 0.3 : screenWidth * 0.4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      );
    } catch (e) {
      debugPrint("Gagal menyalin: $e");
    }
  }

  String _formatNumber(double n) {
  if (n.isNaN) {
      return "Error"; 
    }
    if (n.isInfinite) {
      return "Terlalu Besar"; // <-- UX yang lebih manusiawi
    }
    
    if (n == n.toInt()) return n.toInt().toString();
    
    String str = n.toString();
    if (str.length > 10) {
      str = n.toStringAsFixed(8).replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return str;
  }

  String _formatDisplay(String val) {
    if (val == "Error" || val == "Infinity" || val == "NaN") return "Error";
    if (val.isEmpty) return "0";

    // Konversi string mentah menjadi format rapi (contoh: 2.500,5)
    // Abaikan jika ada karakter matematika (hanya format angka akhir)
    if (RegExp(r'[+\-×÷^!()scl√]').hasMatch(val)) {
      return val.replaceAll('.', ','); 
    }

    List<String> parts = val.replaceAll(',', '.').split('.');
    String intPart = parts[0];
    String decPart = parts.length > 1 ? parts[1] : "";
    String sign = "";

    if (intPart.startsWith("-")) {
      sign = "-";
      intPart = intPart.substring(1);
    }

    String formattedInt = "";
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) formattedInt = ".$formattedInt";
      formattedInt = intPart[intPart.length - 1 - i] + formattedInt;
    }

    if (parts.length > 1) {
      return "$sign$formattedInt,$decPart";
    }
    if (val.contains('.')) {
      return "$sign$formattedInt,";
    }
    return "$sign$formattedInt";
  }

  // FUNGSI BARU: Menambahkan kurung tutup otomatis
  String _autoCloseParentheses(String expr) {
    int openCount = expr.split('(').length - 1;
    int closeCount = expr.split(')').length - 1;
    String result = expr;
    // Tambahkan ')' sampai jumlahnya sama
    while (openCount > closeCount) {
      result += ')';
      closeCount++;
    }
    return result;
  }

  // --- MESIN HITUNG UTAMA ---
  String _evaluateMath(String expr) {
    if (expr.isEmpty) return "";
    try {
      String balancedExpr = _autoCloseParentheses(expr);
      // 1. Ubah simbol UI ke simbol yang dikenali mesin
      String finalExpr = expr
          .replaceAll('×', '*')
          .replaceAll('÷', '/')
          .replaceAll(',', '.')
          .replaceAll('π', math.pi.toString())
          .replaceAll('e', math.e.toString())
          .replaceAll('√', 'sqrt')
          .replaceAll('log(', 'log(10,'); // log default ke basis 10 di package ini

      // 2. Akali faktorial (!) menggunakan Regex, karena package tidak support '!'
      finalExpr = finalExpr.replaceAllMapped(RegExp(r'(\d+)!'), (Match m) {
        try {
          int val = int.parse(m[1]!);
          
          // Lempar peringatan spesifik jika angkanya di atas limit
          if (val > 170) throw const FormatException("OVERLOAD"); 
          
          double res = 1;
          for (int i = 1; i <= val; i++) {
            res *= i;
          }
          return res.toString();
        } catch (e) {
          if (e is FormatException && e.message == "OVERLOAD") {
             rethrow; // Lempar ke blok catch utama di bawah
          }
          throw const FormatException("ERROR");
        }
      });

      // 3. Akali persen (%)
      finalExpr = finalExpr.replaceAll('%', '/100');

      // 4. Proses perhitungan
// 4. Proses perhitungan
      final p = Parser();
      final exp = p.parse(finalExpr);
      final cm = ContextModel();
      final eval = exp.evaluate(EvaluationType.REAL, cm);

      return _formatNumber(eval);
    } catch (e) {
      // UX PRO: Tangkap pesan spesifik untuk ditampilkan ke layar
      if (e is FormatException && e.message == "OVERLOAD") {
        return "Terlalu Besar";
      }
      return "";
    }
  }

  void _updatePreview() {
    if (_expression.isEmpty) {
      _previewResult = "";
      return;
    }
    
    String tempResult = _evaluateMath(_expression);
    
    if (tempResult.isNotEmpty && tempResult != "Error") {
      // Hanya tampilkan preview jika ada operator (bukan cuma ngetik "5")
      if (RegExp(r'[+\-×÷^!()scl√%]').hasMatch(_expression)) {
        _previewResult = "= ${_formatDisplay(tempResult)}";
      } else {
        _previewResult = "";
      }
    } else {
      _previewResult = ""; 
    }
  }

  void _buttonPressed(String buttonText) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    setState(() {
      // 1. ROTASI
      if (buttonText == "ROTATE") {
        _triggerSound("click");
        _isLandscapeLocked = !_isLandscapeLocked;
        if (_isLandscapeLocked) {
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        } else {
          SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        }
        return;
      }

      // 2. CLEAR
      if (buttonText == "C") {
        _triggerSound("click");
        _history = "";
        _previewResult = "";
        _output = "0";
        _expression = "0";
        _isResultDisplayed = false;
        return;
      }

      // 3. BACKSPACE
      if (buttonText == "⌫") {
        _triggerSound("click");
        if (_isResultDisplayed || _output == "Error") {
          _output = "0";
          _expression = "0"; // <-- Pastikan kembali ke "0"
          _isResultDisplayed = false;
        } else if (_expression.isNotEmpty) {
          _expression = _expression.substring(0, _expression.length - 1);
          
          // <-- TAMBAHKAN INI: Jika habis dihapus, paksa jadi "0"
          if (_expression.isEmpty || _expression == "-") {
            _expression = "0"; 
          }
          
          _output = _expression.replaceAll('.', ',');
        }
        _updatePreview();
        return;
      }

      // 4. SAMA DENGAN
// 4. SAMA DENGAN
      if (buttonText == "=") {
        _triggerSound("click");
        
        // AUTO-CORRECT UI: Pakaikan kurung tutup ke layar sebelum dipindah ke history
        _expression = _autoCloseParentheses(_expression);
        
        String finalResult = _evaluateMath(_expression);
        
        // Izinkan teks "Terlalu Besar" lolos ke layar utama
        if (finalResult.isNotEmpty && finalResult != "Error") {
          _history = _expression.replaceAll('.', ','); 
          _expression = finalResult.replaceAll('.', ','); 
          
          _output = (finalResult == "Terlalu Besar") ? finalResult : _formatDisplay(_expression);
          
          _previewResult = "";
          _isResultDisplayed = true;
        } else {
          _triggerSound("error");
          _output = "Error";
        }
        return;
      }
      // 5. SEMUA TOMBOL LAINNYA (Angka, Operator, Simbol Ilmiah)
      _triggerSound("click");
      
      // Satpam 1: Cegah nol ganda di awal
      if ((buttonText == "0" || buttonText == "00") && (_expression.isEmpty || _expression == "0")) {
        _expression = "0"; // Paksa internalnya menjadi 0 tunggal
        _output = "0";     // Pastikan tampilannya tetap 0
        return;            // Hentikan eksekusi
      }

      // <-- TAMBAHKAN SATPAM 2 INI: Cegah tabrakan operator -->
      if (RegExp(r'^[+\-×÷^]$').hasMatch(buttonText)) {
        if (_expression.isNotEmpty && _expression != "0") {
          String lastChar = _expression.substring(_expression.length - 1);
          // Jika karakter terakhir sudah operator, GANTI dengan operator baru
          if (RegExp(r'[+\-×÷^]').hasMatch(lastChar)) {
            _expression = _expression.substring(0, _expression.length - 1) + buttonText;
            _output = _expression.replaceAll('.', ',');
            _updatePreview();
            return; // Berhenti di sini, jangan jalankan kode ke bawah
          }
        }
      }
      // <------------------------------------------------------->
      String appendStr = buttonText;
      
      // Sesuaikan penulisan simbol ilmiah agar pakai kurung
      if (buttonText == "sin" || buttonText == "cos" || buttonText == "tan" || buttonText == "log" || buttonText == "ln") {
        appendStr = "$buttonText(";
      } else if (buttonText == "√") {
        appendStr = "√(";
      }

      if (_isResultDisplayed) {
        // Jika hasil sudah keluar dan ditekan operator, sambung rumusnya
        if (RegExp(r'^[+\-×÷^%]$').hasMatch(buttonText)) {
          _expression = _output.replaceAll(',', '.') + appendStr;
        } else {
          // Jika diketik angka baru, reset semuanya
          _expression = appendStr;
        }
        _isResultDisplayed = false;
      } else {
        if (_expression == "0" && !RegExp(r'^[+\-×÷^%]$').hasMatch(buttonText) && buttonText != ",") {
          _expression = appendStr;
        } else {
          _expression += appendStr;
        }
      }
      
      _output = _expression.replaceAll('.', ',');
      _updatePreview();
    });
  }

  Color _getOverlayColor(String text, bool isMainAction) {
    if (text == "C") return Colors.red.withValues(alpha: 0.2);
    if (isMainAction) return Colors.black.withValues(alpha: 0.1);
    if (text == "+" || text == "-" || text == "×" || text == "÷") {
      return const Color(0xFF00C853).withValues(alpha: 0.1);
    }
    return Colors.grey.withValues(alpha: 0.1);
  }

  Widget _buildButton(
    String text,
    double scaleW, {
    Color? bgColor,
    Color? textColor,
    bool isMainAction = false,
    IconData? icon,
  }) {
    bool isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;

    return Expanded(
      child: Container(
        margin: EdgeInsets.all(1.5 * scaleW),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: bgColor ?? bgWhite,
            foregroundColor: textColor ?? textDark,
            elevation: 0,
            splashFactory: InkRipple.splashFactory,
            overlayColor: _getOverlayColor(text, isMainAction),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(isMainAction ? 16 * scaleW : 8 * scaleW),
            ),
            padding: EdgeInsets.symmetric(vertical: isPortrait ? 20 * scaleW : 0),
          ),
          onPressed: () => _buttonPressed(text),
          child: icon != null
              ? Icon(icon, size: 28 * scaleW, color: textColor ?? textDark)
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 28 * scaleW,
                      fontWeight: isMainAction ? FontWeight.bold : FontWeight.w400,
                    ),
                  ),
                ),
        ),
      ),
    );
  }

Widget _buildPortraitLayout(double scaleW) {
    return Column(
      children: [
        // Baris 1: Kontrol & Kurung
        Expanded(
          child: Row(
            children: [
              _buildButton(
                "ROTATE",
                scaleW,
                textColor: _isLandscapeLocked ? Colors.redAccent : const Color(0xFF00C853),
                icon: _isLandscapeLocked ? Icons.screen_lock_landscape : Icons.screen_rotation,
              ),
              _buildButton("(", scaleW, textColor: const Color(0xFF00C853)),
              _buildButton(")", scaleW, textColor: const Color(0xFF00C853)),
              _buildButton("⌫", scaleW, textColor: Colors.redAccent), // Tombol hapus kembali hadir!
            ],
          ),
        ),
        // Baris 2: Reset & Operator Tambahan
        Expanded(
          child: Row(
            children: [
              _buildButton("C", scaleW, textColor: Colors.redAccent, isMainAction: true),
              _buildButton("%", scaleW, textColor: const Color(0xFF00C853)),
              _buildButton("^", scaleW, textColor: const Color(0xFF00C853)),
              _buildButton("÷", scaleW, textColor: const Color(0xFF00C853)),
            ],
          ),
        ),
        // Baris 3: Angka Atas
        Expanded(
          child: Row(
            children: [
              _buildButton("7", scaleW),
              _buildButton("8", scaleW),
              _buildButton("9", scaleW),
              _buildButton("×", scaleW, textColor: const Color(0xFF00C853)),
            ],
          ),
        ),
        // Baris 4: Angka Tengah
        Expanded(
          child: Row(
            children: [
              _buildButton("4", scaleW),
              _buildButton("5", scaleW),
              _buildButton("6", scaleW),
              _buildButton("-", scaleW, textColor: const Color(0xFF00C853)),
            ],
          ),
        ),
        // Baris 5: Angka Bawah
        Expanded(
          child: Row(
            children: [
              _buildButton("1", scaleW),
              _buildButton("2", scaleW),
              _buildButton("3", scaleW),
              _buildButton("+", scaleW, textColor: const Color(0xFF00C853)),
            ],
          ),
        ),
        // Baris 6: Nol & Sama Dengan
        Expanded(
          child: Row(
            children: [
              _buildButton("00", scaleW), // Tambahan fitur Pro untuk nominal
              _buildButton("0", scaleW),
              _buildButton(",", scaleW),
              _buildButton("=", scaleW, bgColor: const Color(0xFF00C853), textColor: Colors.white, isMainAction: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(double scaleW) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _buildButton("sin", scaleW, textColor: textLight),
                    _buildButton("cos", scaleW, textColor: textLight),
                    _buildButton("tan", scaleW, textColor: textLight),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    _buildButton("√", scaleW, textColor: textLight),
                    _buildButton("π", scaleW, textColor: textLight),
                    _buildButton("^", scaleW, textColor: textLight),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    _buildButton("log", scaleW, textColor: textLight),
                    _buildButton("ln", scaleW, textColor: textLight),
                    _buildButton("e", scaleW, textColor: textLight),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    _buildButton("⌫", scaleW, textColor: Colors.redAccent), // Tombol hapus pindah sini di landscape
                    _buildButton("%", scaleW, textColor: textLight),
                    _buildButton("!", scaleW, textColor: textLight),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 4 * scaleW),
        Expanded(flex: 4, child: _buildPortraitLayout(scaleW)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    bool isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    double rawScaleW = isPortrait ? (screenWidth / 412) : (screenWidth / 800);
    double scaleW = rawScaleW.clamp(0.6, 1.2);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // Layar dasar abu-abu
      // KITA HAPUS SafeArea GLOBAL DARI SINI
      body: Column(
        children: [
          // ==========================================
          // 1. AREA TAMPILAN ATAS (ABU-ABU)
          // ==========================================
          Expanded(
            flex: isPortrait ? 4 : 3,
            child: SafeArea(
              bottom: false, // Pasang SafeArea khusus untuk teks agar tidak nabrak poni
              child: GestureDetector(
                onHorizontalDragEnd: (details) => _buttonPressed("⌫"),
                onLongPress: _copyToClipboard,
                child: Container(
                  width: double.infinity,
                  alignment: Alignment.bottomRight,
                  color: Colors.transparent,
                  padding: EdgeInsets.symmetric(
                    horizontal: 24 * scaleW,
                    vertical: isPortrait ? 16 * scaleW : 4 * scaleW,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomRight,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _history.isEmpty ? "" : _history,
                          style: TextStyle(fontSize: 30* scaleW, color: textLight),
                          maxLines: 1,
                        ),
                        SizedBox(height: 4 * scaleW),
                        Text(
                          _previewResult,
                          style: TextStyle(
                            fontSize: 34 * scaleW,
                            color: const Color(0xFF00C853).withValues(alpha: 0.6),
                            fontWeight: FontWeight.w400,
                          ),
                          maxLines: 1,
                        ),
                        SizedBox(height: 8 * scaleW),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 100),
                          child: Text(
                            _output,
                            key: ValueKey<String>(_output),
                            style: TextStyle(
                              fontSize: 58 * scaleW,
                              fontWeight: FontWeight.w300,
                              color: textDark,
                            ),
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ==========================================
          // 2. AREA TOMBOL BAWAH (PUTIH FULL EDGE)
          // ==========================================
          Expanded(
            flex: isPortrait ? 7 : 5,
            child: Container(
              width: double.infinity, // Paksa warna background mentok kiri kanan
              decoration: BoxDecoration(
                color: bgKeypad, // Warna putih papan tombol
                border: Border(
                  top: BorderSide(
                    color: Colors.grey.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
              ),
              // Pasang SafeArea di SINI agar tombolnya yang geser, bukan background putihnya
              child: SafeArea(
                top: false, 
                child: Padding(
                  padding: EdgeInsets.fromLTRB(4 * scaleW, 0, 4 * scaleW, 0),
                  child: isPortrait ? _buildPortraitLayout(scaleW) : _buildLandscapeLayout(scaleW),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}