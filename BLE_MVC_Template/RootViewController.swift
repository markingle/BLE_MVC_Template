//
//  ViewController.swift
//  BLE_MVC_Template
//
//  Created by Mark Brady Ingle on 3/19/22.
//

import UIKit

class RootViewController: UIViewController {

    var model: corkModel?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        if let ad = UIApplication.shared.delegate as? AppDelegate{
            self.model = ad.model
        }
    }


}

