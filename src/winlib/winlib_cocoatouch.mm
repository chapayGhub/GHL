//
//  winlib_cocoatouch.mm
//  SR
//
//  Created by Андрей Куницын on 26.06.11.
//  Copyright 2011 andryblack. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#include <sys/time.h>

#include "../render/opengl/render_opengl.h"

#include "ghl_application.h"
#include "ghl_settings.h"
#include "ghl_system.h"
#include "../ghl_log_impl.h"

#include "../sound/ghl_sound_impl.h"
#include "../vfs/vfs_cocoa.h"
#include "../image/image_decoders.h"

#include <OpenGLES/ES1/gl.h>
#include <OpenGLES/ES1/glext.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/EAGLDrawable.h>
#import <QuartzCore/QuartzCore.h>

static const char* MODULE = "WINLIB";

static GHL::Application* g_application = 0;
static UIInterfaceOrientation g_orientation = UIInterfaceOrientationLandscapeLeft;
static bool g_orientationLocked = false;
static bool g_retina_enabled = false;

#ifndef GHL_NOSOUND
extern GHL::SoundImpl* GHL_CreateSoundCocoa();
#endif

namespace GHL {
	extern UInt32 g_default_renderbuffer;
}

@class WinLibView;

@interface AccelerometerDelegate : NSObject<UIAccelerometerDelegate>
{
	UIAccelerometer* accelerometer;
	float data[3];
}
- (id)init;
- (void)accelerometer:(UIAccelerometer *)accelerometer didAccelerate:(UIAcceleration *)acceleration;
@end

@implementation AccelerometerDelegate

- (id)init
{
	if (self = [super init]) {
		accelerometer = [UIAccelerometer sharedAccelerometer];
		accelerometer.updateInterval = 0.1;
		accelerometer.delegate = self;
	}
	return self;
}

- (float*)get_data
{
	return data;
}

- (void)dealloc
{
	accelerometer.delegate = nil;
	[super dealloc];
}

- (void)accelerometer:(UIAccelerometer *)accelerometer didAccelerate:(UIAcceleration *)acceleration
{
	data[0]=acceleration.x;
	data[1]=acceleration.y;
	data[2]=acceleration.y;
}


@end

class SystemCocoaTouch;

static const size_t max_touches = 10;

@interface WinLibView : UIView<UITextFieldDelegate> {
	EAGLContext*	m_context;
	// The OpenGL ES names for the framebuffer and renderbuffer used to render to this view
    GLuint m_defaultFramebuffer, m_colorRenderbuffer;
	// The pixel dimensions of the CAEAGLLayer
    GLint m_backingWidth;
    GLint m_backingHeight;
	GHL::ImageDecoderImpl* m_imageDecoder;
	GHL::SoundImpl*	m_sound;
	NSString*	m_appName;
	GHL::RenderOpenGL* m_render;
	NSTimer*	m_timer;
	bool	m_loaded;
	::timeval	m_timeval;
	bool	m_active;
	UITextField* m_hiddenInput;
	UITouch* m_touches[max_touches];
}

- (void)prepareOpenGL;
- (EAGLContext*) getContext;
- (void)setActive:(bool) a;
- (bool)loaded;
- (void)showKeyboard;
- (void)hideKeyboard;

@end

@interface WinLibViewController : UIViewController
{
	
}

@end

class SystemCocoaTouch : public GHL::System {
private:
	WinLibViewController* m_controller;
	AccelerometerDelegate* m_accelerometer;
public:
	explicit SystemCocoaTouch(WinLibViewController* controller) : m_controller(controller) {
		m_accelerometer = 0;
	}
	~SystemCocoaTouch() {
		[m_accelerometer release]; 
	}
	virtual void GHL_CALL Exit() {
		///
		LOG_ERROR("Call GHL::System::Exit on iOS disallow");
	}
	
	///
	virtual bool GHL_CALL IsFullscreen() const {
		return true;
	}
	///
	virtual void GHL_CALL SwitchFullscreen(bool fs) {
		/// do nothing
	}
	
	virtual void GHL_CALL SwapBuffers();	
	///
	virtual void GHL_CALL ShowKeyboard();
		
	///
	virtual void GHL_CALL HideKeyboard();
	
