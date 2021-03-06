//
//  SPViewController
//  SharePictures
//
//  Copyright (c) 2015 Precipice Labs. All rights reserved.
//


#import <CoreMotion/CoreMotion.h>
#import <CoreImage/CoreImage.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <objc/message.h>
#import <ImageIO/ImageIO.h>

#import "SPViewController.h"
#import "SPAppDelegate.h"
#import "SPInfoDialogVC.h"
#import "SPEffectInfo.h"
#import "SPFilterView.h"
#import "Ostetso/Ostetso.h"



@implementation SPViewController

#pragma mark -
#pragma mark Initialization and teardown

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
    NSLog(@"Our didReceiveMemoryWarning method got called.");
}

#pragma mark - View lifecycle

- (void) loadView
{
    [super loadView];
    
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // Initialize ivars
    _isSavingImage = NO;
    _activityIndicator.color = [UIColor whiteColor];
    _panStatus = kPanStatusOff;
    _currentEffect = 0;
    
    // Set up gesture recognizers
    _swipeRightRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleGesture:)];
    _swipeRightRecognizer.direction  = UISwipeGestureRecognizerDirectionRight;
    _swipeRightRecognizer.delegate = self;
    [self.view addGestureRecognizer:_swipeRightRecognizer];
    
    _swipeLeftRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleGesture:)];
    _swipeLeftRecognizer.direction  = UISwipeGestureRecognizerDirectionLeft;
    _swipeLeftRecognizer.delegate = self;
    [self.view addGestureRecognizer:_swipeLeftRecognizer];

    // Configure the list of available effects from our .fx files
    [self buildEffectList];
    [self loadEffectChoicesButtons];
    
    // Alloc the camera/filter view
    _origFilterViewFrame = self.view.frame;
    _filterView = [[SPFilterView alloc] initWithFrame: _origFilterViewFrame];
    [self.view insertSubview:_filterView.view atIndex: 0];

    // Add our home button
    UIButton *homeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [homeButton setFrame:CGRectMake(0.0f, 0.0f, 35.0f, 35.0f)];
    [homeButton addTarget:self action:@selector(homeButtonSelected) forControlEvents:UIControlEventTouchUpInside];
    [homeButton setImage:[UIImage imageNamed:@"HomeButton"] forState:UIControlStateNormal];
    UIBarButtonItem *homeButtonItem = [[UIBarButtonItem alloc] initWithCustomView:homeButton];
    self.navigationItem.leftBarButtonItem = homeButtonItem;
    
    _toolbar.hidden = YES;
    
    // Core motion declaration for detecting accelerator rotation
    self.motionManager = [[CMMotionManager alloc] init];
    self.motionManager.accelerometerUpdateInterval = 1;
    
    // Monitor the motion of the device to keep track of the current device orientation
    if ([self.motionManager isAccelerometerAvailable])
    {
        NSOperationQueue *queue = [[NSOperationQueue alloc] init];
        
        [self.motionManager startAccelerometerUpdatesToQueue:queue withHandler:^(CMAccelerometerData *accelerometerData, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                
                float xx = -accelerometerData.acceleration.x;
                float yy = accelerometerData.acceleration.y;
                float angle = atan2(yy, xx);
                
                // could fire a custom shouldAutorotateToInterfaceOrientation-event here.
                if(angle >= -2.25 && angle <= -0.75)
                {
                    if(_deviceOrientation != UIInterfaceOrientationPortrait)
                    {
                        _deviceOrientation = UIInterfaceOrientationPortrait;
                    }
                }
                else if(angle >= -0.75 && angle <= 0.75)
                {
                    if(_deviceOrientation != UIInterfaceOrientationLandscapeRight)
                    {
                        _deviceOrientation = UIInterfaceOrientationLandscapeRight;
                    }
                }
                else if(angle >= 0.75 && angle <= 2.25)
                {
                    if(_deviceOrientation != UIInterfaceOrientationPortraitUpsideDown)
                    {
                        _deviceOrientation = UIInterfaceOrientationPortraitUpsideDown;
                    }
                }
                else if(angle <= -2.25 || angle >= 2.25)
                {
                    if(_deviceOrientation != UIInterfaceOrientationLandscapeLeft)
                    {
                        _deviceOrientation = UIInterfaceOrientationLandscapeLeft;
                    }
                }
            });
        }];
    }
    else
    {
        NSLog(@"Acceleraometer not available");
    }
    
}

- (void) viewDidAppear:(BOOL)animated
{
    // To avoid the still image popping into view, do a quick dissolve to make it visible
    if (NO == self.imageSourceCamera)
    {
        _previewImageView.alpha = 0.f;
        [_previewImageView setHidden:NO];

        [_stillImagePicture processImage];

        [UIView animateWithDuration:.3f delay:0.f options:UIViewAnimationOptionCurveEaseInOut animations:
         ^{
             _previewImageView.alpha = 1.f;
         }
         completion: nil];
    }
}


