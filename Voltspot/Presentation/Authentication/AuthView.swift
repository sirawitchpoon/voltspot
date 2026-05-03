import AuthenticationServices
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
                        ZStack(alignment: .topTrailing) {
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
                            LanguageToggle()
                                .padding(.top, AppSpacing.lg)
                                .padding(.trailing, AppSpacing.lg)
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
                let auth = RealAuthRepository()
                viewModel = AuthViewModel(
                    signIn: SignInUseCase(authRepository: auth),
                    signUp: SignUpUseCase(authRepository: auth),
                    signInWithApple: SignInWithAppleUseCase(authRepository: auth),
                    signInWithGoogle: SignInWithGoogleUseCase(authRepository: auth),
                    session: session
                )
            }
        }
    }
}

private struct AuthForm: View {
    @Bindable var viewModel: AuthViewModel
    @FocusState private var passwordFocused: Bool

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

                AppPasswordField(
                    title: "auth.password",
                    text: $viewModel.password,
                    isFocused: $passwordFocused
                )

                if viewModel.mode == .signUp,
                   passwordFocused || !viewModel.password.isEmpty {
                    PasswordRulesPanel(rules: viewModel.passwordRules)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeOut(duration: 0.2), value: passwordFocused)
            .animation(.easeOut(duration: 0.2), value: viewModel.password.isEmpty)

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

            FederatedAuthSection(viewModel: viewModel)
                .padding(.top, AppSpacing.sm)
        }
    }
}

private struct PasswordRulesPanel: View {
    let rules: [PasswordRule]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rules) { rule in
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: rule.passed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(rule.passed ? Color.appAccent : Color.appFg3)
                        .contentTransition(.symbolEffect(.replace))
                    Text(rule.label)
                        .font(.appText(12))
                        .foregroundStyle(rule.passed ? Color.appFg2 : Color.appFg3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.xs)
    }
}

private struct FederatedAuthSection: View {
    @Bindable var viewModel: AuthViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Rectangle().fill(Color.appRule).frame(height: 1)
                Text("auth.divider.or")
                    .font(.appText(12, weight: .medium))
                    .foregroundStyle(Color.appFg3)
                Rectangle().fill(Color.appRule).frame(height: 1)
            }

            SignInWithAppleButton(.continue) { request in
                viewModel.prepareAppleRequest(request)
            } onCompletion: { result in
                Task { await viewModel.handleAppleResult(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))

            Button {
                Task { await viewModel.submitGoogle() }
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("auth.continueWithGoogle")
                        .font(.appText(15, weight: .semibold))
                }
                .foregroundStyle(Color.appFg)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.appSurface2, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .stroke(Color.appRule, lineWidth: 1)
                )
            }
            .disabled(viewModel.isWorking)
        }
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

private struct AppPasswordField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if isRevealed {
                    TextField(title, text: $text)
                        .focused(isFocused)
                } else {
                    SecureField(title, text: $text)
                        .focused(isFocused)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .font(.appText(15))
            .foregroundStyle(Color.appFg)

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.appFg3)
                    .frame(width: 32, height: 32)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(Text(isRevealed ? "auth.password.hide" : "auth.password.show"))
        }
        .padding(.leading, AppSpacing.lg)
        .padding(.trailing, AppSpacing.sm)
        .padding(.vertical, 8)
        .background(Color.appSurface2, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }
}
