//
//  CompositionViewController.swift
//  FilterBrim
//
//  Created by Claudiu Miron on 28/05/2020.
//  Copyright © 2020 Apple. All rights reserved.
//

import UIKit

class CompositionViewController: UIViewController {
    
    public var backgroundVideoUrl: URL!
    
    public var foregroundVideoUrl: URL!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        print("\n\(backgroundVideoUrl.path)\n\(foregroundVideoUrl.path)")
    }
    
}
