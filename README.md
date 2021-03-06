SharePictures
==============

About
--------------

[Ostetso](https://www.ostetso.com) is a *social network as a service* that allows you to easily integrate a full-featured photo sharing social network along with backend services into your iOS apps.  See [Ostetso.com](https://www.ostetso.com) for details.
**SharePictures** is a project used to demonstrate how to integrate the Ostetso framework into a photo sharing app.  SharePictures uses the [GPUImage SDK](https://github.com/BradLarson/GPUImage) to apply simple image filters to photos and, via Ostetso, to share them with other users and friends.

Instructions for building 
--------------

- Download the SharePictures project to your Mac.
- This project integrates GPUImage as a [CocoaPods](https://cocoapods.org/) project.  This is super easy to configure to use with SharePictures.  If you aren’t already using CocoaPods, from the command line run :
``` bash
	sudo gem install cocoapods
```
- Next you will need to download the GPUImage project.  This is very easy with CocoaPods.  In the terminal, navigate to the SharePictures source directory and run:
``` bash
	pod install
```
- Next you will have to make sure that you have an account with Ostetso so that you can get the information that is needed to use the Ostetso SDK.  First navigate to [Ostetso.com](https://www.ostetso.com) to sign up as a developer and to obtain the SDK.
- Once you have downloaded the Ostetso SDK and the SharePictures source code, unzip the Ostetso SDK and place both the Ostetso.framework and Ostetso.bundle files into the Ostetso directory within your SharePictures source directory.
- Follow the instructions at [Ostetso.com/sdk](https://www.ostetso.com/sdk) to add register a new app and obtain an API Key and App ID.
- Open up the **SharePictures.xcworkspace** file in Xcode.  **Note: do not use the xcodeproj file since it won’t work with CocoaPods.**
- Edit the file OstetsoConfig.h and replace the placeholder strings with your actual API Key and App ID that you were provided when you registered a new app with Ostetso.com.  
- Build, run and SHARE PICTURES!
- See [Ostetso Support](https://www.ostetso.com/support) if you need assistance or have questions.