- (void) viewWillAppear:(BOOL)animated
{
    self.navigationController.navigationBarHidden=NO;
    _origFilterViewFrame = self.view.frame;
    _filterView.view.frame = _origFilterViewFrame;
    
    // Position the effect amount slider
    CGAffineTransform trans = CGAffineTransformMakeRotation(-M_PI * 0.5);
    _effectAmountSlider.transform = trans;
    CGRect sliderFrame = _effectAmountSlider.frame;
    sliderFrame.origin.x = self.view.frame.size.width - sliderFrame.size.width - 5;
    sliderFrame.origin.y = _toolbar.frame.origin.y - _effectSelectionView.frame.size.height - sliderFrame.size.height - 10.f;
    _effectAmountSlider.frame = sliderFrame;
    
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    NSString *currEffect = [prefs objectForKey: @"currentEffect"];
    
    _currentEffect = nil;   // Set to nil to force setCurrentEffect to go through full initialization
    
    BOOL isIPad = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);

    // Check to differentiate between nativeGallery image and live camera mode
    if (self.imageSourceCamera)
    {
        [_previewImageView setHidden:YES];
        [self setupCamera];
        [self setCurrentEffect: currEffect ? currEffect : @"Sketch" forFilterView: _filterView];
    }
    else   // Processing an image from the camera roll
    {
        [_previewImageView setHidden:YES];
        _reloadImage=NO;
        _backGroundFilter=[[SPFilterView alloc]init];
        
        if (_selectedImage.size.height<_selectedImage.size.width)
        {
            
            [_previewImageView layoutSubviews];
            [_previewImageView setFillMode:kGPUImageFillModePreserveAspectRatio];
            
            [_previewImageView setContentMode:UIViewContentModeScaleAspectFit];
            _previewImageView.center=self.view.center;
            if (isIPad)
            {
                [_previewImageView setFrame:CGRectMake(0, 245, self.view.frame.size.width,550)];
            }
            else
            {
                [_previewImageView setFrame:CGRectMake(0, 115,self.view.frame.size.width,245)];
            }
        }
        else
        {
            if (isIPad)
            {
                [_previewImageView setFrame:CGRectMake(0, 0, self.view.frame.size.width, 550)];
            }
            [_previewImageView layoutSubviews];
            [_previewImageView setFillMode:kGPUImageFillModePreserveAspectRatioAndFill];
        }
        
        _selectedImage=[self fixRotation:_selectedImage];
        
        _stillImagePicture=[[GPUImagePicture alloc]initWithImage:_selectedImage];
        
        SPEffectInfo *effect = [_effectList objectForKey: _currentEffect];
        _toolbar.hidden = YES;

        _effectSelectionView.hidden = NO;
        _cameraButton.hidden = NO;
        [_cameraButton setImage:[UIImage imageNamed:@"ShareShutter"] forState:UIControlStateNormal];
        [_cameraButton removeTarget:self action:@selector(captureImage:) forControlEvents:UIControlEventTouchUpInside];
        [_cameraButton addTarget:self action:@selector(shareImage:) forControlEvents:UIControlEventTouchUpInside];
        [self showOSCsForEffect: effect];
        [_camera resumeCameraCapture];
        [_filterView.view setHidden:YES];
        [self.view setBackgroundColor:[UIColor blackColor]];
        [self setCurrentEffect: currEffect ? currEffect : @"Sketch" forFilterView:_filterView];
    }
    
    
    UINavigationController *nav = [self navigationController];
    if (!nav)
    {
        NSLog(@"no nav");
        return;
    }
    
    UIButton *gallryButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [gallryButton setFrame:CGRectMake(0.0f, 0.0f, 35.0f, 35.0f)];
    [gallryButton addTarget:self action:@selector(showGalleryButtonPressed) forControlEvents:UIControlEventTouchUpInside];
    [gallryButton setImage:[UIImage imageNamed:@"ViewGalleryIcon.png"] forState:UIControlStateNormal];
    UIBarButtonItem *galleryButtonItem = [[UIBarButtonItem alloc] initWithCustomView:gallryButton];
    self.navigationItem.rightBarButtonItem = galleryButtonItem;

}

- (void)viewWillDisappear:(BOOL)animated
{
    // Stop camera capture before the view went off the screen in order to prevent a crash from the camera still sending frames
    [_camera stopCameraCapture];
    
    [super viewWillDisappear:animated];
}


- (void)viewWillUnload
{
    [super viewWillUnload];
}


- (void)viewDidUnload
{
    _previewImageView=nil;
    _capturedImageView = nil;
    
    _resetButton = nil;
    _toolbar = nil;
    _cameraButton = nil;
    _shareButton = nil;
    _switchCameraButton = nil;
    
    _activityIndicator = nil;

    _effectChoiceView = nil;
    _effectSelectionView = nil;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super viewDidUnload];
    _effectAmountSlider = nil;

    
}

