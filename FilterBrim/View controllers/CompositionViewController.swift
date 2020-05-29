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
    
    private let composition = AVMutableComposition()
    
    private var bgAsset: AVAsset?
    
    private var fgAsset: AVAsset?
    
    private var playerLooper: AVPlayerLooper!
    
    private var playerLayer: AVPlayerLayer?
    
    @IBOutlet private weak var previewView: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let bgAsset = AVAsset(url: backgroundVideoUrl)
        bgAsset.prepare(properties: ["tracks", "duration"]) {
            self.bgAsset = bgAsset
            self.tracksLoaded()
        }
        
        let fgAsset = AVAsset(url: foregroundVideoUrl)
        fgAsset.prepare(properties: ["tracks", "duration"]) {
            self.fgAsset = fgAsset
            self.tracksLoaded()
        }
    }
    
    private func tracksLoaded() {
        guard let bgAsset = bgAsset, let fgAsset = fgAsset else {
            return
        }
        
        guard (bgAsset.duration.isNumeric && fgAsset.duration.isNumeric) else {
            return
        }
        
        print("AMKING COMP!")
        
        var timeRange = CMTimeRange()
        timeRange.start = .zero
        timeRange.duration =
            bgAsset.duration.seconds < fgAsset.duration.seconds ?
                bgAsset.duration : fgAsset.duration
        
        let compBgVideoTrack = composition.addMutableTrack(withMediaType: .video,
                                                           preferredTrackID: 1)!
        let assetBgVideoTrack = bgAsset.firstVideoTrack!
        compBgVideoTrack.preferredTransform = assetBgVideoTrack.preferredTransform
        let compBgAudioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                           preferredTrackID: 1)!
        let assetBgAudioTrack = bgAsset.firstAudioTrack!
        try! compBgVideoTrack.insertTimeRange(timeRange,
                                              of: assetBgVideoTrack,
                                              at: .zero)
        try! compBgAudioTrack.insertTimeRange(timeRange,
                                              of: assetBgAudioTrack,
                                              at: .zero)
        
        let compFgVideoTrack = composition.addMutableTrack(withMediaType: .video,
                                                           preferredTrackID: 2)!
        let assetFgVideoTrack = fgAsset.firstVideoTrack!
        compFgVideoTrack.preferredTransform = assetFgVideoTrack.preferredTransform
        let compFgAudioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                           preferredTrackID: 2)!
        let assetFgAudioTrack = fgAsset.firstAudioTrack!
        try! compFgVideoTrack.insertTimeRange(timeRange,
                                              of: assetFgVideoTrack,
                                              at: .zero)
        try! compFgAudioTrack.insertTimeRange(timeRange,
                                              of: assetFgAudioTrack,
                                              at: .zero)
        
        let playerItem = AVPlayerItem(asset: composition)
        let player = AVQueuePlayer(playerItem: playerItem)
        playerLayer = AVPlayerLayer(player: player)
        DispatchQueue.main.async {
            self.previewView.layer.addSublayer(self.playerLayer!)
        }
        playerLooper = AVPlayerLooper(player: player,
                                      templateItem: playerItem)
        
        player.play()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer?.frame = previewView.bounds
    }
    
}
