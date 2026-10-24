import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum UIColors {
    static let background = Color(red: 0.075, green: 0.085, blue: 0.115)
    static let panel = Color(red: 0.13, green: 0.15, blue: 0.19)
    static let field = Color(red: 0.065, green: 0.075, blue: 0.095)
    static let ink = Color(red: 0.93, green: 0.95, blue: 0.98)
    static let muted = Color(red: 0.66, green: 0.70, blue: 0.76)
    static let blue = Color(red: 0.29, green: 0.55, blue: 1.0)
    static let green = Color(red: 0.24, green: 0.86, blue: 0.59)
}
private enum PickerKind { case inputFolder, inputFile, shaderFile, shaderFolder, outputFolder }

struct ContentView: View {
    @State private var showInputFolderPicker = false
    @State private var showInputFilePicker = false
    @State private var showShaderFilePicker = false
    @State private var showShaderFolderPicker = false
    @State private var showOutputFolderPicker = false
    @State private var activePickerKind: PickerKind = .inputFile
    @State private var inputURL: URL?
    @State private var shaderURL: URL?
    @State private var outputURL: URL?
    @State private var resultURL: URL?
    @State private var isConverting = false
    @State private var createZip = true
    @State private var fullValidation = true
    @State private var preserveShadows = true
    @State private var progress = 0.0
    @State private var status = "Ready"
    @State private var log = "MLBB iOS Auto Converter v1.0.26\nChoose Android input and iOS shaders, then tap CONVERT TO iOS.\n"
    @State private var showResult = false
    @State private var resultMessage = ""
    @State private var showShare = false