// Configure the buttons for effect selection
- (void) loadEffectChoicesButtons
{
    const int buttonSep = 5;

    int barHt = 40;
    int idx = 0;
    int lastX = 0;
    CGRect imageButtonFrame;
    const int btnOffset = 10;

    // Loop through all of the effect files that we loaded
    for (NSString *key in _sortedEffectTitles)
    {
        SPEffectInfo *effect = [_effectList objectForKey: key];
        UIButton *effectButton;
        
        BOOL haveIconFile = NO;
        
        // Create the button for the effect
        NSString *iconImageFile = [effect getIconImageFile];
        if (iconImageFile)
        {
            NSString *fxImagePath = [SPEffectInfo getEffectsImagePath];
            
            NSString *iconPath = [fxImagePath stringByAppendingPathComponent: iconImageFile];
            UIImage *btnImage = [UIImage imageWithContentsOfFile: iconPath];
            
            if (btnImage.size.width < 81 && btnImage.size.height < 76)
            {
                effectButton = [UIButton buttonWithType: UIButtonTypeCustom];
                CGRect frame = CGRectMake(lastX, btnOffset, 100, 40);
                CGRect buttonFrame = frame;
                buttonFrame.size = btnImage.size;
                effectButton.frame = buttonFrame;
                
                barHt = fmaxf(barHt, btnImage.size.height+btnOffset);
                
                [effectButton setImage:btnImage forState:UIControlStateNormal];
                
                if ([effect getIconSelectedImageFile])
                {
                    NSString *seliconPath = [fxImagePath stringByAppendingPathComponent: [effect getIconSelectedImageFile]];
                    UIImage *selbtnImage = [UIImage imageWithContentsOfFile: seliconPath];
                    [effectButton setImage:selbtnImage forState:UIControlStateSelected];
                }
                
                haveIconFile = YES;
                lastX += btnImage.size.width + buttonSep;
                
                imageButtonFrame = buttonFrame;
                
            }
        }
        
        if (NO == haveIconFile)
        {
            effectButton = [UIButton buttonWithType: UIButtonTypeRoundedRect];
            CGRect frame = CGRectMake(lastX, 0, 100, 40);
            effectButton.frame = frame;
            
            lastX += 100 + buttonSep;
        }
        
        [effectButton setTitle: [effect getEffectName] forState: UIControlStateNormal];
        
        [effectButton addTarget: self
                         action: @selector(newEffectSelected:)
               forControlEvents: UIControlEventTouchUpInside];
        
        [_effectChoiceView addSubview: effectButton];
        
        idx++;
    }
    
    imageButtonFrame.size.height = barHt;
    
    CGRect frame;
    
    // Set the frame for the main container for effects buttons
    frame = _effectSelectionView.frame;
    frame.origin.x = 0;
    frame.size.height = barHt;
    frame.origin.y = self.view.frame.size.height - frame.size.height;
    _effectSelectionView.frame = frame;
    
    // Set the frame for the scrolled list of effects buttons
    frame = _effectChoiceView.frame;
    frame.origin.y = 0;
    frame.size.height = imageButtonFrame.size.height;
    _effectChoiceView.frame = frame;
    _effectChoiceView.contentSize = CGSizeMake(lastX, imageButtonFrame.size.height);
    
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
{
}

#pragma mark User Interface

// Hide all of the camera onscreen controls
- (void) hideOSCs
{
    _effectAmountSlider.hidden = YES;
    _switchCameraButton.hidden = YES;
    _flashToggleButton.hidden = YES;
    
}

// Show the onscreen controls appropriate for the given effect
- (void) showOSCsForEffect: (SPEffectInfo *) effect
{
    if (_capturedImageView.hidden == NO) return;    // don't mess with the camera state if we're previewing a captured image
    
    _cameraButton.enabled = YES;
    
    _effectAmountSlider.hidden = [effect hasAmountSlider] ? NO : YES;
    
    if (YES == _camera.frontFacingCameraPresent)
    {
        _switchCameraButton.hidden = NO;
        if(_camera.cameraPosition == AVCaptureDevicePositionBack)
        {
            _flashToggleButton.hidden = NO;
        }
    }
    else
    {
        _switchCameraButton.hidden = YES;
        _flashToggleButton.hidden = YES;
    }
}

- (void) setActivityIndicatorAnimatingPerDeviceAge: (BOOL) animating
{
    if (NO == _oldDeviceModel) return;
    
    [self setActivityIndicatorAnimating: animating];
}

- (void) setActivityIndicatorAnimating: (BOOL) animating
{
    BOOL buttonActive = !animating;
    
    _shareButton.enabled = buttonActive;
    _resetButton.enabled = buttonActive;
    _cameraButton.enabled = buttonActive;
    _effectAmountSlider.enabled = buttonActive;
    
    if (animating)
    {
        [_activityIndicator startAnimating];
    }
    else
    {
        [_activityIndicator stopAnimating];
    }
}


// Are we in a state where it's ok to change the current effect?
- (BOOL) canSwitchEffect
{
    return (_panStatus == kPanStatusOff);
}



#pragma mark gesture handling

// Allow the user to swipe left/right to change the current effect
- (BOOL) initiateEffectPan: (CGPoint) pan
{
    BOOL panInFromLeft = NO;
    
    BOOL found = NO;
    NSString *newEffect = nil;
    
    // Find the effect that is before or after the currently selected one, depending on which way we are panning
    for (NSString *key in _sortedEffectTitles)
    {
        if (found)
        {
            newEffect = key;
            break;
        }
        else if ([_currentEffect isEqualToString: key])
        {
            found = YES;
            if (pan.x > 0.f)
            {
                panInFromLeft = YES;
                break;
            }
            else
            {
                newEffect = nil;
            }
        }
        else
        {
            newEffect = key;
        }
    }
    
    if (newEffect)
    {
        _tempFilterView = [self allocNewFilterViewForEffect: newEffect leftOfScreen: panInFromLeft];
        _origFilterViewFrame = _filterView.view.frame;
        _origTempViewFrame = _tempFilterView.view.frame;
        
        _panStatus = panInFromLeft ? kPanStatusLeft : kPanStatusRight;
        
        return YES;
    }
    
    return NO;
    
}

- (void) completePan: (BOOL) switchToNew
{
    
    if (switchToNew)
    {
        [_filterView.view removeFromSuperview];
        [_camera removeTarget:_filterView.filter];
        _filterView = _tempFilterView;
        
    }
    else
    {
        [_tempFilterView.view removeFromSuperview];
        [_camera removeTarget:_tempFilterView.filter];
    }
    
    [self makeFilterViewCurrentForFilterView: _filterView];
    
    _filterView.view.frame = _origFilterViewFrame;
    
    _tempFilterView = nil;
}

- (void) finishEffectPan: (BOOL) switchToNew  panPos:(CGPoint) panPos panVelocity: (float) panVelocity
{
    static bool changeInProg = NO;
    if (changeInProg) return;
    changeInProg = YES;
    
    CGRect newFrame = _origTempViewFrame;
    newFrame.origin.x *= -1.f;
    
    [UIView animateWithDuration:.3f delay:0.1f options:UIViewAnimationOptionCurveEaseOut animations:
     ^{
         if (switchToNew)
         {
             _tempFilterView.view.frame = _origFilterViewFrame;
             _filterView.view.frame = newFrame;
         }
         else
         {
             _tempFilterView.view.frame = _origTempViewFrame;
             _filterView.view.frame = _origFilterViewFrame;
         }
     }
                     completion:^(BOOL finished)
     {
         [self completePan: switchToNew];
         changeInProg = NO;
         _panStatus = kPanStatusOff;
         [self setActivityIndicatorAnimatingPerDeviceAge: NO];
     }];
    
}

- (void) panEffect: (UISwipeGestureRecognizer *) swipeRecognizer
{
    
    CGPoint pan;
    
    if (swipeRecognizer.direction & UISwipeGestureRecognizerDirectionLeft)
    {
        pan.x = -1.;
        pan.y = 0.;
    }
    if (swipeRecognizer.direction & UISwipeGestureRecognizerDirectionRight)
    {
        pan.x = 1.;
        pan.y = 0.;
    }
    
    if ([self initiateEffectPan: pan])
    {
        [self finishEffectPan:YES
                       panPos:pan panVelocity:0.2];
    }
    else
    {
        [self setActivityIndicatorAnimatingPerDeviceAge: NO];
    }
    
}


- (void)handleGesture:(UIGestureRecognizer*)gestureRecognizer
{
    if (gestureRecognizer == _swipeRightRecognizer || gestureRecognizer == _swipeLeftRecognizer)
    {
        UISwipeGestureRecognizer *swipeRecognizer = (UISwipeGestureRecognizer *)gestureRecognizer;
        [self setActivityIndicatorAnimatingPerDeviceAge: YES];
        [self performSelector:@selector(panEffect:) withObject:swipeRecognizer afterDelay:.01];
    }
}

// For the pan effect, we need a new view that will get panned into view.  Set it up here.
- (SPFilterView *) allocNewFilterViewForEffect : (NSString *) effectName leftOfScreen: (BOOL) leftOfScreen
{
    if (_currentEffect && [_currentEffect isEqualToString: effectName])
    {
        return nil;
    }
    
    CGRect viewRect = _filterView.view.frame;
    viewRect.origin.x = leftOfScreen ? -viewRect.size.width : viewRect.size.width;
    
    SPFilterView *tempFilterView;
    tempFilterView = [[SPFilterView alloc] initWithFrame: viewRect];
    [self.view insertSubview:tempFilterView.view atIndex: 1];
    
    [self setEffect: effectName forFilterView: tempFilterView];
    
    [self setFilterAmount: [tempFilterView.effect amountSliderDefault] forFilterView: tempFilterView];
    
    return tempFilterView;
}


#pragma mark device configuration

- (BOOL)shouldAutorotate
{
    return NO;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}

- (BOOL) hasFrontCamera
{
    BOOL hasFrontCamera = NO;
    
    NSArray *devices = [AVCaptureDevice devicesWithMediaType: AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices)
    {
        if ([device position] == AVCaptureDevicePositionFront)
        {
            hasFrontCamera = YES;
            break;
        }
    }
    
    return hasFrontCamera;
}

#pragma mark effect list

NSInteger finderSortWithLocale(id string1, id string2, void *locale)
{
    static NSStringCompareOptions comparisonOptions = NSCaseInsensitiveSearch | NSNumericSearch |
    NSWidthInsensitiveSearch | NSForcedOrderingSearch;
    
    NSRange string1Range = NSMakeRange(0, [string1 length]);
    
    return [string1 compare:string2
                    options:comparisonOptions
                      range:string1Range
                     locale:(__bridge NSLocale *)locale];
}

- (void) buildEffectList
{
    if (_effectList) return;
    
    NSError * error;
    NSString * fxPath = [SPEffectInfo getEffectsImagePath];
    
    NSArray * directoryContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:fxPath error:&error];
    
    NSArray *sortedDirectoryContents = [directoryContents sortedArrayUsingFunction:finderSortWithLocale
                                                                           context:(__bridge void *)([NSLocale currentLocale])];
    
    _effectList = [[NSMutableDictionary alloc] init];
    _sortedEffectTitles = [[NSMutableArray alloc] init];
    
    for (NSString *file in sortedDirectoryContents)
    {
        NSString *ext = [file pathExtension];
        if ([ext isEqualToString: @"fx"])    // Got an effect description file
        {
            NSString *fxpath = [fxPath stringByAppendingPathComponent: file];
            NSString *fxFile = [NSString stringWithContentsOfFile:fxpath encoding:NSASCIIStringEncoding error: &error];
            if (nil == fxFile)
            {
                NSLog(@"Error reading Fx File %@ : %@", fxpath, error);
                continue;
            }
            
            NSDictionary *fxInfo = [fxFile propertyListFromStringsFileFormat];
            
            NSString *name = [fxInfo objectForKey: @"effectName"];
            if (name)
            {
                SPEffectInfo *effect = [_effectList objectForKey: name];
                
                if (nil == effect)
                {
                    effect = [[SPEffectInfo alloc] initWithFxInfo: fxInfo];
                    
#ifndef DEBUG
                    // Only add the bevel effect for debug builds, just for developers!
                    if ([[effect getEffectName] isEqualToString:@"Bevel"] ||
                        [[effect getEffectName] isEqualToString:@"Bevel Selected"])
                    {
                        continue;
                    }
#endif
                    [_effectList setObject:effect forKey: name];
                    [_sortedEffectTitles addObject: name];
                }
            }
        }
    }
}

