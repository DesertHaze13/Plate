#!/usr/bin/env python3
"""Deterministically generate Plate's two app and two widget targets."""
from pathlib import Path
import hashlib, argparse, json, plistlib
parser=argparse.ArgumentParser()
parser.add_argument('--firebase-path',help='Optional local checkout of Firebase SDK 12.0.0 for build verification')
parser.add_argument('--local-only',action='store_true')
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
objects={}
def uid(value): return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
def add(key,value): objects[uid(key)]=value; return uid(key)
def q(value): return json.dumps(str(value))
def array(values): return '('+','.join(values)+')'
refs={}
def ref(path,kind=None):
    path=str(path)
    if path not in refs:
        extension=Path(path).suffix
        kind=kind or {'.swift':'sourcecode.swift','.plist':'text.plist.xml','.entitlements':'text.plist.entitlements','.icon':'folder.iconcomposer.icon','.xcassets':'folder.assetcatalog','.md':'net.daringfireball.markdown'}.get(extension,'text')
        refs[path]=add(path,'{isa = PBXFileReference; lastKnownFileType = '+kind+'; path = '+q(Path(path).name)+'; sourceTree = "<group>"; }')
    return refs[path]
# Build a physical navigator, with icon bundles represented atomically.
allpaths=[p for p in root.rglob('*') if p.is_file() and not any(x.startswith('.') for x in p.relative_to(root).parts) and 'Plate.xcodeproj' not in p.parts and 'node_modules' not in p.parts and not any(x.endswith('.icon') for x in p.relative_to(root).parts)]
allpaths += [root/'Resources/Plate.icon']
for path in allpaths: ref(path.relative_to(root))
def make_group(directory=''):
    prefix=directory+'/' if directory else ''
    files=[p for p in refs if p.startswith(prefix) and '/' not in p[len(prefix):]]
    children=[refs[p] for p in sorted(files)]
    dirs=sorted({p[len(prefix):].split('/')[0] for p in refs if p.startswith(prefix) and '/' in p[len(prefix):]})
    for d in dirs: children.append(make_group(prefix+d))
    if not directory: children.append(uid('products'))
    return add('group:'+directory,'{isa = PBXGroup; '+('path = '+q(Path(directory).name)+'; ' if directory else '')+'sourceTree = "<group>"; children = '+array(children)+'; }')
local=add('core','{isa = XCLocalSwiftPackageReference; relativePath = .; }')
if not args.local_only:
    google=add('google', '{isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/google/GoogleSignIn-iOS.git"; requirement = {kind = exactVersion; version = 8.0.0; }; }')
    firebase=add('firebase',('{isa = XCLocalSwiftPackageReference; relativePath = '+q(args.firebase_path)+'; }') if args.firebase_path else '{isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/firebase/firebase-ios-sdk.git"; requirement = {kind = exactVersion; version = 12.0.0; }; }')
