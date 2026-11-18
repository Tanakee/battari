import PhotosUI
import SwiftData
import SwiftUI

/// G3 プロフィール作成・編集
struct ProfileEditView: View {
    enum Mode {
        case create(uid: String)
        case edit(MyProfile)
    }

    let mode: Mode
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var department: String?
    @State private var grade = 1
    @State private var message = ""
    @State private var icon: Data?
    @State private var original: Snapshot?
    @State private var showErrors = false
    @State private var choosingSource = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pickingPhoto = false
    @State private var usingCamera = false
    @State private var confirmDiscard = false
    @State private var choosingDepartment = false
    @FocusState private var focus: Field?

    private enum Field { case name, message }

    private struct Snapshot: Equatable {
        var displayName: String, department: String?, grade: Int, message: String, icon: Data?
    }

    private var current: Snapshot { Snapshot(displayName: displayName, department: department, grade: grade, message: message, icon: icon) }
    private var isEditing: Bool { if case .edit = mode { return true } else { return false } }
    private var nameValid: Bool { Validation.displayName(displayName) != nil }
    private var canSave: Bool { nameValid && department != nil }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    iconPicker.frame(maxWidth: .infinity).padding(.top, 8)

                    FieldLabel(text: "表示名", required: true).padding(.top, 24).padding(.bottom, 8)
                    HStack {
                        TextField("例：たなか けいと", text: $displayName)
                            .focused($focus, equals: .name)
                            .onChange(of: displayName) { _, new in
                                displayName = Validation.truncated(new, to: Limits.displayNameLength)
                            }
                        Text("\(displayName.count)/\(Limits.displayNameLength)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xA9ACBC))
                    }
                    .fieldStyle(focused: focus == .name, error: showErrors && !nameValid)
                    ErrorText(text: showErrors && !nameValid ? "入力してください" : nil).padding(.top, 6)

                    FieldLabel(text: "学科", required: true).padding(.top, 20).padding(.bottom, 8)
                    // Menu は選んだあとにラベルが揺れるアニメーションが入るので、シートで選ばせる
                    Button { choosingDepartment = true } label: {
                        HStack {
                            Text(department ?? "選択してください")
                                .foregroundStyle(department == nil ? Color(hex: 0xA9ACBC) : Theme.ink)
                            Spacer()
                            Image(systemName: "chevron.down").foregroundStyle(Theme.sub)
                        }
                        .fieldStyle(focused: false, error: showErrors && department == nil)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    ErrorText(text: showErrors && department == nil ? "入力してください" : nil).padding(.top, 6)

                    FieldLabel(text: "学年", required: true).padding(.top, 20).padding(.bottom, 8)
                    GradeSelector(grade: $grade)

                    FieldLabel(text: "ひとこと").padding(.top, 20).padding(.bottom, 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        TextField("例：Swiftでアプリ作ってます。話しかけてください！", text: $message, axis: .vertical)
                            .lineLimit(2...4)
                            .focused($focus, equals: .message)
                            .onChange(of: message) { _, new in
                                message = Validation.truncated(new.replacingOccurrences(of: "\n", with: ""), to: Limits.messageLength)
                            }
                        Text("\(message.count)/\(Limits.messageLength)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xA9ACBC))
                    }
                    .padding(.vertical, 12)
                    .fieldStyle(focused: focus == .message)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            Button("保存する", action: save)
                .buttonStyle(PillButtonStyle())
                .opacity(canSave ? 1 : 0.55) // 押せる見た目は抑えるが、押すと未入力の項目を示す
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear(perform: load)
        .confirmationDialog("アイコン画像", isPresented: $choosingSource) {
            Button("写真を選ぶ") { pickingPhoto = true }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("カメラで撮る") { usingCamera = true }
            }
        }
        .photosPicker(isPresented: $pickingPhoto, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    icon = ImageTools.iconJPEG(from: image)
                }
                photoItem = nil
            }
        }
        .fullScreenCover(isPresented: $usingCamera) {
            CameraPicker { image in
                if let image { icon = ImageTools.iconJPEG(from: image) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $choosingDepartment) {
            DepartmentSheet(selection: $department)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .alert("変更を破棄しますか？", isPresented: $confirmDiscard) {
            Button("キャンセル", role: .cancel) {}
            Button("破棄する", role: .destructive) { dismiss() }
        }
    }

    private var navBar: some View {
        ZStack {
            Text(isEditing ? "プロフィール編集" : "プロフィール作成").font(.system(size: 17, weight: .bold))
            HStack {
                if isEditing {
                    Button("キャンセル") {
                        if current != original { confirmDiscard = true } else { dismiss() }
                    }
                    .font(.system(size: 16, weight: .semibold))
                }
                Spacer()
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 16)
    }

    private var iconPicker: some View {
        Button { choosingSource = true } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let icon {
                        StickerImage(image: icon, size: 112)
                    } else {
                        StickerImage(image: ImageTools.initialIcon(for: displayName.isEmpty ? "?" : displayName, size: 224), size: 112)
                    }
                }
                Image(systemName: "camera.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.accent, in: Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
            }
        }
        .accessibilityLabel("アイコン画像を変更")
        .overlay(alignment: .bottom) {
            Text("このアイコンがステッカーになります")
                .font(.system(size: 12))
                .foregroundStyle(Theme.sub)
                .fixedSize()
                .offset(y: 24)
        }
        .padding(.bottom, 20)
    }

    private func load() {
        guard original == nil else { return }
        if case let .edit(profile) = mode {
            displayName = profile.displayName
            department = Departments.all.contains(profile.department) ? profile.department : nil
            grade = profile.grade
            message = profile.message
            icon = profile.iconImage
        }
        original = current
    }

    private func save() {
        guard let name = Validation.displayName(displayName), let department else {
            showErrors = true
            return
        }
        let image = icon ?? ImageTools.initialIcon(for: name)
        switch mode {
        case let .create(uid):
            context.insert(MyProfile(uid: uid, displayName: name, department: department, grade: grade,
                                     message: message.trimmingCharacters(in: .whitespaces), iconImage: image))
        case let .edit(profile):
            profile.displayName = name
            profile.department = department
            profile.grade = grade
            profile.message = message.trimmingCharacters(in: .whitespaces)
            profile.iconImage = image
            profile.updatedAt = Date()
            dismiss()
        }
        try? context.save()
    }
}

/// 学年の選択。標準のセグメントはガラス表現で文字が読みにくいため、自前のボタンで並べる
private struct GradeSelector: View {
    @Binding var grade: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(Limits.grades), id: \.self) { value in
                let selected = value == grade
                Button { grade = value } label: {
                    Text("\(value)年")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(selected ? .white : Theme.label)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(selected ? Theme.accent : Color.white, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(selected ? Color.clear : Theme.fieldBorder, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// 学科の選択シート
private struct DepartmentSheet: View {
    @Binding var selection: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("学科を選択")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Departments.all, id: \.self) { name in
                        Button {
                            selection = name
                            dismiss()
                        } label: {
                            HStack {
                                Text(name)
                                    .font(.system(size: 16, weight: selection == name ? .bold : .regular))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                if selection == name {
                                    Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
                                }
                            }
                            .padding(.horizontal, 24)
                            .frame(height: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 24)
                    }
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

/// カメラで撮影する（UIKit の UIImagePickerController を使う）
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .front
        picker.allowsEditing = true // 正方形に切り抜ける
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.onFinish((info[.editedImage] ?? info[.originalImage]) as? UIImage)
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onFinish(nil)
            parent.dismiss()
        }
    }
}