    private var bundledShaders: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("PythonApp/ios_shaders", isDirectory: true)
    }
    private var effectiveShaders: URL? { shaderURL ?? bundledShaders }


    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MLBB iOS Auto Converter")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(UIColors.ink)
                        Text("Android → iOS Unity bundle converter with exact ShaderVariants matching")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(UIColors.muted)
                        Text("v1.0.26 · iOS")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(UIColors.muted)
                    }.padding(.top, 8)

                    VStack(alignment: .leading, spacing: 13) {
                        pathRow("Android input", value: inputURL?.lastPathComponent ?? "Choose folder, .unity3d, ZIP or RAR") {
                            HStack {
                                smallButton("Folder", icon: "folder") { openPicker(.inputFolder) }
                                smallButton("File/ZIP/RAR", icon: "doc.zipper") { openPicker(.inputFile) }
                            }
                        }
                        Divider().overlay(UIColors.muted.opacity(0.2))
                        pathRow("iOS shaders", value: shaderURL?.lastPathComponent ?? "Bundled ShaderVariants (3 files)") {
                            HStack {
                                smallButton("File", icon: "doc") { openPicker(.shaderFile) }
                                smallButton("Folder", icon: "folder") { openPicker(.shaderFolder) }
                                smallButton("Default", icon: "arrow.counterclockwise") { shaderURL = nil; status = "Using bundled shaders" }
                            }
                        }
                        Divider().overlay(UIColors.muted.opacity(0.2))
                        pathRow("Output folder", value: outputURL?.path ?? "Documents/Converted") {
                            smallButton("Browse", icon: "folder") { openPicker(.outputFolder) }
                        }
                    }
                    .padding(14)
                    .background(UIColors.panel, in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Conversion options").font(.system(size: 15, weight: .semibold)).foregroundColor(UIColors.ink)
                        Toggle("Create ZIP", isOn: $createZip)
                        Toggle("Full texture validation", isOn: $fullValidation)
                        Toggle("Preserve shadows", isOn: $preserveShadows)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: UIColors.blue))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(UIColors.ink)
                    .padding(14)
                    .background(UIColors.panel, in: RoundedRectangle(cornerRadius: 12))

                    HStack(spacing: 10) {
                        Button(action: startConversion) {
                            Label(isConverting ? "CONVERTING…" : "CONVERT TO iOS", systemImage: "arrow.triangle.2.circlepath")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(UIColors.blue, in: RoundedRectangle(cornerRadius: 7))
                        }.disabled(isConverting)
                        Button("Open Output") {
                            if let resultURL { share(resultURL) }
                            else if let outputURL { share(outputURL) }
                            else { showResult = true; resultMessage = "Converted files are saved in Documents/Converted." }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(UIColors.ink)
                        .padding(.horizontal, 12).frame(minHeight: 48)
                        .background(UIColors.panel, in: RoundedRectangle(cornerRadius: 7))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(status).font(.system(size: 12, weight: .semibold)).foregroundColor(UIColors.ink)
                            Spacer()
                            Text("\(Int(progress * 100))%").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(UIColors.muted)
                        }
                        ProgressView(value: progress).tint(UIColors.green)
                    }.padding(.horizontal, 2)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Conversion log").font(.system(size: 14, weight: .semibold)).foregroundColor(UIColors.ink)
                        ScrollView {
                            Text(log).font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundColor(UIColors.muted).frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }.frame(minHeight: 180, maxHeight: 280)
                    }
                    .padding(12).background(UIColors.field, in: RoundedRectangle(cornerRadius: 8))
                    Text("RAR archives may need to be extracted in Files first. Keep a backup of your original files.")
                        .font(.footnote).foregroundColor(UIColors.muted)
                }
                .padding(16).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background(UIColors.background.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .navigationTitle("MLBB iOS Auto Converter")
            .navigationBarTitleDisplayMode(.inline)
            .alert("MLBB iOS Auto Converter", isPresented: $showResult) {
                Button("OK", role: .cancel) { }
                if resultURL != nil { Button("Share Output") { if let resultURL { share(resultURL) } } }
            } message: { Text(resultMessage) }
            .sheet(isPresented: $showShare) {
                if let resultURL { ActivityView(items: [resultURL]) }
            }
            .onAppear(perform: ensureShaderFolderInDocuments)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        // Use one importer only. Multiple fileImporter modifiers on the same
        // SwiftUI view can compete for presentation and leave every picker inert.
        .fileImporter(
            isPresented: activePickerBinding,
            allowedContentTypes: pickerContentTypes,
            allowsMultipleSelection: activePickerKind == .shaderFile
        ) { result in
            handleImport(result, kind: activePickerKind)
        }
    }

    private var activePickerBinding: Binding<Bool> {
        Binding(
            get: {
                showInputFolderPicker || showInputFilePicker || showShaderFilePicker || showShaderFolderPicker || showOutputFolderPicker
            },
            set: { isPresented in
                if !isPresented {
                    showInputFolderPicker = false
                    showInputFilePicker = false
                    showShaderFilePicker = false
                    showShaderFolderPicker = false
                    showOutputFolderPicker = false
                }
            }
        )
    }

    private var pickerContentTypes: [UTType] {
        switch activePickerKind {
        case .inputFolder, .shaderFolder, .outputFolder:
            return [.folder]
        case .inputFile:
            return [.item, .archive]
        case .shaderFile:
            return [.item]
        }
    }

    @ViewBuilder private func pathRow<Actions: View>(_ title: String, value: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(UIColors.muted)
            Text(value).font(.system(size: 12, weight: .medium)).foregroundColor(UIColors.ink)
                .lineLimit(2).frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                .padding(.horizontal, 9).background(UIColors.field, in: RoundedRectangle(cornerRadius: 4))
            actions()
        }
    }

    private func smallButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold))
                .foregroundColor(UIColors.ink).frame(maxWidth: .infinity, minHeight: 38)
                .background(UIColors.field, in: RoundedRectangle(cornerRadius: 5))
        }
    }

    private func ensureShaderFolderInDocuments() {
        let fm = FileManager.default
        guard let bundled = bundledShaders else { return }
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let visibleFolder = documents.appendingPathComponent("iOSShaders", isDirectory: true)
        do {
            try fm.createDirectory(at: visibleFolder, withIntermediateDirectories: true)
            let files = try fm.contentsOfDirectory(at: bundled, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            for source in files where !source.lastPathComponent.hasPrefix(".") {
                let destination = visibleFolder.appendingPathComponent(source.lastPathComponent)
                if !fm.fileExists(atPath: destination.path) {
                    try fm.copyItem(at: source, to: destination)
                }
            }
            log += "\\nBundled shader files are available in Files > On My iPhone > MLBB iOS Auto Converter > iOSShaders.\\n"
        } catch {
            log += "\\nCould not prepare visible iOSShaders folder: \\(error.localizedDescription)\\n"
        }
    }

    private func openPicker(_ kind: PickerKind) {
        // Separate importers prevent file/folder mode changes from reusing stale picker configuration.
        showInputFolderPicker = false
        showInputFilePicker = false
        showShaderFilePicker = false
        showShaderFolderPicker = false
        showOutputFolderPicker = false
        status = "Opening Files…"
        log += "\\nOpening Files picker: \\(String(describing: kind))\\n"
        activePickerKind = kind
        // Trigger the single fileImporter after its filter has been updated.
        DispatchQueue.main.async {
            switch kind {
            case .inputFolder: showInputFolderPicker = true
            case .inputFile: showInputFilePicker = true
            case .shaderFile: showShaderFilePicker = true
            case .shaderFolder: showShaderFolderPicker = true
            case .outputFolder: showOutputFolderPicker = true
            }
        }
    }

    // Single-selection fileImporter callbacks return Result<URL, Error>.
    // Normalize them to the array-based handler used by multi-selection.
    private func handleImport(_ result: Result<URL, Error>, kind: PickerKind) {
        handleImport(result.map { [$0] }, kind: kind)
    }

    private func handleImport(_ result: Result<[URL], Error>, kind: PickerKind) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else {
                status = "Nothing selected"
                log += "\nNo file or folder selected.\n"
                return
            }
            do {
                let fm = FileManager.default
                let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let inbox = documents.appendingPathComponent("Imported", isDirectory: true)
                try fm.createDirectory(at: inbox, withIntermediateDirectories: true)

                if case .shaderFile = kind {
                    let shaderInbox = inbox.appendingPathComponent("iOSShaders", isDirectory: true)
                    try fm.createDirectory(at: shaderInbox, withIntermediateDirectories: true)
                    var importedNames: [String] = []
                    for selectedURL in urls {
                        let hasAccess = selectedURL.startAccessingSecurityScopedResource()
                        defer { if hasAccess { selectedURL.stopAccessingSecurityScopedResource() } }
                        let target = shaderInbox.appendingPathComponent(selectedURL.lastPathComponent)
                        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                        try copyCoordinatedItem(from: selectedURL, to: target)
                        importedNames.append(selectedURL.lastPathComponent)
                    }
                    shaderURL = shaderInbox
                    status = "Imported \(importedNames.count) shader file(s)"
                    log += "\nImported shader files: \(importedNames.joined(separator: ", "))\nFolder: \(shaderInbox.path)\n"
                } else {
                    guard let selectedURL = urls.first else { return }
                    let hasAccess = selectedURL.startAccessingSecurityScopedResource()
                    defer { if hasAccess { selectedURL.stopAccessingSecurityScopedResource() } }
                    let isFolder = (try? selectedURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    let target = inbox.appendingPathComponent(selectedURL.lastPathComponent, isDirectory: isFolder)
                    if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                    try copyCoordinatedItem(from: selectedURL, to: target)
                    switch kind {
                    case .inputFolder, .inputFile: inputURL = target
                    case .shaderFolder: shaderURL = target
                    case .outputFolder: outputURL = target
                    case .shaderFile: break
                    }
                    status = "Imported: " + target.lastPathComponent
                    log += "\nImported: \(target.path)\n"
                }
            } catch {
                resultMessage = "Import failed: " + error.localizedDescription
                status = "Import failed"
                log += "\nIMPORT ERROR: " + error.localizedDescription + "\n"
                showResult = true
            }
        case .failure(let error):
            resultMessage = "File picker failed: " + error.localizedDescription
            status = "Picker failed"
            log += "\nPICKER ERROR: " + error.localizedDescription + "\n"
            showResult = true
        }
    }

    private func copyCoordinatedItem(from source: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: source, options: [], error: &coordinationError) { readableURL in
            do {
                try FileManager.default.copyItem(at: readableURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
    }

    private func startConversion() {
        guard let inputURL else {
            resultMessage = "Choose an Android .unity3d file, ZIP, or extracted folder first."
            showResult = true; return
        }
        guard let shaders = effectiveShaders else {
            resultMessage = "Bundled iOS ShaderVariants are missing."
            showResult = true; return
        }
        let destination = outputURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Converted", isDirectory: true)
        do { try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true) }
        catch { resultMessage = error.localizedDescription; showResult = true; return }

        isConverting = true; progress = 0.05; status = "Converting…"
        log = "MLBB iOS Auto Converter v1.0.26\nInput: \(inputURL.lastPathComponent)\nShaders: \(shaders.lastPathComponent)\n"
        let input = inputURL.path, shader = shaders.path, output = destination.path
        let zip = createZip, validation = fullValidation, shadows = preserveShadows
        DispatchQueue.global(qos: .userInitiated).async {
            let response = PythonBridge.convertInput(input, shaderPath: shader, outputParent: output, createZip: zip, fullValidation: validation, preserveShadows: shadows)
            DispatchQueue.main.async {
                isConverting = false
                progress = 1
                log += "\n" + response
                guard let data = response.data(using: .utf8), let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    status = "Failed"; resultMessage = response; showResult = true; return
                }
                if (payload["ok"] as? Bool) == true {
                    status = "Complete"
                    let outDir = payload["output_dir"] as? String
                    let zipPath = payload["output_zip"] as? String
                    resultURL = URL(fileURLWithPath: (zipPath?.isEmpty == false ? zipPath! : (outDir ?? destination.path)))
                    resultMessage = "Conversion complete.\nBundles: \(payload["bundles"] ?? "—")\nMaterials: \(payload["materials"] ?? "—")\nTextures: \(payload["textures"] ?? "—")\n\nSaved to:\n\(resultURL?.path ?? destination.path)"
                } else {
                    status = "Failed"; resultMessage = (payload["error"] as? String) ?? "Conversion failed."
                }
                showResult = true
            }
        }
    }

    private func share(_ url: URL) { resultURL = url; showShare = true }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