	virtual GHL::UInt32  GHL_CALL GetKeyMods() const {
		return 0;
	}
	///
	virtual bool GHL_CALL SetDeviceState( GHL::DeviceState name, void* data); 
	///
	virtual bool GHL_CALL GetDeviceData( GHL::DeviceData name, void* data) {
		if (name==GHL::DEVICE_DATA_ACCELEROMETER) {
			if (!m_accelerometer)
				return false;
			memcpy(data, [m_accelerometer get_data], sizeof(float)*3);
			return true;
		} else if (name==GHL::DEVICE_DATA_VIEW_CONTROLLER) {
			if (data) {
				*((UIViewController**)data) = m_controller;
			}
		}
		return false;
	}
    ///
    virtual void GHL_CALL SetTitle( const char* title ) {
        /// do nothing
    }
};







@implementation WinLibView

+ (Class)layerClass
{
    return [CAEAGLLayer class];
}

- (EAGLContext*) getContext {
	return m_context;
}

- (bool)loaded{
	return m_loaded;
}
- (void)setActive:(bool) a {
	if (m_active!=a) {
		m_active = a;
	}
}

-(id) initWithFrame:(CGRect) rect {
	if (self = [super initWithFrame:rect]) {
		m_appName = (NSString*)[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"];
		m_imageDecoder = 0;
		
		m_active = false;
		
#ifndef GHL_NO_IMAGE_DECODERS
		m_imageDecoder = new GHL::ImageDecoderImpl();		
		g_application->SetImageDecoder(m_imageDecoder);
#endif
		
		// Get the layer
        CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
		
        eaglLayer.opaque = TRUE;
        eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                        [NSNumber numberWithBool:FALSE], kEAGLDrawablePropertyRetainedBacking,
										kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil];
		
		m_context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1];
		
        if (!m_context || ![EAGLContext setCurrentContext:m_context])
        {
            [self release];
            return nil;
        }
		

        if([self respondsToSelector:@selector(setContentScaleFactor:)]){
			if (!g_retina_enabled)
				self.contentScaleFactor = 1.0;
            LOG_VERBOSE("contentScaleFactor:"<<self.contentScaleFactor);
        }
		
		
        // Create default framebuffer object. The backing will be allocated for the current layer in -resizeFromLayer
        glGenFramebuffersOES(1, &m_defaultFramebuffer);
        glGenRenderbuffersOES(1, &m_colorRenderbuffer);
        glBindFramebufferOES(GL_FRAMEBUFFER_OES, m_defaultFramebuffer);
        glBindRenderbufferOES(GL_RENDERBUFFER_OES, m_colorRenderbuffer);
        glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_RENDERBUFFER_OES, m_colorRenderbuffer);
		
		GHL::g_default_renderbuffer = m_colorRenderbuffer;
		
		m_sound = 0;
#ifndef GHL_NO_SOUND
		m_sound = GHL_CreateSoundCocoa();
		if (!m_sound->SoundInit()) {
			delete m_sound;
			m_sound = 0;
		}
		g_application->SetSound(m_sound);
#endif
		
		for (size_t i=0;i<max_touches;i++) {
			m_touches[i] = 0;
		}
		
		m_hiddenInput = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
		m_hiddenInput.delegate = self;
		m_hiddenInput.keyboardType = UIKeyboardTypeASCIICapable;
		m_hiddenInput.returnKeyType = UIReturnKeyDone;
		m_hiddenInput.text = @"*";
		[self addSubview:m_hiddenInput];
		
        [self setAutoresizesSubviews:YES];
        
		if([self respondsToSelector:@selector(setContentScaleFactor:)]){
			if (!g_retina_enabled)
				self.contentScaleFactor = 1.0;
			LOG_VERBOSE("contentScaleFactor:"<<self.contentScaleFactor);
		}
		
		[self prepareOpenGL];
	}
	return self;
}