- (UIButton *)effectButtonForTitle: (NSString *) effectTitle
{
    NSArray *subviews = [_effectChoiceView subviews];
    
    for (UIView *view in subviews)
    {
        if ([view isKindOfClass: [UIButton class] ])
        {
            UIButton *button = (UIButton *)view;
            
            if ([[button titleForState: UIControlStateNormal] isEqualToString: _currentEffect])
            {
                return button;
            }
        }
    }
    
    return nil;
}

- (void) setEffect : (NSString *)currentEffectName
      forFilterView: (SPFilterView *) filterView
{
    filterView.effect = [_effectList objectForKey: currentEffectName];
    
    NSString *effectClassname = [filterView.effect getEffectClassName];
    if (nil == effectClassname)
    {
        effectClassname = @"GPUImageSketchFilter";
    }
    
    filterView.filter = [[NSClassFromString(effectClassname) alloc] init];
    
    // Applied check, if its liveCamera Mode or image from nativeGallery
    if (NO == self.imageSourceCamera)
    {
        [_filterView.view setHidden:YES];
        _backGroundFilter=filterView;
        [self.view setBackgroundColor:[UIColor blackColor]];
    }
    else
    {
        [self setupFilterForView:filterView forEffect: currentEffectName];
    }
    
    _foregroundPicture = nil;
    NSString *foregroundImageFile = [filterView.effect getForegroundImageFile];
    if (foregroundImageFile)
    {
        NSString *fxImagePath = [SPEffectInfo getEffectsImagePath];
        NSString *imagePath = [fxImagePath stringByAppendingPathComponent: foregroundImageFile];
        UIImage *inputImage = [UIImage imageNamed:imagePath];
        _foregroundPicture = [[GPUImagePicture alloc] initWithImage:inputImage smoothlyScaleOutput:YES];
        [_foregroundPicture processImage];
        [_foregroundPicture addTarget:filterView.filter atTextureLocation: 1];
    }
    
}

