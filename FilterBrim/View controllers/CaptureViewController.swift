//
//  CaptureViewController.swift
//  FilterBrim
//
//  Created by Claudiu Miron on 28/05/2020.
//  Copyright © 2020 Apple. All rights reserved.
//

import UIKit

class CaptureViewController: UIViewController {
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private var setupResult: SessionSetupResult = .success
        
    // Communicate with the session and other session objects on this queue.
    private let sessionQueue = DispatchQueue(label: "SessionQueue", attributes: [], autoreleaseFrequency: .workItem)
    
    @IBOutlet weak var videoView: UIView!
    @IBOutlet private weak var resumeButton: UIButton!
    @IBOutlet private weak var cameraUnavailableLabel: UILabel!
    @IBOutlet private weak var recordButton: UISwitch!
    @IBOutlet private weak var cameraButton: UIButton!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Disable UI. The UI is enabled if and only if the session starts running.
        cameraButton.isEnabled = false
        recordButton.isEnabled = false
        
        // Check video authorization status, video access is required
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera
            break
            
        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant video access
             Suspend the SessionQueue to delay session setup until the access request has completed
             */
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
            
        default:
            // The user has previously denied access
            setupResult = .notAuthorized
        }
    
    // MARK: - IBActions
    
    @IBAction func didTapCameraButton(_ sender: UIButton) {
    }
    
    @IBAction func recordStateDidChange(_ sender: UISwitch) {
    }
    
    
    @IBAction func didTapResumeButton(_ sender: UIButton) {
        
    }
    
    }
}