- (void)layoutSubviews
{
    LOG_VERBOSE( "layoutSubviews" ); 
	if([self respondsToSelector:@selector(setContentScaleFactor:)]){
		if (!g_retina_enabled)
			self.contentScaleFactor = 1.0;
		LOG_VERBOSE("contentScaleFactor:"<<self.contentScaleFactor);
	}

	[EAGLContext setCurrentContext:m_context];
	// Allocate color buffer backing based on the current layer size
    glBindRenderbufferOES(GL_RENDERBUFFER_OES, m_colorRenderbuffer);
    [m_context renderbufferStorage:GL_RENDERBUFFER_OES fromDrawable:(CAEAGLLayer*)self.layer];
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &m_backingWidth);
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &m_backingHeight);
	GHL::g_default_renderbuffer = m_colorRenderbuffer;
	m_render->Resize(m_backingWidth, m_backingHeight);
    if (glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES) != GL_FRAMEBUFFER_COMPLETE_OES)
    {
        LOG_ERROR("Failed to make complete framebuffer object " << glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES));
    }
	
}

- (void)prepareOpenGL {
	LOG_VERBOSE( "prepareOpenGL" ); 
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	[EAGLContext setCurrentContext:m_context];
	int w = [self bounds].size.width;
	int h = [self bounds].size.height;
	if([self respondsToSelector:@selector(setContentScaleFactor:)]){
		if (!g_retina_enabled)
			self.contentScaleFactor = 1.0;
		else {
			w *= self.contentScaleFactor;
			h *= self.contentScaleFactor;
		}
		LOG_VERBOSE("contentScaleFactor:"<<self.contentScaleFactor);
	}
	
	m_render = new GHL::RenderOpenGL(GHL::UInt32(w),
									 GHL::UInt32(h));
	m_render->RenderInit();
	g_application->SetRender(m_render);
	GHL::g_default_renderbuffer = m_colorRenderbuffer;
	if (g_application->Load()) {
		m_timer = [NSTimer scheduledTimerWithTimeInterval: 1.0f/200.0f target:self selector:@selector(timerFireMethod:) userInfo:nil repeats:YES];
		[m_timer fire];
		m_loaded = true;
	}
	::gettimeofday(&m_timeval,0);
	[pool drain];
}

- (void)drawRect:(CGRect)dirtyRect {
    (void)dirtyRect;
	if (m_loaded  && m_active) {
		NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
		::timeval time;
		::gettimeofday(&time,0);
		GHL::UInt32 dt = static_cast<GHL::UInt32>((time.tv_sec - m_timeval.tv_sec)*1000000 + time.tv_usec - m_timeval.tv_usec);
		m_timeval = time;
		[EAGLContext setCurrentContext:m_context];
		GHL::g_default_renderbuffer = m_colorRenderbuffer;
		m_render->ResetRenderState();
		if (g_application->OnFrame(dt)) {
			
		}
        [m_context presentRenderbuffer:GL_RENDERBUFFER_OES];
		[pool drain];
	}
}

- (int)touchNum:(UITouch*)touch {
	for (size_t i=0;i<max_touches;i++) {
		if (m_touches[i]==touch)
			return i;
	}
	return -1;
}


- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
	for (UITouch* touch in touches) {
		CGPoint pos = [touch locationInView:self];
		int touch_num = -1;
		for (size_t i=0;i<max_touches;i++) {
			if (m_touches[i]==0) {
				touch_num = i;
				break;
			}
		}
		if (touch_num<0)
			continue;
		m_touches[touch_num]=touch; /// no retain!!
		GHL::MouseButton btn = GHL::TOUCH_1;
		if (touch_num>0) {
			btn = GHL::MouseButton(GHL::MUTITOUCH_1+touch_num-1);
		}
		g_application->OnMouseDown(btn,pos.x,pos.y);
        //LOG_DEBUG("touchBegan " << touch_num << " : " << pos.x << pos.y );
	}
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
	for (UITouch* touch in touches) {
		CGPoint pos = [touch locationInView:self];
		int touch_num = [self touchNum:touch];
		if (touch_num<0) {
			continue;
		}
		m_touches[touch_num]=0;
		GHL::MouseButton btn = GHL::TOUCH_1;
		if (touch_num>0) {
			btn = GHL::MouseButton(GHL::MUTITOUCH_1+touch_num-1);
		}
		g_application->OnMouseUp(btn,pos.x,pos.y);
        //LOG_DEBUG("touchesEnded " << touch_num << " : " << pos.x << pos.y );
	}
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
	[self touchesEnded:touches withEvent:event];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
	for (UITouch* touch in touches) {
		CGPoint pos = [touch locationInView:self];
		int touch_num = [self touchNum:touch];
		if (touch_num<0) {
			continue;
		}
		GHL::MouseButton btn = GHL::TOUCH_1;
		if (touch_num>0) {
			btn = GHL::MouseButton(GHL::MUTITOUCH_1+touch_num-1);
		}
		g_application->OnMouseMove(btn,pos.x,pos.y);
        //LOG_DEBUG("touchesMoved " << touch_num << " : " << pos.x << pos.y );
	}
}


