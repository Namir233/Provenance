//
//  NavigationViewController.swift
//  Provenance
//
//  Created by Rico Wang on 2021/8/16.
//  Copyright © 2021 Provenance Emu. All rights reserved.
//

import Foundation

class NavigationViewController : UINavigationController {
    override var shouldAutorotate: Bool {
        return topViewController?.shouldAutorotate ?? false
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return topViewController?.supportedInterfaceOrientations ?? .all
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return topViewController?.preferredInterfaceOrientationForPresentation ?? .portrait
    }
}
