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
    
    private let dataOutputQueue = DispatchQueue(label: "VideoDataQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    private let writeOutputQueue = DispatchQueue(label: "WriteDataQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    private var videoInputs: AVCaptureSessionVideoInputs!
    
    private let videoDataOutput = AVCaptureVideoDataOutput()
    
    private var assetWriters: [AVAssetWriter] = []
    private var assetWriterTimes: [CMTime] = []
    
    private var isSessionRunning = false
    
    private var renderingEnabled = true
    
    private var shouldAskReuseQuestion = false
    
    @IBOutlet private weak var videoView: PreviewMetalView!
    @IBOutlet private weak var resumeButton: UIButton!
    @IBOutlet private weak var cameraUnavailableLabel: UILabel!
    @IBOutlet private weak var recordButton: UISwitch!
    @IBOutlet private weak var cameraButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let tempFileCount = writtenTempVideoUrls().count
        if tempFileCount == 2 {
            shouldAskReuseQuestion = true
        }
        switch tempFileCount {
        case 2:
            shouldAskReuseQuestion = true
            
        case 0:
            break
            
        default:
            clearTempVideoFiles()
        }
        
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
        
        let interfaceOrientation = UIApplication.shared.statusBarOrientation
        
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                self.addObservers()
                
                if let unwrappedVideoDataOutputConnection = self.videoDataOutput.connection(with: .video) {
                    let videoDevicePosition = self.currentVideoDeviceInput().device.position
                    let rotation = PreviewMetalView.Rotation(with: interfaceOrientation,
                                                             videoOrientation: unwrappedVideoDataOutputConnection.videoOrientation,
                                                             cameraPosition: videoDevicePosition)
                    self.videoView.mirroring = (videoDevicePosition == .front)
                    if let rotation = rotation {
                        self.videoView.rotation = rotation
                    }
                }
                
                self.dataOutputQueue.async {
                    self.renderingEnabled = true
                }
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                
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
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if shouldAskReuseQuestion {
            let question =
                UIAlertController.simpleQuestionAlertWith(title: "FilterBrim",
                                                          message: "There are recorded files saved. Do you want to use them?",
                                                          yesAction: {
                                                            self.shouldAskReuseQuestion = false
                                                            self.goToCompositionScreen()
                },
                                                          noAction: {
                                                            self.shouldAskReuseQuestion = false
                                                            self.clearTempVideoFiles()
                })
            self.present(question, animated: true, completion: nil)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        dataOutputQueue.async {
            self.renderingEnabled = false
        }
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
    
    func renderVideo(sampleBuffer: CMSampleBuffer) {
        if !renderingEnabled {
            return
        }
        
        guard let videoPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
        }
        
        videoView.pixelBuffer = videoPixelBuffer
    }
    
    // MARK: - Video file writing
    
    func writeSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }
        
        guard assetWriters.count > 0 else {
            return
        }
        
        let writer = assetWriters.last!
        
        guard writer.status == .writing else {
            return
        }
        
        let writerInput = writer.inputs.first!
        guard writerInput.isReadyForMoreMediaData else {
            return
        }
        
        let index = assetWriters.firstIndex(of: writer)!
        if assetWriterTimes.count == index {
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            assetWriterTimes.append(time)
            writer.startSession(atSourceTime: time)
        }
        
        writerInput.append(sampleBuffer)
    }
    
    // MARK: - Session management
    
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        
        let preset = AVCaptureSession.Preset.hd1920x1080
        
        guard session.canSetSessionPreset(preset) else {
            print("Can't set session preset")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        session.sessionPreset = preset
        
        videoInputs = AVCaptureSessionVideoInputs(with: session)
        
        guard let videoInput = videoInputs.availableInputs.first else {
            print("No suitable video input found")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        session.addInput(videoInput)
        
        // Add a video data output
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            videoDataOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
        } else {
            print("Could not add video data output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
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
    
    func currentVideoDeviceInput() -> AVCaptureDeviceInput {
        let availableSet = Set(self.videoInputs.availableInputs)
        let sessionSet = Set(self.session.inputs)
        var intersection = sessionSet.intersection(availableSet)
        guard intersection.count == 1 else {
            fatalError("")
        }
        
        return intersection.popFirst()! as! AVCaptureDeviceInput
    }
    
    func tempVideoUrls() -> [URL] {
        let tempFolderPath =
            NSSearchPathForDirectoriesInDomains(.documentDirectory,
                                                .userDomainMask,
                                                true).first!
        var urls: [URL] = []
        for i in 1...2 {
            let videoPath = tempFolderPath.appending("/temp\(i).mov")
            let tempVideoUrl = URL(fileURLWithPath: videoPath)
            urls.append(tempVideoUrl)
        }
        
        return urls
    }
    
    func writtenTempVideoUrls() -> [URL] {
        let fileManager = FileManager.default
        var writtenUrls: [URL] = []
        for url in tempVideoUrls() {
            if fileManager.fileExists(atPath: url.path) {
                writtenUrls.append(url)
            }
        }
        return writtenUrls
    }
    
    func clearTempVideoFiles() {
        for url in writtenTempVideoUrls() {
            try! FileManager.default.removeItem(at: url)
        }
    }
    
    func goToCompositionScreen() {
        let urls = tempVideoUrls()
        performSegue(withIdentifier: "showComposition", sender: urls)
    }
    
    // MARK: - IBActions
    
    @IBAction func didTapCameraButton(_ sender: UIButton) {
        cameraButton.isEnabled = false
        recordButton.isEnabled = false
        
        let interfaceOrientation = UIApplication.shared.statusBarOrientation
        
        dataOutputQueue.sync {
            renderingEnabled = false
            videoView.pixelBuffer = nil
        }
        
        sessionQueue.async {
            let currentVideoInput = self.currentVideoDeviceInput()
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
            
            let videoPosition = currentVideoInput.device.position
            
            if let unwrappedVideoDataOutputConnection = self.videoDataOutput.connection(with: .video) {
                let rotation = PreviewMetalView.Rotation(with: interfaceOrientation,
                                                         videoOrientation: unwrappedVideoDataOutputConnection.videoOrientation,
                                                         cameraPosition: videoPosition)
                
                self.videoView.mirroring = (videoPosition == .front)
                if let rotation = rotation {
                    self.videoView.rotation = rotation
                }
            }
            
            self.dataOutputQueue.async {
                self.renderingEnabled = true
            }
            
            DispatchQueue.main.async {
                self.cameraButton.isEnabled = true
                self.recordButton.isEnabled = true
            }
        }
    }
    
    @IBAction func recordStateDidChange(_ sender: UISwitch) {
        if sender.isOn {
            writeOutputQueue.async {
                var urlCount = self.assetWriters.count
                urlCount += 1
                let tempFolderPath =
                    NSSearchPathForDirectoriesInDomains(.documentDirectory,
                                                        .userDomainMask,
                                                        true).first!
                let videoPath = tempFolderPath.appending("/temp\(urlCount).mov")
                let tempVideoUrl = URL(fileURLWithPath: videoPath)
                if FileManager.default.fileExists(atPath: tempVideoUrl.path) {
                    try! FileManager.default.removeItem(at: tempVideoUrl)
                }
                
                let fileType = AVFileType.mov
                let codecTypes =
                    self.videoDataOutput.availableVideoCodecTypesForAssetWriter(writingTo: fileType)
                let settings: [AnyHashable : Any]
                if codecTypes.contains(.hevc) {
                    settings =
                        self.videoDataOutput.recommendedVideoSettings(forVideoCodecType: .hevc,
                                                                      assetWriterOutputFileType: fileType)!
                } else {
                    settings =
                        self.videoDataOutput.recommendedVideoSettingsForAssetWriter(writingTo: fileType)!
                }
                let assetWriter = try! AVAssetWriter(outputURL: tempVideoUrl,
                                                     fileType: fileType)
                
                let writerInput = AVAssetWriterInput(mediaType: .video,
                                                     outputSettings: settings as? [String : Any])
                writerInput.expectsMediaDataInRealTime = true
                let height: Int = settings[AVVideoHeightKey] as! Int
                var transform = CGAffineTransform(rotationAngle: .pi / 2)
                transform = transform.translatedBy(x: 0, y: -CGFloat(height))
                writerInput.transform = transform
                guard assetWriter.canAdd(writerInput) else {
                    fatalError("Cannot add input to video writer")
                }
                assetWriter.add(writerInput)
                self.assetWriters.append(assetWriter)
                assetWriter.startWriting()
            }
        } else {
            recordButton.isEnabled = false
            writeOutputQueue.async {
                let writer = self.assetWriters.last!
                let writerInput = writer.inputs.first!
                writerInput.markAsFinished()
                writer.finishWriting {
                    if writer.status != .completed {
                        print(writer.error!.localizedDescription)
                    }
                    DispatchQueue.main.async {
                        self.recordButton.isEnabled = true
                        if self.assetWriters.count == 2 {
                            self.goToCompositionScreen()
                        }
                    }
                }
            }
        }
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
    
    @IBAction func unwindToCapture(segue: UIStoryboardSegue) {
        assetWriters = []
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let urls = sender as! [URL]
        let compVC = segue.destination as! CompositionViewController
        compVC.backgroundVideoUrl = urls.last!
        compVC.foregroundVideoUrl = urls.first!
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
        dataOutputQueue.async {
            self.renderingEnabled = false
            self.videoView.pixelBuffer = nil
            self.videoView.flushTextureCache()
        }
    }
    
    @objc
    func willEnterForground(notification: NSNotification) {
        dataOutputQueue.async {
            self.renderingEnabled = true
        }
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

extension CaptureViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        renderVideo(sampleBuffer: sampleBuffer)
        writeOutputQueue.async {
            self.writeSampleBuffer(sampleBuffer)
        }
    }
}
