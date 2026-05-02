import SwiftUI

struct AuthView: View {
    @Environment(AppSession.self) private var session
    @State private var viewModel: AuthViewModel?

    var body: some View {
        NavigationStack {
            VStack {
                BrandHeader(subtitle: "auth.subtitle")
                    .padding(.top, 40)

                if let viewModel {
                    AuthForm(viewModel: viewModel)
                }

                Spacer()
            }
            .padding()
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
        VStack(spacing: 16) {
            Picker("auth.mode", selection: $viewModel.mode) {
                Text("auth.signIn").tag(AuthViewModel.Mode.signIn)
                Text("auth.signUp").tag(AuthViewModel.Mode.signUp)
            }
            .pickerStyle(.segmented)

            if viewModel.mode == .signUp {
                TextField("auth.displayName", text: $viewModel.displayName)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
            }

            TextField("auth.email", text: $viewModel.email)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()

            SecureField("auth.password", text: $viewModel.password)
                .textFieldStyle(.roundedBorder)

            if viewModel.mode == .signUp {
                HStack {
                    Text("auth.password.requirement \(AppConfig.minimumPasswordLength)")
                        .font(.caption)
                        .foregroundStyle(viewModel.passwordMeetsMinimum ? Color.secondary : Color.red)
                    Spacer()
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await viewModel.submit() }
            } label: {
                if viewModel.isWorking {
                    ProgressView()
                } else {
                    Text(viewModel.mode == .signIn ? "auth.signIn" : "auth.signUp")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isWorking || !viewModel.canSubmit)
        }
        .padding()
    }
}
