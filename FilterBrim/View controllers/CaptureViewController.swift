//
//  CaptureViewController.swift
//  FilterBrim
//
//  Created by Claudiu Miron on 28/05/2020.
//  Copyright © 2020 Apple. All rights reserved.
//

import AVFoundation
import UIKit

class CaptureViewController: UIViewController {
    
    private let session = AVCaptureSession()
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private var setupResult: SessionSetupResult = .success
        
    // Communicate with the session and other session objects on this queue.
    private let sessionQueue = DispatchQueue(label: "SessionQueue", attributes: [], autoreleaseFrequency: .workItem)
    
    private let audioDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInMicrophone],
                                                                               mediaType: .audio,
                                                                               position: .unspecified)
    
    private var videoInputs: AVCaptureSessionVideoInputs!
    
    private let videoFileOutput = AVCaptureMovieFileOutput()
    
    private var isSessionRunning = false
    
    @IBOutlet private weak var videoView: UIView!
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
        
        /*
         Setup the capture session.
         In general it is not safe to mutate an AVCaptureSession or any of its
         inputs, outputs, or connections from multiple threads at the same time.
         
         Don't do this on the main queue, because AVCaptureSession.startRunning()
         is a blocking call, which can take a long time. Dispatch session setup
         to the sessionQueue so as not to block the main queue, which keeps the UI responsive.
         */
        sessionQueue.async {
            self.configureSession()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                self.addObservers()
                
                self.session.startRunning()
                
                DispatchQueue.main.async {
                    self.setupLivePreview(session: self.session)
                }
                
            case .notAuthorized:
                DispatchQueue.main.async {
                    let message = NSLocalizedString("CameraPermissionDenied",
                                                    comment: "Alert message when the user has denied access to the camera")
                    let actions = [
                        UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                      style: .cancel,
                                      handler: nil),
                        UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                      style: .`default`,
                                      handler: { _ in
                                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                                  options: [:],
                                                                  completionHandler: nil)
                        })
                    ]
                    
                    self.alert(title: "FilterBrim", message: message, actions: actions)
                }
                
            case .configurationFailed:
                DispatchQueue.main.async {
                    
                    let message = NSLocalizedString("Unable to capture media",
                                                    comment: "Alert message when something goes wrong during capture session configuration")
                    
                    self.alert(title: "FilterBrim",
                               message: message,
                               actions: [UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                       style: .cancel,
                                                       handler: nil)])
                }
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
                self.removeObservers()
            }
        }
        
        super.viewWillDisappear(animated)
    }
    
    // MARK: - Screen rendering
    
    func setupLivePreview(session: AVCaptureSession) {
        let videoPreviewLayer = AVCaptureVideoPreviewLayer(session: session)
        videoPreviewLayer.videoGravity = .resizeAspectFill
        videoPreviewLayer.connection?.videoOrientation = .portrait
        videoView.layer.addSublayer(videoPreviewLayer)
        videoPreviewLayer.frame = videoView.bounds
    }
    
    // MARK: - Session management
    
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        
        session.sessionPreset = AVCaptureSession.Preset.hd1920x1080
        
        videoInputs = AVCaptureSessionVideoInputs(with: session)
        
        guard let videoInput = videoInputs.availableInputs.first else {
            print("No suitable video input found")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        session.addInput(videoInput)
        
        guard session.canAddOutput(videoFileOutput) else {
            print("Could not add video file output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        session.addOutput(videoFileOutput)
        
        if let audioDevice = audioDeviceDiscoverySession.devices.first {
            if let audioInput = try? AVCaptureDeviceInput(device: audioDevice) {
                if session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                }
            }
        }
        
        session.commitConfiguration()
    }
    
    @objc
    func sessionRuntimeError(notification: NSNotification) {
        guard let errorValue = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError else {
            return
        }
        
        let error = AVError(_nsError: errorValue)
        print("Capture session runtime error: \(error)")
        
        /*
         Automatically try to restart the session running if media services were
         reset and the last start running succeeded. Otherwise, enable the user
         to try to resume the session running.
         */
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                } else {
                    DispatchQueue.main.async {
                        self.resumeButton.isHidden = false
                    }
                }
            }
        } else {
            resumeButton.isHidden = false
        }
    }
    
    @objc
    func sessionWasInterrupted(notification: NSNotification) {
        // In iOS 9 and later, the userInfo dictionary contains information on why the session was interrupted.
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
            let reasonIntegerValue = userInfoValue.integerValue,
            let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            print("Capture session was interrupted with reason \(reason)")
            
            if reason == .videoDeviceInUseByAnotherClient {
                // Simply fade-in a button to enable the user to try to resume the session running.
                resumeButton.isHidden = false
                resumeButton.alpha = 0.0
                UIView.animate(withDuration: 0.25) {
                    self.resumeButton.alpha = 1.0
                }
            } else if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
                // Simply fade-in a label to inform the user that the camera is unavailable.
                cameraUnavailableLabel.isHidden = false
                cameraUnavailableLabel.alpha = 0.0
                UIView.animate(withDuration: 0.25) {
                    self.cameraUnavailableLabel.alpha = 1.0
                }
            }
        }
    }
    
    @objc
    func sessionInterruptionEnded(notification: NSNotification) {
        if !resumeButton.isHidden {
            UIView.animate(withDuration: 0.25,
                           animations: {
                            self.resumeButton.alpha = 0
            }, completion: { _ in
                self.resumeButton.isHidden = true
            }
            )
        }
        if !cameraUnavailableLabel.isHidden {
            UIView.animate(withDuration: 0.25,
                           animations: {
                            self.cameraUnavailableLabel.alpha = 0
            }, completion: { _ in
                self.cameraUnavailableLabel.isHidden = true
            }
            )
        }
    }
    
    // MARK: - Utilities
    
    func alert(title: String, message: String, actions: [UIAlertAction]) {
        let alertController = UIAlertController(title: title,
                                                message: message,
                                                preferredStyle: .alert)
        
        actions.forEach {
            alertController.addAction($0)
        }
        
        self.present(alertController, animated: true, completion: nil)
    }
    
    // MARK: - IBActions
    
    @IBAction func didTapCameraButton(_ sender: UIButton) {
        cameraButton.isEnabled = false
        recordButton.isEnabled = false
        
        sessionQueue.async {
            let availableSet = Set(self.videoInputs.availableInputs)
            let sessionSet = Set(self.session.inputs)
            var intersection = sessionSet.intersection(availableSet)
            guard intersection.count == 1 else {
                fatalError("")
            }
            
            let currentVideoInput =
                intersection.popFirst()! as! AVCaptureDeviceInput
            let currentVideoInputIndex =
                self.videoInputs.availableInputs.firstIndex(of: currentVideoInput)!
            var nextVideoInputIndex = currentVideoInputIndex + 1
            if nextVideoInputIndex == self.videoInputs.availableInputs.count {
                nextVideoInputIndex = 0
            }
            let nextVideoInput = self.videoInputs.availableInputs[nextVideoInputIndex]
            
            self.session.beginConfiguration()
            
            // Remove the existing device input first, since using the front and back camera simultaneously is not supported.
            self.session.removeInput(currentVideoInput)
            self.session.addInput(nextVideoInput)
            
            self.session.commitConfiguration()
            
            DispatchQueue.main.async {
                self.cameraButton.isEnabled = true
                self.recordButton.isEnabled = true
            }
        }
    }
    
    @IBAction func recordStateDidChange(_ sender: UISwitch) {
        
    }
    
    
    @IBAction func didTapResumeButton(_ sender: UIButton) {
        sessionQueue.async {
                   /*
                    The session might fail to start running. A failure to start the session running will be communicated via
                    a session runtime error notification. To avoid repeatedly failing to start the session
                    running, we only try to restart the session running in the session runtime error handler
                    if we aren't trying to resume the session running.
                    */
                   self.session.startRunning()
                   self.isSessionRunning = self.session.isRunning
                   if !self.session.isRunning {
                       DispatchQueue.main.async {
                           let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
                           let actions = [
                               UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                             style: .cancel,
                                             handler: nil)]
                           self.alert(title: "FilterBrim", message: message, actions: actions)
                       }
                   } else {
                       DispatchQueue.main.async {
                           self.resumeButton.isHidden = true
                       }
                   }
               }
    }
    
    // MARK: - KVO and Notifications
    
    private var sessionRunningContext = 0
    
    private func addObservers() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(willEnterForground),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(thermalStateChanged),
                                               name: ProcessInfo.thermalStateDidChangeNotification,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionRuntimeError),
                                               name: NSNotification.Name.AVCaptureSessionRuntimeError,
                                               object: session)
        
        session.addObserver(self, forKeyPath: "running", options: NSKeyValueObservingOptions.new, context: &sessionRunningContext)
        
        // A session can run only when the app is full screen. It will be interrupted in a multi-app layout.
        // Add observers to handle these session interruptions and inform the user.
        // See AVCaptureSessionWasInterruptedNotification for other interruption reasons.
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionWasInterrupted),
                                               name: NSNotification.Name.AVCaptureSessionWasInterrupted,
                                               object: session)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionInterruptionEnded),
                                               name: NSNotification.Name.AVCaptureSessionInterruptionEnded,
                                               object: session)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        session.removeObserver(self, forKeyPath: "running", context: &sessionRunningContext)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if context == &sessionRunningContext {
            let newValue = change?[.newKey] as AnyObject?
            guard let isSessionRunning = newValue?.boolValue else { return }
            DispatchQueue.main.async {
                let videoInputsCount = self.videoInputs.availableInputs.count
                self.cameraButton.isHidden = videoInputsCount < 2
                self.cameraButton.isEnabled = isSessionRunning
                self.recordButton.isEnabled = isSessionRunning
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    // MARK: - UIApplication life cycle
    
    @objc
    func didEnterBackground(notification: NSNotification) {
        
    }
    
    @objc
    func willEnterForground(notification: NSNotification) {
        
    }
    
    // Use this opportunity to take corrective action to help cool the system down.
    @objc
    func thermalStateChanged(notification: NSNotification) {
        if let processInfo = notification.object as? ProcessInfo {
            showThermalState(state: processInfo.thermalState)
        }
    }
    
    func showThermalState(state: ProcessInfo.ThermalState) {
        DispatchQueue.main.async {
            var thermalStateString = "UNKNOWN"
            if state == .nominal {
                thermalStateString = "NOMINAL"
            } else if state == .fair {
                thermalStateString = "FAIR"
            } else if state == .serious {
                thermalStateString = "SERIOUS"
            } else if state == .critical {
                thermalStateString = "CRITICAL"
            }
            
            let message = NSLocalizedString("Thermal state: \(thermalStateString)", comment: "Alert message when thermal state has changed")
            let actions = [
                UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                              style: .cancel,
                              handler: nil)]
            
            self.alert(title: "FilterBrim", message: message, actions: actions)
        }
    }
}