products=[]; target_ids=[]
shared=sorted(str(p.relative_to(root)) for folder in ['Services','Features'] for p in (root/'Sources/Shared'/folder).glob('*.swift'))
for platform in ['iOS','macOS']:
    for widget in [True,False]:
        name=('PlateWidgetsIOS' if platform=='iOS' else 'PlateWidgetsMac') if widget else ('Plate' if platform=='iOS' else 'PlateMac')
        product_type='com.apple.product-type.app-extension' if widget else 'com.apple.product-type.application'
        extension='appex' if widget else 'app'
        product=add(name+'app','{isa = PBXFileReference; explicitFileType = '+('"wrapper.app-extension"' if widget else 'wrapper.application')+'; path = '+q(name+'.'+extension)+'; sourceTree = BUILT_PRODUCTS_DIR; }'); products.append(product)
        sources=['Sources/Widgets/PlateWidgets.swift','Sources/Shared/Services/PlateIntents.swift'] if widget else shared+[f'Sources/{platform}/App/PlateApp.swift']
        builds=[add(name+p,'{isa = PBXBuildFile; fileRef = '+refs[p]+'; }') for p in sources]
        sp=add(name+'sources','{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = '+array(builds)+'; runOnlyForDeploymentPostprocessing = 0; }')
        package_deps=[]; framework_builds=[]
        dependencies=['PlateCore']+([] if widget or args.local_only else ['FirebaseCore','FirebaseAuth','FirebaseFirestore','FirebaseStorage','FirebaseAI','FirebaseAppCheck','GoogleSignIn'])
        for dep in dependencies:
            d=add(name+dep,'{isa = XCSwiftPackageProductDependency; package = '+(local if dep=='PlateCore' else google if dep=='GoogleSignIn' else firebase)+'; productName = '+dep+'; }');package_deps.append(d)
            framework_builds.append(add(name+dep+'build','{isa = PBXBuildFile; productRef = '+d+'; }'))
        fp=add(name+'frameworks','{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = '+array(framework_builds)+'; runOnlyForDeploymentPostprocessing = 0; }')
        resources=[]
        if not widget:
            resourcepaths=['Resources/Plate.icon']
            config=f'Resources/{platform}/GoogleService-Info.plist'
            if config in refs: resourcepaths.append(config)
            for path in resourcepaths: resources.append(add(name+path,'{isa = PBXBuildFile; fileRef = '+refs[path]+'; }'))
        rp=add(name+'resourcephase','{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = '+array(resources)+'; runOnlyForDeploymentPostprocessing = 0; }')
        phases=[sp,fp,rp]; targetdeps=[]
        if not widget:
            child='PlateWidgetsIOS' if platform=='iOS' else 'PlateWidgetsMac'
            embedbuild=add(name+'embedwidget','{isa = PBXBuildFile; fileRef = '+uid(child+'app')+'; settings = {ATTRIBUTES = (RemoveHeadersOnCopy); }; }')
            embed=add(name+'embedphase','{isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = ('+embedbuild+'); name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0; }');phases.append(embed)
            proxy=add(name+'proxy','{isa = PBXContainerItemProxy; containerPortal = '+uid('project')+'; proxyType = 1; remoteGlobalIDString = '+uid(child+'target')+'; remoteInfo = '+child+'; }')
            targetdeps.append(add(name+'dependency','{isa = PBXTargetDependency; target = '+uid(child+'target')+'; targetProxy = '+proxy+'; }'))
        configs=[]
        for mode in ['Debug','Release']:
            settings={'PRODUCT_NAME':name,'PRODUCT_BUNDLE_IDENTIFIER':'com.dony.plate'+('.widgets' if widget else ''),'SWIFT_VERSION':'6.0','SWIFT_STRICT_CONCURRENCY':'complete','CODE_SIGN_STYLE':'Automatic','DEVELOPMENT_TEAM':'7388ZR99UP','MARKETING_VERSION':'1.0.0','CURRENT_PROJECT_VERSION':'12','ENABLE_HARDENED_RUNTIME':'YES','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O','ONLY_ACTIVE_ARCH':'YES' if mode=='Debug' else 'NO','SWIFT_EMIT_LOC_STRINGS':'YES','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks'+(' @executable_path/../../Frameworks' if widget else ''),'CODE_SIGN_ENTITLEMENTS':f'Resources/{platform}/'+('Widgets.entitlements' if widget else 'Plate.entitlements')}
            if mode=='Debug': settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG $(inherited)'
            if platform=='iOS': settings.update({'SDKROOT':'iphoneos','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','TARGETED_DEVICE_FAMILY':'1,2','IPHONEOS_DEPLOYMENT_TARGET':'26.0','SUPPORTS_MACCATALYST':'NO'})
            else: settings.update({'SDKROOT':'macosx','MACOSX_DEPLOYMENT_TARGET':'26.0'})
            if widget: settings.update({'GENERATE_INFOPLIST_FILE':'NO','INFOPLIST_FILE':'Resources/Widgets/Info.plist','SKIP_INSTALL':'YES','APPLICATION_EXTENSION_API_ONLY':'YES'})
            else: settings.update({'GENERATE_INFOPLIST_FILE':'YES','INFOPLIST_FILE':'Resources/Common/Info.plist','INFOPLIST_KEY_CFBundleDisplayName':'Plate','ASSETCATALOG_COMPILER_APPICON_NAME':'Plate','INFOPLIST_KEY_NSCameraUsageDescription':'Take food and nutrition-label photos to log your meals.','INFOPLIST_KEY_NSHealthShareUsageDescription':'Read your body-weight trend and active energy with your permission.','INFOPLIST_KEY_NSHealthUpdateUsageDescription':'Save the dietary energy and macros from meals you log.','INFOPLIST_KEY_UILaunchScreen_Generation':'YES','INFOPLIST_KEY_UIApplicationSceneManifest_Generation':'YES','INFOPLIST_KEY_LSApplicationCategoryType':'public.app-category.healthcare-fitness','INFOPLIST_KEY_ITSAppUsesNonExemptEncryption':'NO'})
            configs.append(add(name+mode,'{isa = XCBuildConfiguration; name = '+mode+'; buildSettings = {'+' '.join(k+' = '+q(v)+';' for k,v in settings.items())+'}; }'))
        cl=add(name+'configlist','{isa = XCConfigurationList; buildConfigurations = '+array(configs)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }')
        tid=add(name+'target','{isa = PBXNativeTarget; name = '+name+'; productName = '+name+'; productReference = '+product+'; productType = '+q(product_type)+'; buildConfigurationList = '+cl+'; buildPhases = '+array(phases)+'; buildRules = (); dependencies = '+array(targetdeps)+'; packageProductDependencies = '+array(package_deps)+'; }');target_ids.append(tid)
add('products','{isa = PBXGroup; name = Products; sourceTree = "<group>"; children = '+array(products)+'; }')
main=make_group()
configs=[add('project'+mode,'{isa = XCBuildConfiguration; name = '+mode+'; buildSettings = {CLANG_ENABLE_MODULES = YES; }; }') for mode in ['Debug','Release']]
cl=add('projectconfigs','{isa = XCConfigurationList; buildConfigurations = '+array(configs)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }')
project=add('project','{isa = PBXProject; attributes = {LastUpgradeCheck = 2700; }; buildConfigurationList = '+cl+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en,Base); mainGroup = '+main+'; productRefGroup = '+uid('products')+'; projectDirPath = ""; projectRoot = ""; targets = '+array(target_ids)+'; packageReferences = '+array([local]+([] if args.local_only else [firebase,google]))+'; }')
projectdir=root/'Plate.xcodeproj';projectdir.mkdir(exist_ok=True)
(projectdir/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 60; objects = {\n'+'\n'.join(k+' = '+v+';' for k,v in objects.items())+'\n}; rootObject = '+project+'; }\n')
for name in ['Plate','PlateMac']:
    scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(name+'target')}" BuildableName="{name}.app" BlueprintName="{name}" ReferencedContainer="container:Plate.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(name+'target')}" BuildableName="{name}.app" BlueprintName="{name}" ReferencedContainer="container:Plate.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>'''
    p=projectdir/'xcshareddata/xcschemes'/f'{name}.xcscheme';p.parent.mkdir(parents=True,exist_ok=True);p.write_text(scheme)
