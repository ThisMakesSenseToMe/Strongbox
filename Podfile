workspace 'StrongBox'

use_frameworks!

abstract_target 'common-mac' do
    project 'macbox/MacBox.xcodeproj'
    platform :osx, '10.15'
    
    pod 'libsodium'
    pod 'Down'

    target 'Mac-Freemium' do
      pod 'MSAL'
      pod 'MSGraphClientSDK'
      pod 'GoogleAPIClientForREST/Drive'
      pod 'GoogleSignIn'
      pod 'ObjectiveDropboxOfficial'
    end

    target 'Mac-Pro' do
        pod 'MSAL'
        pod 'MSGraphClientSDK'
        pod 'GoogleAPIClientForREST/Drive'
        pod 'GoogleSignIn'
        pod 'ObjectiveDropboxOfficial'
    end

    target 'Mac-Unified-Freemium' do
      pod 'MSAL'
      pod 'MSGraphClientSDK'
      pod 'GoogleAPIClientForREST/Drive'
      pod 'GoogleSignIn'
      pod 'ObjectiveDropboxOfficial'
    end

    target 'Mac-Unified-Pro' do
      pod 'MSAL'
      pod 'MSGraphClientSDK'
      pod 'GoogleAPIClientForREST/Drive'
      pod 'GoogleSignIn'
      pod 'ObjectiveDropboxOfficial'
    end

    target 'Mac-Graphene' do #TODO
      pod 'MSAL'
      pod 'MSGraphClientSDK'
      pod 'GoogleAPIClientForREST/Drive'
      pod 'GoogleSignIn'
      pod 'ObjectiveDropboxOfficial'
    end

    target 'Mac-Freemium-AutoFill' do
    end

    target 'Mac-Unified-Freemium-AutoFill' do
    end
    
    target 'Mac-Unified-Pro-AutoFill' do
    end

    target 'Mac-Pro-AutoFill' do
    end
    
    target 'Mac-Graphene-AutoFill' do
    end
end

abstract_target 'common-ios' do
    project 'Strongbox.xcodeproj'
    platform :ios, '14.0'

    pod 'libsodium'    
    pod 'Down'
   
    target 'Strongbox-iOS' do
        pod 'ISMessages'
        pod 'MTBBarcodeScanner'
        pod 'ObjectiveDropboxOfficial'
        pod 'GoogleAPIClientForREST/Drive'
        pod 'GoogleSignIn'
        pod 'MSAL'
        pod 'MSGraphClientSDK'
        pod 'SwiftMessages'
    end

    target 'Strongbox-iOS-Pro' do
        pod 'ISMessages'
        pod 'MTBBarcodeScanner'
        pod 'ObjectiveDropboxOfficial'
        pod 'GoogleAPIClientForREST/Drive'
        pod 'GoogleSignIn'
        pod 'MSAL'
        pod 'MSGraphClientSDK'
        pod 'SwiftMessages'
    end    

    target 'Strongbox-iOS-SCOTUS' do
        pod 'ISMessages'
        pod 'SwiftMessages'
    end    

    target 'Strongbox-iOS-Graphene' do
        pod 'MTBBarcodeScanner'
        pod 'ISMessages'
        pod 'SwiftMessages'
    end  

    target 'Strongbox-Auto-Fill' do

    end

    target 'Strongbox-Auto-Fill-Pro' do

    end

    target 'Strongbox-Auto-Fill-SCOTUS' do 

    end

    target 'Strongbox-Auto-Fill-Graphene' do 
    
    end
end

# XCode 14 issue...
# From: https://github.com/fastlane/fastlane/issues/20670
# Also: https://support.bitrise.io/hc/en-us/articles/4406551563409-CocoaPods-frameworks-signing-issue

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      if target.respond_to?(:product_type) and target.product_type == "com.apple.product-type.bundle"
        target.build_configurations.each do |config|
          config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
        end
      end
    end
  end
end

