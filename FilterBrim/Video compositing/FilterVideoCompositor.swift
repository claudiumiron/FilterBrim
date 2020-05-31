//
//  FilterVideoCompositor.swift
//  FilterBrim
//
//  Created by Claudiu Miron on 30/05/2020.
//  Copyright © 2020 Apple. All rights reserved.
//

import AVFoundation
import CoreImage
import CoreVideo
import Foundation

enum FilterVideoCompositorError: Error {
    case missingDestinationBuffer
    case missingBackBuffer
    case missingFrontBuffer
    case cannotCreateFormatDescription
}

extension FilterVideoCompositorError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingDestinationBuffer:
            return "Cannot retrieve destination pixel buffer"
            
        case .missingBackBuffer:
            return "Cannot retrieve background pixel buffer"
            
        case .missingFrontBuffer:
            return "Cannot retrieve foreground pixel buffer"

        case .cannotCreateFormatDescription:
            return "Cannot create pixel format description"
        }
    }
}

class FilterVideoCompositor: NSObject, AVVideoCompositing {
    
    private let filterRenderQueue = DispatchQueue(label: "FilterRender",
                                                  qos: .userInitiated,
                                                  attributes: [],
                                                  autoreleaseFrequency: .workItem)
    
    private var ciFilters: [Int : [CIFilter]] = [:]
    
    private var pipRenderer = PictureInPictureRenderer()
    
    var sourcePixelBufferAttributes: [String : Any]? {
        return  [kCVPixelBufferPixelFormatTypeKey as String : Int(kCVPixelFormatType_32BGRA)]
    }
    
    var requiredPixelBufferAttributesForRenderContext: [String : Any] {
        return  [kCVPixelBufferPixelFormatTypeKey as String : Int(kCVPixelFormatType_32BGRA)]
    }
    
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        
    }
    
    func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
        filterRenderQueue.async {
            autoreleasepool {
                let request = asyncVideoCompositionRequest
                
                guard var destination = request.renderContext.newPixelBuffer() else {
                    request.finish(with: FilterVideoCompositorError.missingDestinationBuffer)
                    return
                }
                
                var formatDescription: CMVideoFormatDescription? = nil
                CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil,
                                                             imageBuffer: destination,
                                                             formatDescriptionOut: &formatDescription)
                guard let formatDesc = formatDescription else {
                    request.finish(with: FilterVideoCompositorError.cannotCreateFormatDescription)
                    return
                }
                
                guard let backBuffer = request.sourceFrame(byTrackID: 2) else {
                    request.finish(with: FilterVideoCompositorError.missingBackBuffer)
                    return
                }
                
                guard let frontBuffer = request.sourceFrame(byTrackID: 1) else {
                    request.finish(with: FilterVideoCompositorError.missingBackBuffer)
                    return
                }
                
                if !self.pipRenderer.isPrepared {
                    self.pipRenderer.prepare(with: formatDesc)
                }
                
                var fgFilters: [CIFilter] = []
                if let filters = self.ciFilters[1] {
                    fgFilters = filters
                }
                var bgFilters: [CIFilter] = []
                if let filters = self.ciFilters[2] {
                    bgFilters = filters
                }
                
                self.pipRenderer.render(bgPixelBuffer: backBuffer,
                                        bgCIFilters: bgFilters,
                                        fgPixelBuffer: frontBuffer,
                                        fgCIFilters: fgFilters,
                                        in: &destination)
                
                request.finish(withComposedVideoFrame: destination)
            }
        }
    }
    
    func set(ciFilters: [CIFilter], forTrackId trackId: Int) {
        self.ciFilters[trackId] = ciFilters
    }
}
