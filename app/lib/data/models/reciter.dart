/// Reciter models mirroring the gateway's /v1/reciters payload.

class Reciter {
  final String id;
  final String displayName;
  final String? displayNameFa;
  final String folder;
  final int bitrateKbps;
  final String style; // murattal | mujawwad
  final String tradition; // shia | sunni | universal

  Reciter({
    required this.id,
    required this.displayName,
    required this.folder,
    required this.bitrateKbps,
    required this.style,
    required this.tradition,
    this.displayNameFa,
  });

  factory Reciter.fromJson(Map<String, dynamic> j) => Reciter(
        id: j['id'] as String,
        displayName: j['display_name'] as String,
        displayNameFa: j['display_name_fa'] as String?,
        folder: j['folder'] as String,
        bitrateKbps: j['bitrate_kbps'] as int,
        style: j['style'] as String,
        tradition: j['tradition'] as String,
      );

  /// Persian name when the UI language is fa and one exists, else the default name.
  String localizedName(String lang) =>
      (lang == 'fa' && displayNameFa != null) ? displayNameFa! : displayName;
}

/// A human-recited TRANSLATION of the Quran (not the Arabic), per ayah, hosted
/// on the same CDN as the reciters. Used to read the meaning aloud instead of AI
/// TTS. Keyed by translation language (fa/en); some languages have no source.
class TranslationAudio {
  final String folder; // CDN subpath; same {folder}/{SSS}{AAA}.mp3 scheme
  final String label;
  final String? labelFa;

  TranslationAudio({required this.folder, required this.label, this.labelFa});

  factory TranslationAudio.fromJson(Map<String, dynamic> j) => TranslationAudio(
        folder: j['folder'] as String,
        label: j['label'] as String,
        labelFa: j['label_fa'] as String?,
      );

  String localizedLabel(String lang) =>
      (lang == 'fa' && labelFa != null) ? labelFa! : label;
}

class ReciterCatalog {
  final String defaultId;
  final List<Reciter> reciters;

  /// Translation-audio sources keyed by translation language (e.g. fa, en).
  final Map<String, TranslationAudio> translationAudio;

  ReciterCatalog({
    required this.defaultId,
    required this.reciters,
    this.translationAudio = const {},
  });

  factory ReciterCatalog.fromJson(Map<String, dynamic> j) => ReciterCatalog(
        defaultId: j['default'] as String,
        reciters: (j['reciters'] as List)
            .map((e) => Reciter.fromJson(e as Map<String, dynamic>))
            .toList(),
        translationAudio: {
          for (final e in ((j['translation_audio'] ?? const {})
                  as Map<String, dynamic>)
              .entries)
            e.key: TranslationAudio.fromJson(e.value as Map<String, dynamic>)
        },
      );

  Reciter? byId(String id) {
    for (final r in reciters) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// The translation-audio source for [lang], or null if none exists.
  TranslationAudio? translationFor(String lang) => translationAudio[lang];
}
