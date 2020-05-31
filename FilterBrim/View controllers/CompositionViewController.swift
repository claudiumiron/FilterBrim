//
//  CompositionViewController.swift
//  FilterBrim
//
//  Created by Claudiu Miron on 28/05/2020.
//  Copyright © 2020 Apple. All rights reserved.
//

import AVFoundation
import UIKit

class CompositionViewController: UIViewController {
    
    public var backgroundVideoUrl: URL!
    
    public var foregroundVideoUrl: URL!
    
    private var composition: AVMutableComposition! = AVMutableComposition()
    
    private let dataOutputQueue = DispatchQueue(label: "VideoDataQueue",
                                                qos: .userInitiated,
                                                attributes: [],
                                                autoreleaseFrequency: .workItem)
    
    private var videoOutput: AVPlayerItemVideoOutput!
    
    private var bgAsset: AVAsset?
    
    private var fgAsset: AVAsset?
    
    private var player: AVPlayer!
    
    private var players: [AVPlayer] = []
    
    private var displayLink: CADisplayLink!
    
    private var availableBgCiFilters: [CIFilter] = []
    private var currentBgFilterIndex = -1
    
    private var videoCompositor: FilterVideoCompositor!
    
    @IBOutlet private weak var backgroundView: PreviewMetalView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupBgFilters()
        
        let bgAsset = AVAsset(url: backgroundVideoUrl)
        bgAsset.prepare(properties: ["tracks", "duration"]) {
            self.bgAsset = bgAsset
            self.assetLoaded()
        }
        
        let fgAsset = AVAsset(url: foregroundVideoUrl)
        fgAsset.prepare(properties: ["tracks", "duration"]) {
            self.fgAsset = fgAsset
            self.assetLoaded()
        }
        
        let leftSwipeGesture = UISwipeGestureRecognizer(target: self, action: #selector(leftFilterSwipe))
        leftSwipeGesture.direction = .left
        backgroundView.addGestureRecognizer(leftSwipeGesture)
        
        let rightSwipeGesture = UISwipeGestureRecognizer(target: self, action: #selector(rightFilterSwipe))
        rightSwipeGesture.direction = .right
        backgroundView.addGestureRecognizer(rightSwipeGesture)
        
        backgroundView.rotation = .rotate90Degrees
    }
    
    private func assetLoaded() {
        guard let bgAsset = bgAsset, let fgAsset = fgAsset else {
            return
        }
        
        guard (bgAsset.duration.isNumeric && fgAsset.duration.isNumeric) else {
            return
        }
        
        var timeRange = CMTimeRange()
        timeRange.start = .zero
        timeRange.duration =
            bgAsset.duration.seconds < fgAsset.duration.seconds ?
                bgAsset.duration : fgAsset.duration
        
        let compBgVideoTrack = composition.addMutableTrack(withMediaType: .video,
                                                           preferredTrackID: 2)!
        let assetBgVideoTrack = bgAsset.firstVideoTrack!
        //compBgVideoTrack.preferredTransform = assetBgVideoTrack.preferredTransform
        try! compBgVideoTrack.insertTimeRange(timeRange,
                                              of: assetBgVideoTrack,
                                              at: .zero)
        
        let compFgVideoTrack = composition.addMutableTrack(withMediaType: .video,
                                                           preferredTrackID: 1)!
        let assetFgVideoTrack = fgAsset.firstVideoTrack!
        try! compFgVideoTrack.insertTimeRange(timeRange,
                                              of: assetFgVideoTrack,
                                              at: .zero)
        
        let naturalSize = assetBgVideoTrack.naturalSize
        let transformedSize =
            naturalSize.applying(assetBgVideoTrack.preferredTransform)
        let renderSize = CGSize(width: abs(transformedSize.width),
                                height: abs(transformedSize.height))
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = naturalSize//renderSize
        videoComposition.frameDuration =
            CMTimeMakeWithSeconds(Float64(1.0 / assetBgVideoTrack.nominalFrameRate),
                                  preferredTimescale: assetBgVideoTrack.naturalTimeScale);
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = composition.tracks.first!.timeRange
        
        let fgInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: assetFgVideoTrack)
        fgInstruction.trackID = 1
        
        let bgInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: assetBgVideoTrack)
        bgInstruction.trackID = 2
        
        let scale: CGFloat = 0.5
        var fgTransform = assetFgVideoTrack.preferredTransform
        fgTransform = fgTransform.scaledBy(x: scale, y: scale)
        