- (void)timerFireMethod:(NSTimer*)theTimer {
    (void)theTimer;
	if (m_active) {
        [self drawRect:[self bounds]];
	}
}

-(void)showKeyboard {
	[m_hiddenInput becomeFirstResponder];
}

-(void)hideKeyboard {
	[m_hiddenInput resignFirstResponder];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
	//use string here for the text input
	if (string!=nil && [string length]>0) {
		wchar_t wc = [string characterAtIndex:0];
		g_application->OnChar(wc);
	} else {
		g_application->OnKeyDown(GHL::KEY_BACKSPACE);
		g_application->OnKeyUp(GHL::KEY_BACKSPACE);
	}
	/// always have one char
	textField.text = @"*";
	return NO;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	g_application->OnKeyDown(GHL::KEY_ENTER);
	g_application->OnKeyUp(GHL::KEY_ENTER);
	return NO;
}

-(void)dealloc {
	if (m_timer) {
		[m_timer release];
	}
	if (m_render) {
		m_render->RenderDone();
		delete m_render;
		m_render = 0;
	}
	// Tear down GL
    if (m_defaultFramebuffer)
    {
        glDeleteFramebuffersOES(1, &m_defaultFramebuffer);
        m_defaultFramebuffer = 0;
    }
	
    if (m_colorRenderbuffer)
    {
        glDeleteRenderbuffersOES(1, &m_colorRenderbuffer);
        m_colorRenderbuffer = 0;
    }
	
    // Tear down context
    if ([EAGLContext currentContext] == m_context)
        [EAGLContext setCurrentContext:nil];
	
    [m_context release];
    m_context = nil;
	delete m_imageDecoder;
	delete m_sound;

	[super dealloc];
}

@end

@implementation WinLibViewController

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
	if (g_orientation==UIInterfaceOrientationLandscapeRight && !g_orientationLocked) {
		if (orientation==UIInterfaceOrientationLandscapeLeft)
			return YES;
	}
    return orientation == g_orientation ? YES : NO; 
}

- (void)viewWillAppear:(BOOL)animated    // Called when the view is about to made visible. Default does nothing
{
	
}
- (void)viewDidAppear:(BOOL)animated     // Called when the view has been fully transitioned onto the screen. Default does nothing
{
	[(WinLibView*)self.view setActive: true];
}
- (void)viewWillDisappear:(BOOL)animated // Called when the view is dismissed, covered or otherwise hidden. Default does nothing
{
	[(WinLibView*)self.view setActive: false];
}
- (void)viewDidDisappear:(BOOL)animated  // Called after the view was dismissed, covered or otherwise hidden. Default does 
{
	
}
@end

@interface WinLibAppDelegate : NSObject<UIApplicationDelegate> {
	UIWindow* window;
	WinLibView*	view;
	WinLibViewController* controller;
	GHL::VFSCocoaImpl*	m_vfs;
	SystemCocoaTouch*	m_system;
}
@end

@implementation WinLibAppDelegate

