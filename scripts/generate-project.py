#!/usr/bin/env python3
"""Повторяемая генерация Xcode app/test проекта и ресурсов лицензий."""
from pathlib import Path
import hashlib
root=Path(__file__).resolve().parents[1]
def uid(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
objects=[]
def obj(name,body): objects.append(f'{uid(name)} = {{ {body} }};'); return uid(name)
def ref(name):return uid(name)
def array(items):return '('+','.join(items)+',)'
app_sources=sorted([*root.glob('App/*.swift'),*root.glob('Features/**/*.swift'),*root.glob('Core/DesignSystem/*.swift')])
test_sources=sorted([*root.glob('Tests/Unit/*.swift'), *root.glob('Tests/App/*.swift')])
file_ids=[];app_build=[];test_build=[]
for p in app_sources+test_sources:
 s=p.relative_to(root).as_posix();f=obj(s,f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{s}"; sourceTree = SOURCE_ROOT;');file_ids.append(f)
 b=obj('build:'+s,f'isa = PBXBuildFile; fileRef = {f};');(test_build if p in test_sources else app_build).append(b)
# Проверяем модели приложения с изолированными зависимостями без TCC и устройств.
for s in ['Features/Audio/AudioSessionModel.swift', 'Features/Audio/NativeAudioCapture.swift', 'Features/Meetings/ConversationModel.swift', 'Features/Notes/NotesModel.swift', 'Features/Overlay/GlobalHotkeyService.swift', 'Features/Overlay/OverlayPreferences.swift', 'Features/ScreenCapture/ImagePreparation.swift', 'Features/ScreenCapture/NativeScreenCapture.swift', 'Features/Transcription/TranscriptionModel.swift']:
 test_build.append(obj('test-support:'+s, f'isa = PBXBuildFile; fileRef = {ref(s)};'))
app=obj('app', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = MaxInterviewCopilot.app; sourceTree = BUILT_PRODUCTS_DIR;')
test=obj('test', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = CopilotCoreTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
license_ref=obj('licenses', 'isa = PBXFileReference; lastKnownFileType = folder; path = Resources/Licenses; sourceTree = SOURCE_ROOT;')
file_ids.append(license_ref)
products=obj('products',f'isa = PBXGroup; children = {array([app,test])}; name = Products; sourceTree = "<group>";')
group=obj('group',f'isa = PBXGroup; children = {array(file_ids+[products])}; sourceTree = "<group>";')
package=obj('package','isa = XCLocalSwiftPackageReference; relativePath = .;')
for kind,builds,product,ptype in [('application',app_build,app,'com.apple.product-type.application'),('tests',test_build,test,'com.apple.product-type.bundle.unit-test')]:
 dep=obj(kind+'dep',f'isa = XCSwiftPackageProductDependency; package = {package}; productName = CopilotCore;')
 lib=obj(kind+'lib',f'isa = PBXBuildFile; productRef = {dep};')
 phase=obj(kind+'sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(builds)}; runOnlyForDeploymentPostprocessing = 0;')
 frameworks=obj(kind+'frameworks',f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {array([lib])}; runOnlyForDeploymentPostprocessing = 0;')
 phases=[phase,frameworks]
 if kind=='application':
  license_build=obj('licensesbuild',f'isa = PBXBuildFile; fileRef = {license_ref};')
  resources=obj('appresources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {array([license_build])}; runOnlyForDeploymentPostprocessing = 0;')
  phases.append(resources)
 configs=[]
 for config in ['Debug','Release']:
  settings='SWIFT_VERSION = 6.0; SWIFT_STRICT_CONCURRENCY = complete; SWIFT_TREAT_WARNINGS_AS_ERRORS = YES; MACOSX_DEPLOYMENT_TARGET = 15.0; SDKROOT = macosx; CODE_SIGN_STYLE = Manual; CODE_SIGN_IDENTITY = "-"; PRODUCT_NAME = "$(TARGET_NAME)"; '
  if config=='Debug': settings+='ONLY_ACTIVE_ARCH = YES; '
  settings+='SWIFT_OPTIMIZATION_LEVEL = "'+('-Onone' if config=='Debug' else '-O')+'"; '
  if kind=='application': settings+='INFOPLIST_FILE = Resources/Info.plist; PRODUCT_BUNDLE_IDENTIFIER = dev.maxmashevsky.MaxInterviewCopilot; ENABLE_HARDENED_RUNTIME = YES; '
  else: settings+='GENERATE_INFOPLIST_FILE = YES; PRODUCT_BUNDLE_IDENTIFIER = dev.maxmashevsky.MaxInterviewCopilot.tests; '
  configs.append(obj(kind+config,f'isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = {config};'))
 cl=obj(kind+'configs',f'isa = XCConfigurationList; buildConfigurations = {array(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
 obj(kind+'target',f'isa = PBXNativeTarget; buildConfigurationList = {cl}; buildPhases = {array(phases)}; buildRules = (); dependencies = (); name = '+('MaxInterviewCopilot' if kind=='application' else 'CopilotCoreTests')+f'; packageProductDependencies = {array([dep])}; productReference = {product}; productType = "{ptype}";')
configs=[obj('project'+c,f'isa = XCBuildConfiguration; buildSettings = {{ CLANG_ENABLE_MODULES = YES; }}; name = {c};') for c in ['Debug','Release']]
cl=obj('projectconfigs',f'isa = XCConfigurationList; buildConfigurations = {array(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
project=obj('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {cl}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ru; hasScannedForEncodings = 0; knownRegions = (ru,en,Base); mainGroup = {group}; packageReferences = {array([package])}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {array([ref("applicationtarget"),ref("teststarget")])};')
(root/'MaxInterviewCopilot.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {project}; }}\n')
def buildref(kind,name,product):return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref(kind+"target")}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:MaxInterviewCopilot.xcodeproj"/>'
a=buildref('application','MaxInterviewCopilot','MaxInterviewCopilot.app');t=buildref('tests','CopilotCoreTests','CopilotCoreTests.xctest')
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{a}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{t}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{a}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{a}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(root/'MaxInterviewCopilot.xcodeproj/xcshareddata/xcschemes/MaxInterviewCopilot.xcscheme').write_text(scheme)
print('Создан Xcode project: Swift 6, macOS 15, app + XCTest target')
