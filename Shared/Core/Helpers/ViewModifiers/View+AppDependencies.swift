import SwiftUI

extension View {
    func injectAppDependencies(_ dependencies: AppDependencies) -> some View {
        self
            .modelContainer(dependencies.modelContainer)
            .environment(dependencies)
            .environment(\.youtube, dependencies.youtube)
            .environment(\.router, dependencies.router)
            .environment(dependencies.prefetchSettings)
            .environment(dependencies.playerViewModel)
            .environment(dependencies.searchViewModel)
            .environment(dependencies.networkMonitor)
    }

    func injectSettingsDependencies(_ dependencies: AppDependencies) -> some View {
        self
            .environment(dependencies)
            .environment(dependencies.prefetchSettings)
            .environment(dependencies.networkMonitor)
    }
}