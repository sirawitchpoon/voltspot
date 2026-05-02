import SwiftUI

struct AuthView: View {
    @Environment(AppSession.self) private var session
    @State private var viewModel: AuthViewModel?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        ZStack {
                            Color.appAccentTint
                            WeavePattern()
                            VStack {
                                Spacer()
                                BrandHeader(subtitle: "auth.subtitle")
                                Spacer()
                            }
                            .padding(.bottom, AppSpacing.xl)
                        }
                        .frame(height: 240)

                        if let viewModel {
                            AuthForm(viewModel: viewModel)
                                .padding(AppSpacing.xl)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            if viewModel == nil {
                viewModel = AuthViewModel(
                    signIn: SignInUseCase(authRepository: MockAuthRepository(keychain: KeychainStore())),
                    signUp: SignUpUseCase(authRepository: MockAuthRepository(keychain: KeychainStore())),
                    session: session
                )
            }
        }
    }
}

private struct AuthForm: View {
    @Bindable var viewModel: AuthViewModel

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Picker("auth.mode", selection: $viewModel.mode) {
                Text("auth.signIn").tag(AuthViewModel.Mode.signIn)
                Text("auth.signUp").tag(AuthViewModel.Mode.signUp)
            }
            .pickerStyle(.segmented)

            VStack(spacing: AppSpacing.md) {
                if viewModel.mode == .signUp {
                    AppTextField(
                        title: "auth.displayName",
                        text: $viewModel.displayName,
                        autocapitalization: .words
                    )
                }

                AppTextField(
                    title: "auth.email",
                    text: $viewModel.email,
                    keyboard: .emailAddress,
                    autocapitalization: .never,
                    autocorrect: false
                )

                AppSecureField(title: "auth.password", text: $viewModel.password)
            }

            if viewModel.mode == .signUp {
                HStack {
                    Text("auth.password.requirement \(AppConfig.minimumPasswordLength)")
                        .font(.appText(12))
                        .foregroundStyle(passwordHintColor)
                    Spacer()
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.appText(13, weight: .medium))
                    .foregroundStyle(Color.appDanger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            PrimaryButton(
                title: viewModel.mode == .signIn ? "auth.signIn" : "auth.signUp",
                isLoading: viewModel.isWorking,
                isDisabled: !viewModel.canSubmit
            ) {
                Task { await viewModel.submit() }
            }
            .padding(.top, AppSpacing.sm)
        }
    }

    private var passwordHintColor: Color {
        if viewModel.password.isEmpty { return .appFg3 }
        return viewModel.passwordMeetsMinimum ? .appAccent : .appDanger
    }
}

private struct AppTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    var autocorrect: Bool = true

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(keyboard)
            .textInputAutocapitalization(autocapitalization)
            .autocorrectionDisabled(!autocorrect)
            .font(.appText(15))
            .foregroundStyle(Color.appFg)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, 14)
            .background(Color.appSurface2, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }
}

private struct AppSecureField: View {
    let title: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        SecureField(title, text: $text)
            .font(.appText(15))
            .foregroundStyle(Color.appFg)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, 14)
            .background(Color.appSurface2, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }
}
