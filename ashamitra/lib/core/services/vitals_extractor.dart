// ─────────────────────────────────────────────────────────────────────────────
// VitalsExtractor — Priority 1: Vitals collection from free speech
//
// Parses spoken vital signs from any language/dialect:
//   - Blood pressure: "BP ১৪০/৯০", "bp 140 over 90", "BP ek sau chalis"
//   - Temperature: "জ্বর ১০২", "temp 38.5", "bukhar 101"
//   - MUAC: "MUAC ১১", "muac 11.5 cm"
//   - SpO2: "অক্সিজেন ৯২", "spo2 94", "oxygen 88"
//   - Weight: "ওজন ১.২", "weight 1.5 kg"
//   - Respiratory rate: "শ্বাস ৬৫", "rr 70", "breathing 60"
//
// Returns Map<String, double> matching RuleExecutor vitals keys:
//   systolic_bp, diastolic_bp, temperature_c, muac_cm, spo2,
//   weight_kg, respiratory_rate
// ─────────────────────────────────────────────────────────────────────────────

class VitalsExtractor {
  // ── Bengali digit map ─────────────────────────────────────────────────────
  static const _bnDigits = {
    '০': '0', '১': '1', '২': '2', '৩': '3', '৪': '4',
    '৫': '5', '৬': '6', '৭': '7', '৮': '8', '৯': '9',
  };

  /// Extract all vitals from a spoken input string.
  /// Returns only the vitals that were clearly mentioned.
  static Map<String, double> extract(String input) {
    final text = _normalise(input);
    final vitals = <String, double>{};

    _extractBP(text, vitals);
    _extractTemperature(text, vitals);
    _extractMuac(text, vitals);
    _extractSpO2(text, vitals);
    _extractWeight(text, vitals);
    _extractRespiratoryRate(text, vitals);

    return vitals;
  }