- (void)applicationDidFinishLaunching:(UIApplication *)application {
	
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	LOG_INFO("applicationDidFinishLaunching");
    
	m_vfs = new GHL::VFSCocoaImpl();
	g_application->SetVFS(m_vfs);

	CGRect rect = [[UIScreen mainScreen] bounds];
	
	GHL::Settings settings;
	settings.width = rect.size.width;
	settings.height = rect.size.height;
	settings.fullscreen = true;
	
	
	
	g_application->FillSettings(&settings);
	LOG_INFO("application require " << settings.width << "x" << settings.height);
    settings.fullscreen = true;
	
	if ( rect.size.width==320 && rect.size.height==480 ) {
		if (( settings.width >= 480*2 && settings.height >= 320*2 ) ||
			 ( settings.height >= 480*2 && settings.width >= 320*2 ) ) {
			LOG_VERBOSE("Enable retina");
			g_retina_enabled = true;
		}
	}
	
	
	
	if (settings.width > settings.height) {
		g_orientation = UIInterfaceOrientationLandscapeRight;
		settings.width = rect.size.height;
		settings.height = rect.size.width;
        LOG_VERBOSE("UIInterfaceOrientationLandscapeRight");
    } else {
		g_orientation = UIInterfaceOrientationPortrait;
		settings.width = rect.size.width;
		settings.height = rect.size.height;
        LOG_VERBOSE("UIInterfaceOrientationPortrait");
	}
	
	
	/// setup audio session
	AVAudioSession *session = [AVAudioSession sharedInstance];
	[session setCategory:AVAudioSessionCategoryAmbient error:nil];
	
	
	
	controller = [[WinLibViewController alloc] init];
	m_system = new SystemCocoaTouch(controller);
	g_application->SetSystem(m_system);

	window = [[UIWindow alloc] initWithFrame:rect];
    [window setAutoresizesSubviews:YES];
	
	view = [[WinLibView alloc] initWithFrame:CGRectMake(0, 0, settings.width, settings.height)];
	controller.view = view;
	
	g_application->Initialize();
	
	
	NSString *reqSysVer = @"4.0";
	NSString *currSysVer = [[UIDevice currentDevice] systemVersion];
	if ([currSysVer compare:reqSysVer options:NSNumericSearch] != NSOrderedAscending) {
        LOG_INFO("setRootViewController");
		[window setRootViewController:controller];
	} else
	{
		while(window.subviews.count > 0)
			[[window.subviews objectAtIndex:0] removeFromSuperview];
		[window addSubview:controller.view];
	}
	[window setOpaque:YES];
	
	
	[window makeKeyAndVisible];
	
	[pool drain];
}

- (void)applicationWillResignActive:(UIApplication *)application
{
	[EAGLContext setCurrentContext:[view getContext]];
	g_application->OnDeactivated();
	//[view setActive:false];
	//[view drawRect:[view bounds]];
	LOG_INFO("Deactivated");
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
	[EAGLContext setCurrentContext:[view getContext]];
	g_application->OnActivated();
	//[view setActive:true];
	//if ([view loaded]) [view drawRect:[view bounds]];
	LOG_INFO("Activated");
}

- (void)dealloc
{
	delete m_system;
	[super dealloc];
}

@end


void GHL_CALL SystemCocoaTouch::SwapBuffers() {
	//[[m_view getContext] presentRenderbuffer:GL_RENDERBUFFER_OES];	
}

void GHL_CALL SystemCocoaTouch::ShowKeyboard() {
	[(WinLibView*)m_controller.view showKeyboard];
}

void GHL_CALL SystemCocoaTouch::HideKeyboard() {
	[(WinLibView*)m_controller.view hideKeyboard];
}

bool GHL_CALL SystemCocoaTouch::SetDeviceState( GHL::DeviceState name, void* data) {
	if (!data) return false;
	if (name==GHL::DEVICE_STATE_ACCELEROMETER_ENABLED) {
		bool* state = (bool*)data;
		if (*state && !m_accelerometer) {
			m_accelerometer = [[AccelerometerDelegate alloc] init];
		} else if (!*state && m_accelerometer) {
			[m_accelerometer release];
			m_accelerometer = nil;
		}
		return true;
	} else if (name==GHL::DEVICE_STATE_ORIENTATION_LOCKED) {
		g_orientationLocked = *(bool*)data;
		return true;
	} else if (name==GHL::DEVICE_STATE_MULTITOUCH_ENABLED) {
		bool* state = (bool*)data;
		m_controller.view.multipleTouchEnabled = *state ? YES : NO;
		return true;
	} else if (name==GHL::DEVICE_STATR_RETINA_ENABLED) {
		bool* state = (bool*)data;
		g_retina_enabled = *state;
		return true;
	}
	return false;
}

GHL_API void GHL_CALL GHL_Log( GHL::LogLevel level,const char* message) {
   	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    NSLog( @"%@",[NSString stringWithUTF8String:message] );
    [pool release];
}


GHL_API int GHL_CALL GHL_StartApplication( GHL::Application* app , int argc, char** argv) {
    (void)MODULE;
    g_application = app;
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	UIApplicationMain(argc, argv, nil, @"WinLibAppDelegate");
	[pool release];
	return 0;
}