// A new effect was selected, handle the UI setup for it
- (void) makeFilterViewCurrentForFilterView: (SPFilterView *) filterView
{
    NSString *currentEffectName = [filterView.effect getEffectName];
    
    // Don't do anything if we're not changing the effect
    if (_currentEffect && [_currentEffect isEqualToString: currentEffectName])
    {
        return;
    }
    
    // Deselect the previous effect button
    if (_currentEffect)
    {
        UIButton *oldbutton = [self effectButtonForTitle: _currentEffect];
        if (oldbutton) oldbutton.selected = NO;
    }
    
    _currentEffect = currentEffectName;
    
    // Select the new effect button and scroll it into view
    if (_currentEffect)
    {
        UIButton *newbutton = [self effectButtonForTitle: _currentEffect];
        if (newbutton)
        {
            newbutton.selected = YES;
            CGRect btnFrame = newbutton.frame;
            [_effectChoiceView scrollRectToVisible:(CGRect)btnFrame animated: YES];
        }
        
        // Save the newly selected effect to the user preferences
        NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
        [prefs setObject: _currentEffect forKey: @"currentEffect"];
        [prefs synchronize];
    }
    
    SPEffectInfo *effect = [_effectList objectForKey: _currentEffect];
    UINavigationController *nav = [self navigationController];

    // Set the effect title in the navigation bar
    NSString *navTitle;
    navTitle = [effect getEffectName];
    nav.navigationBar.topItem.title = navTitle;
    
    // Show the available controls that apply to the new effect
    [self showOSCsForEffect: effect];
    
    // Initialize the slider values for the effect if applicable
    if ([effect hasAmountSlider])
    {
        _effectAmountSlider.value = [effect amountSliderDefault];
        _effectAmountSlider.maximumValue = [effect amountSliderMax];
        _effectAmountSlider.minimumValue = [effect amountSliderMin];
    }
}


// A new effect was selected, get it going
- (void) setCurrentEffect : (NSString *)currentEffectName
             forFilterView: (SPFilterView *)filterView
{
    // Nothing changed, abort!
    if (_currentEffect && [_currentEffect isEqualToString: currentEffectName])
    {
        return;
    }
    
    // pause the camera
    [_camera stopCameraCapture];
    
    // change the effect
    [self setEffect: currentEffectName forFilterView: filterView];
    [self makeFilterViewCurrentForFilterView: filterView];
    
    // set the amount value for the effect to its default
    [self setFilterAmount: [filterView.effect amountSliderDefault] forFilterView: filterView];
    
    // Filtering from the camera roll, hide the filterView
    if (NO == self.imageSourceCamera)
    {
        [_filterView.view setHidden:YES];
        [self.view setBackgroundColor:[UIColor blackColor]];
    }
    
    // Start processing frames again
    [_camera startCameraCapture];
}



// Determine if effectName occurs before _currentEffect in the sorted effect list
- (BOOL) effectIsBeforeCurrent: (NSString *) effectName
{
    for (NSString *key in _sortedEffectTitles)
    {
        if ([_currentEffect isEqualToString: key])
        {
            return NO;
        }
        else if ([effectName isEqualToString: key])
        {
            return YES;
        }
    }
    
    return NO;
}

// Animate a new effect selection into view
- (void) animateNewEffectSelection : (NSString *) effectName
{
    if (_currentEffect && [_currentEffect isEqualToString: effectName])
    {
        return;
    }
    
    static bool changeInProg = NO;
    if (changeInProg) return;
    changeInProg = YES;
    
    CGRect viewRect = _filterView.view.frame;
    BOOL effectIsBeforeCurrent = [self effectIsBeforeCurrent: effectName];
    viewRect.origin.x = effectIsBeforeCurrent ? -viewRect.size.width : viewRect.size.width;
    CGRect newViewRect = _filterView.view.frame;
    newViewRect.origin.x = effectIsBeforeCurrent ? viewRect.size.width : -viewRect.size.width;
    
    // Create a new SPFilterView for the new effect that will get panned into view
    __block SPFilterView *tempFilterView;
    tempFilterView = [[SPFilterView alloc] initWithFrame: viewRect];
    [self.view insertSubview:tempFilterView.view atIndex: 1];
    
    [self setCurrentEffect: effectName forFilterView: tempFilterView];
    
    // Perform the animation
    [UIView animateWithDuration:0.3f delay:0.f options:UIViewAnimationOptionCurveEaseInOut animations:
     ^{
         tempFilterView.view.frame = _filterView.view.frame;
         _filterView.view.frame = newViewRect;
     }
                     completion:^(BOOL finished)
     {
         [_filterView.view removeFromSuperview];
         [_camera removeTarget:_filterView.filter];
         _filterView = tempFilterView;
         tempFilterView = nil;
         changeInProg = NO;
         
         [self setActivityIndicatorAnimatingPerDeviceAge: NO];
     }];
    
}

