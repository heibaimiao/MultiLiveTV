import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var api: APIClient
    @State private var email = ""
    @State private var password = ""
    @State private var isRegister = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                if api.isLoggedIn {
                    Section {
                        Text("已登录")
                        Button("退出", role: .destructive) { api.logout() }
                    }
                } else {
                    Section {
                        TextField("邮箱", text: $email)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            #endif
                        SecureField("密码", text: $password)
                    }
                    Section {
                        Button(isRegister ? "注册" : "登录") {
                            Task { await submit() }
                        }
                        Button(isRegister ? "已有账号？登录" : "没有账号？注册") {
                            isRegister.toggle()
                        }
                    }
                }
                if let message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("账户")
        }
    }

    private func submit() async {
        message = nil
        do {
            if isRegister {
                try await api.register(email: email, password: password)
                message = "注册成功"
            } else {
                try await api.login(email: email, password: password)
                message = "登录成功"
            }
        } catch {
            message = error.localizedDescription
        }
    }
}
