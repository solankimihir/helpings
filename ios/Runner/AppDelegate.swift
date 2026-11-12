import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var backupFolder: BackupFolderChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BackupFolderChannel") {
      backupFolder = BackupFolderChannel(registrar: registrar)
    }
  }
}

/// A folder the user picks once and the app keeps access to across launches
/// via a security-scoped bookmark. The token handed to Dart is the bookmark,
/// base64-encoded. See lib/data/backup_folder.dart.
final class BackupFolderChannel: NSObject, UIDocumentPickerDelegate {
  private weak var registrar: FlutterPluginRegistrar?
  private var pendingPick: FlutterResult?
  private let io = DispatchQueue(label: "helpings.backup_folder")

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
    let channel = FlutterMethodChannel(
      name: "helpings/backup_folder", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
  }

  private struct NoAccess: Error { let message: String }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    if call.method == "pick" { return pick(result) }
    let args = call.arguments as? [String: Any] ?? [:]
    guard let token = args["token"] as? String else {
      return result(FlutterError(code: "bad_args", message: "token is required", details: nil))
    }
    io.async {
      let reply: Any?
      do {
        switch call.method {
        case "name":
          reply = try self.withFolder(token) { $0.lastPathComponent }
        case "list":
          reply = try self.withFolder(token) { dir in
            try FileManager.default.contentsOfDirectory(
              at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
            )
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map { $0.lastPathComponent }
          }
        case "write":
          guard let name = args["name"] as? String,
            let bytes = args["bytes"] as? FlutterStandardTypedData
          else { throw NoAccess(message: "name and bytes are required") }
          reply = try self.withFolder(token) { dir in
            try self.coordinate(dir.appendingPathComponent(name), writing: .forReplacing) {
              try bytes.data.write(to: $0, options: .atomic)
            }
            return nil
          }
        case "delete":
          guard let name = args["name"] as? String else {
            throw NoAccess(message: "name is required")
          }
          reply = try self.withFolder(token) { dir in
            let file = dir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: file.path) {
              try self.coordinate(file, writing: .forDeleting) {
                try FileManager.default.removeItem(at: $0)
              }
            }
            return nil
          }
        case "release":
          reply = nil  // Bookmarks hold no system-side grant to give back.
        default:
          DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
          return
        }
        DispatchQueue.main.async { result(reply) }
      } catch let e as NoAccess {
        DispatchQueue.main.async {
          result(FlutterError(code: "no_access", message: e.message, details: nil))
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "io_error", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  /// Resolves the bookmark and holds security-scoped access for [body].
  private func withFolder<T>(_ token: String, _ body: (URL) throws -> T) throws -> T {
    let lost = NoAccess(
      message: "Helpings no longer has access to the backup folder. Choose it again.")
    guard let data = Data(base64Encoded: token) else { throw lost }
    var stale = false
    guard
      let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale),
      url.startAccessingSecurityScopedResource()
    else { throw lost }
    defer { url.stopAccessingSecurityScopedResource() }
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue
    else {
      throw NoAccess(message: "The backup folder can't be found. It may have been deleted.")
    }
    return try body(url)
  }

  /// File coordination, so iCloud Drive and other providers see a clean write.
  private func coordinate(
    _ url: URL, writing options: NSFileCoordinator.WritingOptions,
    _ body: (URL) throws -> Void
  ) throws {
    var coordError: NSError?
    var bodyError: Error?
    NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordError) {
      do { try body($0) } catch { bodyError = error }
    }
    if let e = coordError ?? bodyError { throw e }
  }

  private func pick(_ result: @escaping FlutterResult) {
    guard pendingPick == nil else {
      return result(FlutterError(code: "busy", message: "A folder picker is already open", details: nil))
    }
    guard let presenter = topViewController() else {
      return result(FlutterError(code: "no_ui", message: "Nothing to present the picker from", details: nil))
    }
    pendingPick = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
    picker.delegate = self
    picker.allowsMultipleSelection = false
    presenter.present(picker, animated: true)
  }

  private func topViewController() -> UIViewController? {
    var vc = registrar?.viewController
      ?? UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController
    while let presented = vc?.presentedViewController { vc = presented }
    return vc
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = pendingPick else { return }
    pendingPick = nil
    guard let url = urls.first else { return result(nil) }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      let bookmark = try url.bookmarkData(
        options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
      result(["token": bookmark.base64EncodedString(), "name": url.lastPathComponent])
    } catch {
      result(FlutterError(code: "io_error", message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingPick?(nil)
    pendingPick = nil
  }
}