// Make a newly selected effect current
- (void) setEffect: (NSString *) newEffectName
{
    [self animateNewEffectSelection: newEffectName];
}

// One of the effect buttons was selected
- (void) newEffectSelected : (id) item
{
    if (NO == [self canSwitchEffect])
    {
        return;
    }
    
    UIButton *button = (UIButton *) item;
    NSString *newEffectName = [button titleForState: UIControlStateNormal];
    
    if (_currentEffect && [_currentEffect isEqualToString: newEffectName])
    {
        return;
    }
    
    [self setActivityIndicatorAnimatingPerDeviceAge: YES];
    [self performSelector:@selector(setEffect:) withObject:newEffectName afterDelay:.01];
}


#pragma mark GPUImage stuff

// Configure the camera
- (void)setupCamera
{
    NSString *captureSessionPreset;
    captureSessionPreset = AVCaptureSessionPresetPhoto;
    
    _camera = [[GPUImageStillCamera alloc] initWithSessionPreset: captureSessionPreset
                                                  cameraPosition: [self hasFrontCamera] ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack];
    _camera.horizontallyMirrorFrontFacingCamera = YES;
    
    _camera.outputImageOrientation = UIInterfaceOrientationPortrait;
    _camera.delegate = self;
    
    self.title = @"Mask";
    
    [_camera startCameraCapture];
}


- (void)setupFilterForView: (SPFilterView *) filterview forEffect:(NSString *)effectName
{
    [_camera addTarget: filterview.filter];
    
    // _camera.runBenchmark = YES;   // For debugging frame rate
    filterview.view.fillMode = kGPUImageFillModePreserveAspectRatioAndFill;
    
    [filterview.filter addTarget:filterview.view];
}



// Toggle the camera capture state
- (void) setCameraCaptureState: (BOOL) cameraActive
{
    if (_capturedImageView.hidden == NO) return;    // don't mess with the camera state if we're previewing a captured image
    if (_isSavingImage == YES) return;              // don't mess with the camera state if we're in the process of saving.  This can happen when the OS prompts for camera roll permissions on first run
    
    [self hideOSCs];
    
    SPEffectInfo *effect = [_effectList objectForKey: _currentEffect];
    
    if (cameraActive)
    {
        _toolbar.hidden = YES;
        _effectSelectionView.hidden = NO;
        _cameraButton.hidden = NO;
        [self showOSCsForEffect: effect];
        [_camera resumeCameraCapture];
    }
    
    else
    {
        _toolbar.hidden = NO;
        _effectSelectionView.hidden = YES;
        _cameraButton.hidden = YES;
        [_camera pauseCameraCapture];
    }
}

// Change the amount value for the effect (user adjusted the slider perhaps)
- (void) setFilterAmount: (CGFloat) amount forFilterView: (SPFilterView *)filterView
{
    NSString *amountMethodName = [filterView.effect getAmountMethodName];
    if (amountMethodName)
    {
        void (*setAmt)(id, SEL, CGFloat) = (void (*)(id, SEL, CGFloat)) objc_msgSend;
        setAmt(filterView.filter, NSSelectorFromString(amountMethodName), amount);
        
    }
    
    // If we're processing a still image, apply the new effect amount to the still
    if (NO == self.imageSourceCamera)
    {
        [_filterView.view setHidden:YES];
        // Checking if we need to reload image on _previewImageView or not
        if (_reloadImage==YES)
        {
            _stillImagePicture=[[GPUImagePicture alloc]initWithImage:_selectedImage];
        }
        [filterView.filter forceProcessingAtSizeRespectingAspectRatio:CGSizeMake(_previewImageView.sizeInPixels.width,_previewImageView.sizeInPixels.height)];
        [_stillImagePicture addTarget:filterView.filter];
        [filterView.filter addTarget:_previewImageView];
        [_stillImagePicture processImage];
        
        if (_foregroundPicture)
        {
            [_foregroundPicture processImage];
            [_foregroundPicture addTarget:filterView.filter atTextureLocation: 1];
        }
        
        _reloadImage=NO;
    }
}

#pragma mark Image Saving

