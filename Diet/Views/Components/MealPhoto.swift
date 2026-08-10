import SwiftUI
import UIKit

struct MealPhoto: View {
    let data: Data?
    var height: CGFloat = 160

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [AppTheme.paleLime, AppTheme.mint.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "fork.knife")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(AppTheme.ink.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
    }
}
