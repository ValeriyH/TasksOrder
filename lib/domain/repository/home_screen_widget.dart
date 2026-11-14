/// The home-screen widget of the device (T-601). The platform side lives in
/// `lib/data` and in the Android code; tests use a fake.
abstract interface class HomeScreenWidget {
  /// Whether this platform has the widget at all.
  bool get isSupported;

  /// Stores [payload] for the widget and redraws every placed widget. The
  /// format is described in docs/03 Data Model.md ("Home-screen widget
  /// cache").
  Future<void> update(String payload);
}