// Save the image to the camera roll
- (void) saveToAlbum: (NSData *)imageData
{
    // Variable for EXIF rotation tag
    int rotationNumber;

    if (_deviceOrientation == UIInterfaceOrientationLandscapeRight)
    {
        rotationNumber=8;
    }
    else if (_deviceOrientation == UIInterfaceOrientationLandscapeLeft)
    {
        rotationNumber=6;
    }
    else
    {
        rotationNumber=1;
    }
    
    [self setCameraCaptureState: NO];
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    _isSavingImage = YES;
    
    _image = [[UIImage alloc] initWithData:imageData];
    // Checking if the deviceOrientation is in portrait mode
    if ([[UIDevice currentDevice]orientation] == UIDeviceOrientationPortrait)
    {
        NSMutableDictionary *tiffMetadata = [[NSMutableDictionary alloc] init];
        [tiffMetadata setObject:[NSNumber numberWithInt:rotationNumber ]forKey:(NSString*)kCGImagePropertyTIFFOrientation];
        NSMutableDictionary *metadata = [[NSMutableDictionary alloc] init];
        [metadata setObject:tiffMetadata forKey:(NSString*)kCGImagePropertyTIFFDictionary];
        
        // Correcting rotation of image with EXIF tag
        _image=[self fixRotation:_image];
        // Method to save image to photosAlbum with image rotation
        [library writeImageToSavedPhotosAlbum:[_image CGImage] metadata:tiffMetadata completionBlock:^(NSURL *assetURL, NSError *error2) {
            
            if (error2)
            {
                NSLog(@"ERROR: the image failed to be written");
                
                NSString *saveFail;
                
                if (error2.code == ALAssetsLibraryAccessUserDeniedError)
                {
                    saveFail = NSLocalizedString(@"ImageSavePermissionsFail", @"ImageSavePermissionsFail");
                }
                else
                {
                    saveFail = NSLocalizedString(@"ImageSaveFail", @"ImageSaveFail");
                }
                
                //Pop up a notification
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                                message:saveFail
                                                               delegate:nil
                                                      cancelButtonTitle:@"OK"
                                                      otherButtonTitles:nil];
                [alert show];
                
            }
            
            _isSavingImage = NO;
            _capturedImageView.backgroundColor=[UIColor clearColor];
            
            _capturedImageView.hidden = NO;
            _capturedImageView.userInteractionEnabled = YES;
            
            [self setActivityIndicatorAnimating: NO];
            
            runOnMainQueueWithoutDeadlocking(^{
            });
        }];
    }
    else
    {
        _image=[self fixRotation:_image];
        [library writeImageToSavedPhotosAlbum:[_image CGImage] metadata:nil completionBlock:^(NSURL *assetURL, NSError *error2)
         {
             if (error2)
             {
                 NSLog(@"ERROR: the image failed to be written");
                 
                 NSString *saveFail;
                 
                 if (error2.code == ALAssetsLibraryAccessUserDeniedError)
                 {
                     saveFail = NSLocalizedString(@"ImageSavePermissionsFail", @"ImageSavePermissionsFail");
                 }
                 else
                 {
                     saveFail = NSLocalizedString(@"ImageSaveFail", @"ImageSaveFail");
                 }
                 
                 //Pop up a notification
                 UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                                 message:saveFail
                                                                delegate:nil
                                                       cancelButtonTitle:@"OK"
                                                       otherButtonTitles:nil];
                 [alert show];
                 
             }
             
             _isSavingImage = NO;
             _capturedImageView.backgroundColor=[UIColor clearColor];
             
             _capturedImageView.hidden = NO;
             _capturedImageView.userInteractionEnabled = YES;
             [self setActivityIndicatorAnimating: NO];
             
             runOnMainQueueWithoutDeadlocking(^{ });
         }];
    }
}

- (void) saveImage
{
    [self setActivityIndicatorAnimating:YES];
    
    // Check if the effect requested to be saved as PNG (perhaps we'd like to preserve alpha channel)
    if ([_filterView.effect saveAsPng])
    {
        [_camera capturePhotoAsPNGProcessedUpToFilter:_filterView.filter withCompletionHandler:^(NSData *processedPNG, NSError *error)
         {
             [self saveToAlbum: processedPNG] ;
         }];
    }
    else
    {
        [_camera capturePhotoAsJPEGProcessedUpToFilter:_filterView.filter withCompletionHandler:^(NSData *processedJPEG, NSError *error)
         {
             [self saveToAlbum: processedJPEG];
         }];
    }
}

- (void)willOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
}



#pragma mark Actions

// Home button was selected
- (void)homeButtonSelected
{
    [self.navigationController popViewControllerAnimated:YES];
}

// Save image button selected
- (IBAction)captureImage:(id)sender
{
    [self saveImage];
}

// Toggle camera front/back button selected
- (IBAction)switchCamera:(id)sender
{
    [_camera stopCameraCapture];
    [_camera rotateCamera];
    if(_camera.cameraPosition == AVCaptureDevicePositionBack)
    {
        _flashToggleButton.hidden = NO;
    }
    else
    {
        _flashToggleButton.hidden = YES;
    }
    
    [_camera startCameraCapture];
}

// Toggle flash on/off button selected
- (IBAction)toggleFlash:(id)sender
{
    NSError *error = nil;
    if (![_camera.inputCamera lockForConfiguration:&error])
    {
        NSLog(@"Error locking for configuration: %@", error);
        return;
    }
    
    if(_camera.inputCamera.torchMode == AVCaptureTorchModeOff)
    {
        [_camera.inputCamera setTorchMode:AVCaptureTorchModeOn];
    }
    else
    {
        [_camera.inputCamera setTorchMode:AVCaptureTorchModeOff];
    }
    
    [_camera.inputCamera unlockForConfiguration];
    
}

// Reset button selected.  Go from viewing a captured image back to the live camera feed
- (IBAction)reset:(id)sender
{
    _image = nil;
    _capturedImageView.hidden = YES;
    _capturedImageView.image = nil;
    
    [self setCameraCaptureState: YES];
}


