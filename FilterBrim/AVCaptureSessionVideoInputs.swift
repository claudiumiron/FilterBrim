//
//  AVCaptureSessionVideoInputs.swift
//  FilterBrim
//
//  Created by Claudiu Miron on 28/05/2020.
//  Copyright © 2020 Apple. All rights reserved.
//

import AVFoundation
import Foundation

class AVCaptureSessionVideoInputs {
    
    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera,
                                                                                             .builtInWideAngleCamera,
                                                                                             .builtInTelephotoCamera,
                                                                                             .builtInTrueDepthCamera],
                                                                               mediaType: .video,
                                                                               position: .unspecified)
    
    public let availableInputs: [AVCaptureDeviceInput]
    
    init(with session: AVCaptureSession) {
        var inputs: [AVCaptureDeviceInput] = []
        for device in videoDeviceDiscoverySession.devices {
            if let input = try? AVCaptureDeviceInput(device: device) {
                if session.canAddInput(input) {
                    inputs.append(input)
                }
            }
        }
        availableInputs = inputs
    }
}
