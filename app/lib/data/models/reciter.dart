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

class ReciterCatalog {
  final String defaultId;
  final List<Reciter> reciters;

  ReciterCatalog({required this.defaultId, required this.reciters});

  factory ReciterCatalog.fromJson(Map<String, dynamic> j) => ReciterCatalog(
        defaultId: j['default'] as String,
        reciters: (j['reciters'] as List)
            .map((e) => Reciter.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Reciter? byId(String id) {
    for (final r in reciters) {
      if (r.id == id) return r;
    }
    return null;
  }
}