// Share image button selected
- (IBAction)shareImage:(id)sender
{
    UIImage *imageToPost = nil;
    
    // Share and save edited image selected from camera roll
    if (NO == self.imageSourceCamera)
    {
        _reloadImage=YES;
        
        // Applying effect to save image to gallery
        UIImage *tempImage = [self fixRotation: _selectedImage];
        
        // Rebuild the effect chain but process at full resolution
        GPUImageFilter *filter = [[NSClassFromString([_filterView.effect getEffectClassName]) alloc] init];
        
        GPUImagePicture *filterImage = [[GPUImagePicture alloc]initWithImage: tempImage];
        [filter forceProcessingAtSizeRespectingAspectRatio:CGSizeMake(tempImage.size.width, tempImage.size.height)];
        [filterImage addTarget: filter];
        
        GPUImagePicture *foregroundPicture = nil;
        NSString *foregroundImageFile = [_filterView.effect getForegroundImageFile];
        if (foregroundImageFile)
        {
            NSString *fxImagePath = [SPEffectInfo getEffectsImagePath];
            NSString *imagePath = [fxImagePath stringByAppendingPathComponent: foregroundImageFile];
            UIImage *inputImage = [UIImage imageNamed:imagePath];
            foregroundPicture = [[GPUImagePicture alloc] initWithImage:inputImage smoothlyScaleOutput:YES];
            [foregroundPicture processImage];
            [foregroundPicture addTarget: filter atTextureLocation: 1];
        }
        
        NSString *amountMethodName = [_backGroundFilter.effect getAmountMethodName];
        if (amountMethodName)
        {
            void (*setAmt)(id, SEL, CGFloat) = (void (*)(id, SEL, CGFloat)) objc_msgSend;
            setAmt(filter, NSSelectorFromString(amountMethodName), _effectAmountSlider.value);
        }

        
        [filterImage processImage];

        _imageSelected=[filter imageFromCurrentlyProcessedOutput];
        
        _imageSelected=[self fixRotation:_imageSelected];
        
        ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
        
        NSData *imageData = [_backGroundFilter.effect saveAsPng] ? UIImagePNGRepresentation(_imageSelected) : UIImageJPEGRepresentation(_imageSelected, 8.0);

        [library writeImageDataToSavedPhotosAlbum: imageData metadata:nil completionBlock:^(NSURL *assetURL, NSError *error2)
         {
             
             if (error2)
             {
                 NSLog(@"ERROR: the image failed to be written");
                 
                 NSString *saveFail;
                 
                 if (error2.code == ALAssetsLibraryAccessUserDeniedError)
                 {
                     saveFail = NSLocalizedString(@"ImageSavePermissionsFail", @"ImageSavePermissionsFail");
                 }
                 else
                 {
                     saveFail = NSLocalizedString(@"ImageSaveFail", @"ImageSaveFail");
                 }
                 
                 //Pop up a notification
                 UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                                 message:saveFail
                                                                delegate:nil
                                                       cancelButtonTitle:@"OK"
                                                       otherButtonTitles:nil];
                 [alert show];
                 
             }
             
         }];
        
        imageToPost = _imageSelected;
    }
    else   // Share an image captured from the camera
    {
        imageToPost = _image;
    }

    [self setActivityIndicatorAnimating:NO];

    NSAssert(imageToPost, @"Attempting to share a nil image imageToPost");
    
    // Post the image to Ostetso
    [Ostetso shareImage: imageToPost];
        
    [self resignFirstResponder];
}


- (IBAction)effectAmountValueChanged:(id)sender
{
    CGFloat effectAmt = _effectAmountSlider.value;
    [self setFilterAmount:effectAmt forFilterView:_filterView];
}


- (void) showGalleryButtonPressed
{
    [Ostetso showGallery];
}

#pragma mark UIGestureRecognizer delegate methods

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer*)gestureRecognizer
{
    if (_capturedImageView.hidden == NO) return NO;    // don't accept gesture if we're previewing a captured image
    
    return YES;
}

- (BOOL) gestureRecognizer : (UIGestureRecognizer *) gestureRecognizer shouldReceiveTouch : (UITouch *) touch
{
    // Don't allow gesture to propogate if the user is touching in the effect button view - there has to be a better way to prevent this!
    CGPoint locInSelView = [touch locationInView:self.view];
    CGRect selViewRect = _effectSelectionView.frame;
    BOOL ptInSelView = CGRectContainsPoint(selViewRect, locInSelView);
    if (ptInSelView) return NO;
    
    
    if ([touch.view isKindOfClass:[UISlider class]] ||
        touch.view == _effectSelectionView)
    {
        // prevent recognizing touches on the slider
        return NO;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer*)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer*)otherGestureRecognizer
{
    return ![gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]] && ![gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]];
}


# pragma mark  Method to check EXIF rotation

- (UIImage *)fixRotation:(UIImage *)image{
    
    if (image.imageOrientation == UIImageOrientationUp) return image;
    CGAffineTransform transform = CGAffineTransformIdentity;
    
    switch (image.imageOrientation) {
        case UIImageOrientationDown:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.width, image.size.height);
            transform = CGAffineTransformRotate(transform, M_PI);
            break;
            
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.width, 0);
            transform = CGAffineTransformRotate(transform, M_PI_2);
            break;
            
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, 0, image.size.height);
            transform = CGAffineTransformRotate(transform, -M_PI_2);
            break;
        case UIImageOrientationUp:
        case UIImageOrientationUpMirrored:
            break;
    }
    
    switch (image.imageOrientation) {
        case UIImageOrientationUpMirrored:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.width, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
            
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.height, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
        case UIImageOrientationUp:
        case UIImageOrientationDown:
        case UIImageOrientationLeft:
        case UIImageOrientationRight:
            break;
    }
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGContextRef ctx = CGBitmapContextCreate( NULL, image.size.width, image.size.height, 8, 0, colorSpace, (CGBitmapInfo)kCGImageAlphaNoneSkipFirst /*kCGBitmapByteOrderDefault*/ );
    
    CGContextConcatCTM(ctx, transform);
    switch (image.imageOrientation) {
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            // Grr...
            CGContextDrawImage(ctx, CGRectMake(0,0,image.size.height,image.size.width), image.CGImage);
            break;
            
        default:
            CGContextDrawImage(ctx, CGRectMake(0,0,image.size.width,image.size.height), image.CGImage);
            break;
    }
    
    // And now we just create a new UIImage from the drawing context
    CGImageRef cgimg = CGBitmapContextCreateImage(ctx);
    UIImage *img = [UIImage imageWithCGImage:cgimg];
    CGContextRelease(ctx);
    CGImageRelease(cgimg);
    return img;
}

@end
