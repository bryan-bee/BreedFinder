import MessageUI
import SwiftUI

/// The problem report form. Builds an email the user reviews before sending, with the
/// chosen scan's frames attached when they want.
struct ReportProblemView: View {
    @EnvironmentObject private var recentScans: RecentScansStore
    @EnvironmentObject private var collection: BreedCollection
    @EnvironmentObject private var scanModel: ScanModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var kind: ProblemKind
    @State private var scanID: UUID?
    @State private var pickedBreed: String?
    @State private var describedBreed = ""
    @State private var details = ""
    @State private var attachPhotos = true
    /// Explicit, opt-in permission to train the breed model on the attached photos.
    @State private var allowTrainingUse = false
    @State private var showingBreedPicker = false
    @State private var showingMail = false
    @State private var showingNoMailOptions = false
    @State private var showingShareSheet = false

    init(kind: ProblemKind = .bug, scanID: UUID? = nil, actualBreed: String? = nil) {
        _kind = State(initialValue: kind)
        _scanID = State(initialValue: scanID)
        _pickedBreed = State(initialValue: actualBreed)
    }

    private var selectedScan: RecentScan? { recentScans.scan(id: scanID) }

    private var actualBreed: String? {
        let described = describedBreed.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (pickedBreed, described.isEmpty) {
        case (let picked?, true): return picked
        case (let picked?, false): return "\(picked) (\(described))"
        case (nil, false): return described
        case (nil, true): return nil
        }
    }

