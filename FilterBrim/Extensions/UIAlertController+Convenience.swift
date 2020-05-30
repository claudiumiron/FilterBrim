//
//  UIAlertController+Convenience.swift
//  FilterBrim
//
//  Created by Claudiu Miron on 30/05/2020.
//  Copyright © 2020 Apple. All rights reserved.
//

import UIKit

extension UIAlertController {
    static func simpleQuestionAlertWith(title: String,
                                        message: String,
                                        yesAction: @escaping () -> Void,
                                        noAction: @escaping () -> Void) -> UIAlertController {
        let alert = UIAlertController(title: title,
                                      message: message,
                                      preferredStyle: .alert)
        let yesAction = UIAlertAction(title: "Yes", style: .default) { (action) in
            yesAction()
        }
        let noAction = UIAlertAction(title: "No", style: .cancel) { (action) in
            noAction()
        }
        alert.addAction(noAction)
        alert.addAction(yesAction)
        return alert
    }
}
