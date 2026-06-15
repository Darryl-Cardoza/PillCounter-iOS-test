//
//  SuccessAnimationView.swift
//  PillCounter
//

import SwiftUI

struct SuccessAnimationView: View {
    let count: Int
    let color: Color

    @State private var particles: [ConfettiParticle] = []
    @State private var scale: CGFloat = 0.1
    @State private var opacity: Double = 1.0

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .position(x: particle.x, y: particle.y)
                    .opacity(particle.opacity)
            }
            Text("+\(count)")
                .font(.system(size: 80, weight: .heavy))
                .foregroundStyle(color)
                .scaleEffect(scale)
                .opacity(opacity)
                .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 0)
        }
        .onAppear { createParticles(); animate() }
    }

    private func createParticles() {
        let colors: [Color] = [color, .red, .blue, .yellow, .green, .orange, .purple]
        for _ in 0..<50 {
            let angle = Double.random(in: 0..<360) * .pi / 180
            let speed = Double.random(in: 200...500)
            particles.append(ConfettiParticle(
                x: UIScreen.main.bounds.width / 2,
                y: UIScreen.main.bounds.height / 2,
                vx: cos(angle) * speed,
                vy: sin(angle) * speed,
                color: colors.randomElement() ?? .blue,
                size: CGFloat.random(in: 5...12),
                opacity: 1.0
            ))
        }
    }

    private func animate() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { scale = 1.5 }
        withAnimation(.easeOut(duration: 1.5)) {
            for i in particles.indices {
                particles[i].x += particles[i].vx
                particles[i].y += particles[i].vy
                particles[i].opacity = 0
            }
        }
        withAnimation(.easeIn(duration: 0.5).delay(2.0)) { opacity = 0 }
    }
}

struct ConfettiParticle: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    let color: Color
    let size: CGFloat
    var opacity: Double
}
