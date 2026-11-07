import SwiftUI

/// Third-party components and data used by NOVA's own voice (attribution required by their licences).
struct LicensesView: View {
    @EnvironmentObject private var model: AppModel

    private let items: [(String, String)] = [
        ("ONNX Runtime", "Copyright (c) Microsoft Corporation. MIT License."),
        ("CMU Pronouncing Dictionary", "Copyright (C) 1993-2015 Carnegie Mellon University. All rights reserved. Redistribution and use in source and binary forms, with or without modification, are permitted provided that the copyright notice, this list of conditions and the following disclaimer are retained. THIS SOFTWARE IS PROVIDED BY CARNEGIE MELLON UNIVERSITY \"AS IS\" AND ANY EXPRESSED OR IMPLIED WARRANTIES ARE DISCLAIMED."),
        ("Kokoro-82M", "hexgrad. Apache License 2.0. Used offline to create the voice timbre and English training audio."),
        ("Chatterbox Multilingual", "Resemble AI. MIT License. Used offline to create Turkish training audio."),
        ("Piper", "Base checkpoint trained on LJ Speech (public domain). The NOVA voice models were trained by us with Piper."),
        ("Mozilla Common Voice", "Training sentences from the Common Voice sentence collection (CC0 1.0).")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(model.t("NOVA'nın sesi gerçek bir kişinin sesi değildir; yapay olarak tasarlanmış ve cihazda çalışan bir modeldir.",
                             "NOVA's voice is not a real person's voice; it is a synthetic voice running on your device."))
                    .font(Theme.body).foregroundStyle(Theme.textSecondary)
                ForEach(items.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(items[index].0).font(Theme.headline).foregroundStyle(.white)
                        Text(items[index].1).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(20)
        }
        .novaBackground()
        .navigationTitle(model.t("Lisanslar", "Licences"))
    }
}