        fgInstruction.setOpacity(0.7, at: .zero)
        fgInstruction.setTransform(fgTransform, at: .zero)
        
        let bgTransform = assetBgVideoTrack.preferredTransform
        bgInstruction.setTransform(bgTransform, at: .zero)
        
        instruction.layerInstructions = [fgInstruction, bgInstruction]
        videoComposition.instructions = [instruction]
        videoComposition.customVideoCompositorClass = FilterVideoCompositor.self
        
        dataOutputQueue.async {
            let settings =
                [kCVPixelBufferPixelFormatTypeKey as String : Int(kCVPixelFormatType_32BGRA)]
            self.videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: settings)
            
            let playerItem = AVPlayerItem(asset: self.composition)
            playerItem.videoComposition = videoComposition
            playerItem.add(self.videoOutput)
            
            self.videoCompositor =
                playerItem.customVideoCompositor as! FilterVideoCompositor
            
            let bgTransformFilter = CIFilter(name: "CIAffineTransform")
            bgTransformFilter!.setValue(bgTransform, forKey: kCIInputTransformKey)
            let bgCIFilters: [CIFilter] = [
                CIFilter(name: "CIPhotoEffectNoir")!//, bgTransformFilter!
            ]
            
            let opacity = CIFilter(name: "CIColorMatrix")
            opacity!.setValue(CIVector(x: 0.0, y: 0.0, z: 0.0, w: 0.7), forKey: "inputAVector")
            let scale = CIFilter(name: "CIAffineTransform")
            scale!.setValue(CGAffineTransform(scaleX: 0.5, y: 0.5), forKey: kCIInputTransformKey)
            let fgCIFilters: [CIFilter] = [
                opacity!, scale!
            ]
            
            //self.videoCompositor.set(ciFilters: bgCIFilters, forTrackId: 2)
            self.videoCompositor.set(ciFilters: fgCIFilters, forTrackId: 1)
            
            self.player = AVPlayer(playerItem: playerItem)
            self.player.actionAtItemEnd = .none
            self.player.play()
            
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(self.playerItemDidFinish(notification:)),
                                                   name: .AVPlayerItemDidPlayToEndTime,
                                                   object: playerItem)
            
            self.displayLink = CADisplayLink(target: self,
                                            selector: #selector(self.displayLinkUpdate))
            self.displayLink.add(to: .main, forMode: .common)
        }
        
    }
    
    @objc func playerItemDidFinish(notification: Notification) {
        let item = notification.object as! AVPlayerItem
        item.seek(to: .zero, completionHandler: nil)
    }
    
    @objc func displayLinkUpdate() {
        dataOutputQueue.async {
            guard let item = self.player.currentItem else {
                return
            }
            
            guard let buffer =
                self.videoOutput.copyPixelBuffer(forItemTime: item.currentTime(),
                                                 itemTimeForDisplay:nil) else {
                                                    return
            }
            self.backgroundView.pixelBuffer = buffer
        }
    }
    
    @objc func leftFilterSwipe() {
        print("left swipe")
        currentBgFilterIndex += 1
        
        if currentBgFilterIndex >= availableBgCiFilters.count {
            currentBgFilterIndex = -1
        }
        let filter = bgFilter(for: currentBgFilterIndex)
        set(bgFilter: filter)
    }
    
    @objc func rightFilterSwipe() {
        print("right swipe")
        currentBgFilterIndex -= 1
        
        if currentBgFilterIndex < -1 {
            currentBgFilterIndex = availableBgCiFilters.count - 1
        }
        
        let filter = bgFilter(for: currentBgFilterIndex)
        set(bgFilter: filter)
    }
    
    private func bgFilter(for index: Int) -> CIFilter? {
        switch index {
        case -1:
            return nil
            
        default:
            return availableBgCiFilters[index]
        }
    }
    
    private func set(bgFilter: CIFilter?) {
        var filters: [CIFilter] = []
        if let filter = bgFilter {
            filters.append(filter)
        }
        videoCompositor.set(ciFilters: filters, forTrackId: 2)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.composition = nil
        self.videoCompositor = nil
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        self.displayLink.remove(from: .main, forMode: .common)
        
        self.player.pause()
    }
    
    private func setupBgFilters() {
        let noir    = CIFilter(name: "CIPhotoEffectNoir")!
        let chrome  = CIFilter(name: "CIPhotoEffectChrome")!
        let instant = CIFilter(name: "CIPhotoEffectInstant")!
        
        availableBgCiFilters = [noir, chrome, instant]
        currentBgFilterIndex = -1
    }
    
}