    private var canSend: Bool {
        switch kind {
        case .wrongBreed: return actualBreed != nil
        case .crash: return true
        case .bug, .suggestion:
            return !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var report: ProblemReport {
        let scan = selectedScan
        return ProblemReport(
            kind: kind,
            details: details,
            actualBreed: kind == .wrongBreed ? actualBreed : nil,
            scan: scan,
            countedAs: scan?.recordID.flatMap { collection.record(id: $0)?.breed },
            photosAttached: attachingPhotos,
            allowsTrainingUse: attachingPhotos && allowTrainingUse,
            appVersion: SupportInfo.appVersion,
            modelVersion: scanModel.modelVersion,
            systemVersion: SupportInfo.systemVersion,
            deviceModel: SupportInfo.deviceModel
        )
    }

    private var attachingPhotos: Bool {
        attachPhotos && !(selectedScan?.frameFiles.isEmpty ?? true)
    }

    private var attachments: [ReportAttachment] {
        guard attachingPhotos, let scan = selectedScan else { return [] }
        return recentScans.attachments(for: scan)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What kind of problem?") {
                    Picker("Problem", selection: $kind) {
                        ForEach(ProblemKind.allCases) { option in
                            Label(option.rawValue, systemImage: option.systemImage).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                scanSection

                if kind == .wrongBreed {
                    Section {
                        Button { showingBreedPicker = true } label: {
                            HStack {
                                Text("Breed")
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                Text(pickedBreed ?? "Choose")
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        TextField("Not in the list? Describe it", text: $describedBreed)
                    } header: {
                        Text("What breed is it really?")
                    } footer: {
                        Text("For example a mix like Labrador × Poodle, or \"not sure\".")
                    }
                }

                Section("Details") {
                    TextField(kind.detailsPrompt, text: $details, axis: .vertical)
                        .lineLimit(4...10)
                }

                if let scan = selectedScan {
                    Section {
                        Toggle("Attach this scan's \(scan.source.itemName)s", isOn: $attachPhotos)
                        if attachPhotos {
                            FrameThumbnails(scan: scan)
                            Toggle("Breed Finder may use these \(scan.source.itemName)s to improve breed recognition",
                                   isOn: $allowTrainingUse)
                        }
                    } footer: {
                        Text("Nothing is sent until you send the email, and you'll see everything in it first. Photos are only used to train the breed model if you turn that on.")
                    }
                }

                Section("Included automatically") {
                    LabeledContent("App version", value: SupportInfo.appVersion)
                    LabeledContent("Breed model", value: selectedScan?.modelVersion ?? scanModel.modelVersion)
                    LabeledContent("iOS", value: SupportInfo.systemVersion)
                    LabeledContent("iPhone model", value: SupportInfo.deviceModel)
                }
            }
            .navigationTitle("Report a Problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next", action: send)
                        .disabled(!canSend)
                }
            }
            .onAppear(perform: preselectLatestScan)
            .onChange(of: kind) { _, _ in preselectLatestScan() }
            .sheet(isPresented: $showingBreedPicker) {
                BreedPickerSheet(suggestions: selectedScan?.guesses ?? [], current: pickedBreed,
                                 onPick: { pickedBreed = $0 })
            }
            .sheet(isPresented: $showingMail) {
                MailComposer(recipient: SupportInfo.reportEmail, subject: report.subject,
                             messageBody: report.body, attachments: attachments) { result in
                    showingMail = false
                    if result == .sent {
                        Analytics.send(.reportSent(report, via: "mail"))
                        dismiss()
                    }
                }
                .ignoresSafeArea()
            }
            .confirmationDialog("Mail isn't set up on this iPhone", isPresented: $showingNoMailOptions,
                                titleVisibility: .visible) {
                Button("Share with another app") {
                    UIPasteboard.general.string = SupportInfo.reportEmail
                    showingShareSheet = true
                }
                Button("Email without photos") { openMailto() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("To include the photos, share the report with an app like Gmail. \(SupportInfo.reportEmail) will be copied so you can paste it into the To field.")
            }
            .sheet(isPresented: $showingShareSheet) {
                ActivityView(items: shareItems) { completed in
                    showingShareSheet = false
                    if completed {
                        Analytics.send(.reportSent(report, via: "share sheet"))
                        dismiss()
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    /// Recent scans to choose from. Required context for wrong-breed reports.
    @ViewBuilder
    private var scanSection: some View {
        if !recentScans.scans.isEmpty {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(recentScans.scans) { scan in
                            Button {
                                // Tapping the selected scan again deselects it (except for wrong-breed reports).
                                scanID = (scanID == scan.id && kind != .wrongBreed) ? nil : scan.id
                            } label: {
                                RecentScanCard(scan: scan, isSelected: scan.id == scanID)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text(kind == .wrongBreed ? "Which scan?" : "Related scan (optional)")
            } footer: {
                Text("Your last \(RecentScansStore.limit) scans are kept on this iPhone so you can attach them here.")
            }
        } else if kind == .wrongBreed {
            Section("Which scan?") {
                Text("No recent scans. Scan the dog again, then report it from the result screen.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func preselectLatestScan() {
        if scanID == nil, kind == .wrongBreed {
            scanID = recentScans.scans.first?.id
        }
    }

    private func send() {
        if MFMailComposeViewController.canSendMail() {
            showingMail = true
        } else if attachments.isEmpty {
            openMailto()
        } else {
            showingNoMailOptions = true
        }
    }

    private func openMailto() {
        guard let url = SupportInfo.mailtoURL(subject: report.subject, body: report.body) else { return }
        openURL(url)
        // Handed to the default mail app; whether it was actually sent isn't known.
        Analytics.send(.reportSent(report, via: "mail app"))
        dismiss()
    }

    private var shareItems: [Any] {
        let text = "To: \(SupportInfo.reportEmail)\nSubject: \(report.subject)\n\n\(report.body)"
        return [text] + attachments.compactMap { UIImage(data: $0.data) }
    }
}

/// One recent scan in the picker: a frame and what the app said.
private struct RecentScanCard: View {
    let scan: RecentScan
    let isSelected: Bool
    @EnvironmentObject private var recentScans: RecentScansStore

    var body: some View {
        let frameIndex = scan.framesWithDog.firstIndex(of: true) ?? 0
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let thumbnail = recentScans.thumbnail(for: scan, frame: frameIndex) {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                } else {
                    PhotoPlaceholder()
                }
            }
            .frame(width: 92, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: isSelected ? 3 : 0)
            }
            .accessibilityHidden(true)  // the breed and date below describe the scan
            Text(scan.guesses.first?.breed ?? "No dog found")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(scan.date.formatted(.relative(presentation: .named)))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 92)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Every frame or photo of a scan, as it will be attached.
private struct FrameThumbnails: View {
    let scan: RecentScan
    @EnvironmentObject private var recentScans: RecentScansStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(scan.frameFiles.indices, id: \.self) { index in
                    Group {
                        if let thumbnail = recentScans.thumbnail(for: scan, frame: index) {
                            Image(uiImage: thumbnail).resizable().scaledToFill()
                        } else {
                            PhotoPlaceholder()
                        }
                    }
                    .frame(width: 54, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .opacity(scan.framesWithDog.indices.contains(index) && scan.framesWithDog[index] ? 1 : 0.4)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(scan.frameFiles.count) \(scan.source.itemName)\(scan.frameFiles.count == 1 ? "" : "s") to attach")
    }
}

/// The system email composer, wrapped for SwiftUI.
struct MailComposer: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    // Not `body`: that name belongs to SwiftUI's View protocol, which this type adopts.
    let messageBody: String
    var attachments: [ReportAttachment] = []
    let onFinish: (MFMailComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.setToRecipients([recipient])
        composer.setSubject(subject)
        composer.setMessageBody(messageBody, isHTML: false)
        for attachment in attachments {
            composer.addAttachmentData(attachment.data, mimeType: "image/jpeg", fileName: attachment.fileName)
        }
        composer.mailComposeDelegate = context.coordinator
        return composer
    }

    func updateUIViewController(_ composer: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult) -> Void

        init(onFinish: @escaping (MFMailComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish(result)
        }
    }
}

/// The system share sheet, for phones without the Mail app set up.
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    let onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in onComplete(completed) }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