  // ── Normalise: convert Bengali digits, lowercase ──────────────────────────
  static String _normalise(String input) {
    var text = input.toLowerCase();
    for (final entry in _bnDigits.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    // Replace Bengali decimal separator
    text = text.replaceAll('।', '.').replaceAll(',', '.');
    return text;
  }

  // ── Blood Pressure ────────────────────────────────────────────────────────
  // Patterns: "140/90", "140 over 90", "140 by 90", "ek sau chalis by nabbe"
  static void _extractBP(String text, Map<String, double> vitals) {
    // Numeric pattern: 140/90 or 140 / 90
    final numericBP = RegExp(r'(\d{2,3})\s*[/\\]\s*(\d{2,3})');
    final m = numericBP.firstMatch(text);
    if (m != null) {
      final sys = double.tryParse(m.group(1)!);
      final dia = double.tryParse(m.group(2)!);
      if (sys != null && dia != null && sys > 60 && sys < 250 && dia > 40 && dia < 150) {
        vitals['systolic_bp'] = sys;
        vitals['diastolic_bp'] = dia;
        return;
      }
    }

    // "over" / "by" pattern: "140 over 90", "140 by 90"
    final overBP = RegExp(r'(\d{2,3})\s+(?:over|by|upon|upar)\s+(\d{2,3})');
    final m2 = overBP.firstMatch(text);
    if (m2 != null) {
      final sys = double.tryParse(m2.group(1)!);
      final dia = double.tryParse(m2.group(2)!);
      if (sys != null && dia != null) {
        vitals['systolic_bp'] = sys;
        vitals['diastolic_bp'] = dia;
      }
    }

    // BP keyword + single number (systolic only)
    if (text.contains('bp') || text.contains('blood pressure') ||
        text.contains('রক্তচাপ') || text.contains('বিপি')) {
      final single = RegExp(r'(?:bp|blood pressure|রক্তচাপ|বিপি)\D{0,10}(\d{2,3})');
      final m3 = single.firstMatch(text);
      if (m3 != null) {
        final sys = double.tryParse(m3.group(1)!);
        if (sys != null && sys > 60 && sys < 250) {
          vitals['systolic_bp'] = sys;
        }
      }
    }
  }

  // ── Temperature ───────────────────────────────────────────────────────────
  // Patterns: "জ্বর ১০২", "temp 38.5", "temperature 101 f", "bukhar 99"
  static void _extractTemperature(String text, Map<String, double> vitals) {
    final tempKeywords = [
      'temperature', 'temp', 'জ্বর', 'তাপমাত্রা', 'bukhar', 'jwar', 'tap',
      'fever', 'jor',
    ];

    for (final kw in tempKeywords) {
      if (!text.contains(kw)) continue;
      final pattern = RegExp('$kw\\D{0,10}(\\d{2,3}(?:\\.\\d)?)');
      final m = pattern.firstMatch(text);
      if (m != null) {
        var temp = double.tryParse(m.group(1)!);
        if (temp == null) continue;
        // Convert Fahrenheit to Celsius if > 45 (clearly Fahrenheit)
        if (temp > 45) temp = (temp - 32) * 5 / 9;
        if (temp > 34 && temp < 43) {
          vitals['temperature_c'] = double.parse(temp.toStringAsFixed(1));
          return;
        }
      }
    }

    // Standalone temperature number near degree symbol
    final degreePattern = RegExp(r'(\d{2,3}(?:\.\d)?)\s*(?:°|degree|डिग्री|ডিগ্রি)');
    final m = degreePattern.firstMatch(text);
    if (m != null) {
      var temp = double.tryParse(m.group(1)!);
      if (temp != null) {
        if (temp > 45) temp = (temp - 32) * 5 / 9;
        if (temp > 34 && temp < 43) {
          vitals['temperature_c'] = double.parse(temp.toStringAsFixed(1));
        }
      }
    }
  }

  // ── MUAC ──────────────────────────────────────────────────────────────────
  // Patterns: "MUAC ১১", "muac 11.5", "arm 11 cm", "বাহু ১১"
  static void _extractMuac(String text, Map<String, double> vitals) {
    final muacKeywords = ['muac', 'mid upper arm', 'arm circumference', 'বাহু', 'হাতের মাপ'];
    for (final kw in muacKeywords) {
      if (!text.contains(kw)) continue;
      final pattern = RegExp('$kw\\D{0,15}(\\d{1,2}(?:\\.\\d)?)');
      final m = pattern.firstMatch(text);
      if (m != null) {
        final val = double.tryParse(m.group(1)!);
        if (val != null && val > 5 && val < 30) {
          vitals['muac_cm'] = val;
          return;
        }
      }
    }
  }

  // ── SpO2 / Oxygen Saturation ──────────────────────────────────────────────
  // Patterns: "অক্সিজেন ৯২", "spo2 94%", "oxygen 88", "saturation 96"
  static void _extractSpO2(String text, Map<String, double> vitals) {
    final spo2Keywords = [
      'spo2', 'sp02', 'oxygen', 'অক্সিজেন', 'saturation', 'pulse ox',
      'oximeter', 'o2',
    ];
    for (final kw in spo2Keywords) {
      if (!text.contains(kw)) continue;
      final pattern = RegExp('$kw\\D{0,10}(\\d{2,3})');
      final m = pattern.firstMatch(text);
      if (m != null) {
        final val = double.tryParse(m.group(1)!);
        if (val != null && val > 50 && val <= 100) {
          vitals['spo2'] = val;
          return;
        }
      }
    }
  }

  // ── Weight ────────────────────────────────────────────────────────────────
  // Patterns: "ওজন ১.২ কেজি", "weight 1.5 kg", "wajan 2 kilo"
  static void _extractWeight(String text, Map<String, double> vitals) {
    final weightKeywords = ['weight', 'ওজন', 'wajan', 'wajana', 'kg', 'kilo', 'কেজি'];
    for (final kw in weightKeywords) {
      if (!text.contains(kw)) continue;
      final pattern = RegExp('$kw\\D{0,10}(\\d{1,2}(?:\\.\\d{1,2})?)');
      final m = pattern.firstMatch(text);
      if (m != null) {
        final val = double.tryParse(m.group(1)!);
        if (val != null && val > 0.3 && val < 150) {
          vitals['weight_kg'] = val;
          return;
        }
      }
    }
    // Number before kg/kilo
    final beforeKg = RegExp(r'(\d{1,3}(?:\.\d{1,2})?)\s*(?:kg|kilo|কেজি|কিলো)');
    final m = beforeKg.firstMatch(text);
    if (m != null) {
      final val = double.tryParse(m.group(1)!);
      if (val != null && val > 0.3 && val < 150) {
        vitals['weight_kg'] = val;
      }
    }
  }

  // ── Respiratory Rate ──────────────────────────────────────────────────────
  // Patterns: "শ্বাস ৬৫", "rr 70", "breathing 60 per minute", "sans 65"
  static void _extractRespiratoryRate(String text, Map<String, double> vitals) {
    final rrKeywords = [
      'respiratory rate', 'rr', 'breathing rate', 'শ্বাসের হার', 'শ্বাস',
      'sans', 'nishwas',
    ];
    for (final kw in rrKeywords) {
      if (!text.contains(kw)) continue;
      final pattern = RegExp('$kw\\D{0,15}(\\d{2,3})');
      final m = pattern.firstMatch(text);
      if (m != null) {
        final val = double.tryParse(m.group(1)!);
        if (val != null && val > 10 && val < 120) {
          vitals['respiratory_rate'] = val;
          return;
        }
      }
    }
  }

  /// Returns a human-readable Bengali summary of extracted vitals
  /// for display in the chat bubble and for Gemini context.
  static String summarise(Map<String, double> vitals) {
    if (vitals.isEmpty) return '';
    final parts = <String>[];
    if (vitals.containsKey('systolic_bp')) {
      final sys = vitals['systolic_bp']!.toInt();
      final dia = vitals['diastolic_bp']?.toInt();
      parts.add(dia != null ? 'BP: $sys/$dia mmHg' : 'Systolic BP: $sys mmHg');
    }
    if (vitals.containsKey('temperature_c')) {
      parts.add('তাপমাত্রা: ${vitals['temperature_c']}°C');
    }
    if (vitals.containsKey('muac_cm')) {
      parts.add('MUAC: ${vitals['muac_cm']} cm');
    }
    if (vitals.containsKey('spo2')) {
      parts.add('SpO2: ${vitals['spo2']!.toInt()}%');
    }
    if (vitals.containsKey('weight_kg')) {
      parts.add('ওজন: ${vitals['weight_kg']} kg');
    }
    if (vitals.containsKey('respiratory_rate')) {
      parts.add('শ্বাসের হার: ${vitals['respiratory_rate']!.toInt()}/মিনিট');
    }
    return parts.join(', ');
  }

  /// Returns danger alerts for extracted vitals based on clinical thresholds.
  /// Used to give immediate guidance when a dangerous vital is spoken.
  static String? getDangerAlert(Map<String, double> vitals, String moduleId) {
    if (vitals.isEmpty) return null;

    final alerts = <String>[];

    // BP
    final sys = vitals['systolic_bp'];
    final dia = vitals['diastolic_bp'];
    if (sys != null && sys >= 140) {
      alerts.add('BP $sys/${dia?.toInt() ?? '?'} — প্রি-এক্লাম্পসিয়া! বাম কাতে শোয়ান, ১০৮ কল করুন।');
    } else if (sys != null && sys >= 130) {
      alerts.add('BP $sys — উচ্চ রক্তচাপ। ২৪ ঘণ্টার মধ্যে PHC-তে নিয়ে যান।');
    }

    // Temperature
    final temp = vitals['temperature_c'];
    if (temp != null) {
      if (moduleId == 'newborn' && temp > 37.5) {
        alerts.add('জ্বর ${temp}°C — নবজাতকের জন্য বিপদচিহ্ন! এখনই SNCU-তে রেফার করুন।');
      } else if (moduleId == 'delivery_pnc' && temp > 38.0) {
        alerts.add('জ্বর ${temp}°C — পিউরপেরাল সেপসিসের ঝুঁকি! FRU-তে রেফার করুন।');
      } else if (temp > 38.5) {
        alerts.add('জ্বর ${temp}°C — উচ্চ জ্বর। PHC-তে নিয়ে যান।');
      }
    }

    // MUAC
    final muac = vitals['muac_cm'];
    if (muac != null) {
      if (muac < 11.5) {
        alerts.add('MUAC $muac cm — SAM (গুরুতর অপুষ্টি)! NRC-তে রেফার করুন।');
      } else if (muac < 12.5) {
        alerts.add('MUAC $muac cm — MAM (মাঝারি অপুষ্টি)। ICDS-তে রেফার করুন।');
      }
    }

    // SpO2
    final spo2 = vitals['spo2'];
    if (spo2 != null && spo2 < 90) {
      alerts.add('SpO2 ${spo2.toInt()}% — গুরুতর হাইপক্সিয়া! এখনই ১০৮ কল করুন।');
    } else if (spo2 != null && spo2 < 94) {
      alerts.add('SpO2 ${spo2.toInt()}% — কম অক্সিজেন। FRU-তে রেফার করুন।');
    }

    // Respiratory rate
    final rr = vitals['respiratory_rate'];
    if (rr != null) {
      if (moduleId == 'newborn' && rr > 60) {
        alerts.add('শ্বাসের হার ${rr.toInt()}/মিনিট — নবজাতকের জন্য বিপদচিহ্ন! SNCU-তে রেফার করুন।');
      } else if (rr > 50) {
        alerts.add('শ্বাসের হার ${rr.toInt()}/মিনিট — দ্রুত শ্বাস। PHC-তে নিয়ে যান।');
      }
    }

    // Weight (newborn LBW)
    final weight = vitals['weight_kg'];
    if (weight != null && moduleId == 'newborn' && weight < 1.5) {
      alerts.add('ওজন $weight kg — LBW (কম ওজন)। SNCU-তে রেফার করুন।');
    }

    return alerts.isEmpty ? null : alerts.join(' ');
  }
}
