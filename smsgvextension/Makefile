
PROJECTNAME = SMSGVExtension

TOOLCHAIN:=/toolchain4
SDK:=$(TOOLCHAIN)/sys
IPHONEOSMINVERSION:=40000
DEBUG=DEBUGOFF

#CC:=$(TOOLCHAIN)/pre/bin/arm-apple-darwin9-gcc
CC:=clang -ccc-host-triple arm-apple-darwin9 
CPP:=$(TOOLCHAIN)/pre/bin/arm-apple-darwin9-g++
LD:=$(TOOLCHAIN)/pre/bin/arm-apple-darwin9-gcc

LDFLAGS := -lobjc
LDFLAGS += -framework CoreFoundation 
LDFLAGS += -framework Foundation 
LDFLAGS += -framework UIKit 
//LDFLAGS += -framework CoreGraphics
//LDFLAGS += -framework AVFoundation
//LDFLAGS += -framework AddressBook
//LDFLAGS += -framework AddressBookUI
//LDFLAGS += -framework AudioToolbox
//LDFLAGS += -framework AudioUnit
//LDFLAGS += -framework CFNetwork
//LDFLAGS += -framework CoreAudio
//LDFLAGS += -framework CoreData
//LDFLAGS += -framework CoreFoundation 
LDFLAGS += -framework GraphicsServices
//LDFLAGS += -framework CoreLocation
//LDFLAGS += -framework ExternalAccessory
//LDFLAGS += -framework GameKit
LDFLAGS += -framework IOKit
//LDFLAGS += -framework MapKit
//LDFLAGS += -framework MediaPlayer
//LDFLAGS += -framework MessageUI
//LDFLAGS += -framework MobileCoreServices
//LDFLAGS += -framework OpenAL
//LDFLAGS += -framework OpenGLES
//LDFLAGS += -framework QuartzCore
//LDFLAGS += -framework Security
//LDFLAGS += -framework StoreKit
//LDFLAGS += -framework System
//LDFLAGS += -framework SystemConfiguration
//LDFLAGS += -framework CoreSurface
//LDFLAGS += -framework GraphicsServices
//LDFLAGS += -framework Celestial
//LDFLAGS += -framework WebCore
//LDFLAGS += -framework WebKit
//LDFLAGS += -framework SpringBoardUI
//LDFLAGS += -framework TelephonyUI
//LDFLAGS += -framework JavaScriptCore
//LDFLAGS += -framework PhotoLibrary
LDFLAGS += -framework CoreTelephony

LDFLAGS += -isysroot $(SDK)
LDFLAGS += -F"$(SDK)/System/Library/Frameworks"
LDFLAGS += -F"$(SDK)/System/Library/PrivateFrameworks"
LDFLAGS += -Wl,-dead_strip -all_load -miphoneos-version-min=$(MINIMUMVERSION)
LDFLAGS += -bind_at_load
LDFLAGS += -multiply_defined suppress
//LDFLAGS += -arch=armv6
LDFLAGS += -march=armv6
LDFLAGS += -mcpu=arm1176jzf-s 

CFLAGS += -ObjC -fblocks
CFLAGS += -std=c99 #-Wall 
CFLAGS += -isysroot $(SDK)
CFLAGS += -D__IPHONE_OS_VERSION_MIN_REQUIRED=$(IPHONEOSMINVERSION)
ifeq ($(DEBUG),DEBUGOFF)
CFLAGS += -g0 -O2
else
CFLAGS += -g
CFLAGS += -D$(DEBUG)
endif
CFLAGS += -Wno-attributes -Wno-trigraphs -Wreturn-type -Wunused-variable

BUILDDIR=./build/$(MINIMUMVERSION)
SRCDIR    = .

DIRLIST    := $(SRCDIR:%=%)
SRCS       := $(foreach dir,$(DIRLIST), $(wildcard $(dir)/*.m))
HDRS       := $(foreach dir,$(DIRLIST), $(wildcard $(dir)/*.h))
OBJS       := $(SRCS:.m=.o)

CFLAGS += -I"$(SRCDIR)"

all: $(PROJECTNAME).dylib

$(PROJECTNAME).dylib: $(OBJS) $(HDRS)
	$(LD) -dynamiclib $(LDFLAGS) $(OBJS) -init _$(PROJECTNAME)Initialize -lsubstrate -L. -o $@
	export CODESIGN_ALLOCATE=$(TOOLCHAIN)/pre/bin/arm-apple-darwin9-codesign_allocate; $(TOOLCHAIN)/pre/bin/ldid -S $(PROJECTNAME).dylib

%.o:	%.m
	$(CC) -c $(CFLAGS) $< -o $@

%.o:	%.c
	$(CC) -c $(CFLAGS) $< -o $@

clean:
	rm -f $(OBJS) $(PROJECTNAME).dylib
