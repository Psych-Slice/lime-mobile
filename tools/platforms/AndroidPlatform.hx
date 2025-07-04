package;

import hxp.ArrayTools;
import hxp.Haxelib;
import hxp.HXML;
import hxp.Log;
import hxp.Path;
import hxp.System;
import lime.tools.AndroidHelper;
import lime.tools.Architecture;
import lime.tools.AssetHelper;
import lime.tools.AssetType;
import lime.tools.CPPHelper;
import lime.tools.DeploymentHelper;
import lime.tools.HXProject;
import lime.tools.Icon;
import lime.tools.IconHelper;
import lime.tools.Orientation;
import lime.tools.PlatformTarget;
import lime.tools.ProjectHelper;
import sys.io.File;
import sys.FileSystem;

class AndroidPlatform extends PlatformTarget
{
	private var deviceID:String;

	public function new(command:String, _project:HXProject, targetFlags:Map<String, String>)
	{
		super(command, _project, targetFlags);

		var defaults = new HXProject();

		defaults.meta =
			{
				title: "MyApplication",
				description: "",
				packageName: "com.example.myapp",
				version: "1.0.0",
				company: "",
				companyUrl: "",
				buildNumber: null,
				companyId: ""
			};

		defaults.app =
			{
				main: "Main",
				file: "MyApplication",
				path: "bin",
				preloader: "",
				swfVersion: 17,
				url: "",
				init: null
			};

		defaults.window =
			{
				width: 800,
				height: 600,
				parameters: "{}",
				background: 0xFFFFFF,
				fps: 30,
				hardware: true,
				display: 0,
				resizable: true,
				borderless: false,
				orientation: Orientation.AUTO,
				vsync: false,
				fullscreen: false,
				allowHighDPI: true,
				alwaysOnTop: false,
				antialiasing: 0,
				allowShaders: true,
				requireShaders: false,
				depthBuffer: true,
				stencilBuffer: true,
				colorDepth: 32,
				maximized: false,
				minimized: false,
				hidden: false,
				title: ""
			};

		if (project.targetFlags.exists("simulator") || project.targetFlags.exists("emulator"))
		{
			defaults.architectures = [Architecture.X64, Architecture.ARM64];
		}
		else
		{
			defaults.architectures = [Architecture.ARMV7, Architecture.ARM64];
		}

		defaults.window.width = 0;
		defaults.window.height = 0;
		defaults.window.fullscreen = true;
		defaults.window.requireShaders = true;

		for (i in 1...project.windows.length)
		{
			defaults.windows.push(defaults.window);
		}

		defaults.merge(project);
		project = defaults;

		for (excludeArchitecture in project.excludeArchitectures)
		{
			project.architectures.remove(excludeArchitecture);
		}

		if (command != "display" && command != "clean")
		{
			// project = project.clone ();

			if (!project.environment.exists("ANDROID_SETUP"))
			{
				Log.error("You need to run \"lime setup android\" before you can use the Android target");
			}

			AndroidHelper.initialize(project);

			if (deviceID == null && project.targetFlags.exists("device"))
			{
				deviceID = project.targetFlags.get("device") + ":5555";
			}
		}

		targetDirectory = Path.combine(project.app.path, project.config.getString("android.output-directory", "android"));
	}

	public override function build():Void
	{
		var destination = targetDirectory + "/bin";
		var hxml = targetDirectory + "/haxe/" + buildType + ".hxml";
		var sourceSet = destination + "/app/src/main";

		if (project.targetFlags.exists("ONLY_ARMV7"))
			project.architectures = [Architecture.ARMV7];
		else if (project.targetFlags.exists("ONLY_ARM64"))
			project.architectures = [Architecture.ARM64];
		else if (project.targetFlags.exists("ONLY_X86"))
			project.architectures = [Architecture.X86];
		else if (project.targetFlags.exists("ONLY_X86_64"))
			project.architectures = [Architecture.X64];

		var hasARM64 = ArrayTools.containsValue(project.architectures, Architecture.ARM64);
		var hasARMV7 = ArrayTools.containsValue(project.architectures, Architecture.ARMV7);
		var hasX64 = ArrayTools.containsValue(project.architectures, Architecture.X64);
		var hasX86 = ArrayTools.containsValue(project.architectures, Architecture.X86);

		var architectures = [];

		if (hasARM64) architectures.push(Architecture.ARM64);
		if (hasARMV7) architectures.push(Architecture.ARMV7);
		if (hasX64) architectures.push(Architecture.X64);
		if (hasX86) architectures.push(Architecture.X86);

		if (architectures.length == 0)
		{
			Log.warn("No architecture selected, defaulting to ARM64.");

			hasARM64 = true;

			architectures.push(Architecture.ARM64);
		}

		for (architecture in architectures)
		{
			var minSDKVer = project.config.getInt("android.minimum-sdk-version", 21);
			var haxeParams = [hxml, "-D", "android", "-D", 'PLATFORM_NUMBER=$minSDKVer'];
			var cppParams = ["-Dandroid", '-DPLATFORM_NUMBER=$minSDKVer'];
			var path = sourceSet + "/jniLibs";
			var suffix = ".so";

			if (architecture == Architecture.ARM64)
			{
				haxeParams.push("-D");
				haxeParams.push("HXCPP_ARM64");
				cppParams.push("-DHXCPP_ARM64");
				path = sourceSet + "/jniLibs/arm64-v8a";
				suffix = "-64.so";
			}
			else if (architecture == Architecture.ARMV7)
			{
				haxeParams.push("-D");
				haxeParams.push("HXCPP_ARMV7");
				cppParams.push("-DHXCPP_ARMV7");
				path = sourceSet + "/jniLibs/armeabi-v7a";
				suffix = "-v7.so";
			}
			else if (architecture == Architecture.X64)
			{
				haxeParams.push("-D");
				haxeParams.push("HXCPP_X86_64");
				cppParams.push("-DHXCPP_X86_64");
				path = sourceSet + "/jniLibs/x86_64";
				suffix = "-x86_64.so";
			}
			else if (architecture == Architecture.X86)
			{
				haxeParams.push("-D");
				haxeParams.push("HXCPP_X86");
				cppParams.push("-DHXCPP_X86");
				path = sourceSet + "/jniLibs/x86";
				suffix = "-x86.so";
			}

			for (ndll in project.ndlls)
			{
				ProjectHelper.copyLibrary(project, ndll, "Android", "lib", suffix, path, project.debug, ".so");
			}

			System.runCommand("", "haxe", haxeParams);

			if (noOutput) return;

			CPPHelper.compile(project, targetDirectory + "/obj", cppParams);

			System.copyIfNewer(targetDirectory + "/obj/libApplicationMain" + (project.debug ? "-debug" : "") + suffix, path + "/libApplicationMain.so");
		}

		if (!hasARM64)
		{
			if (FileSystem.exists(sourceSet + "/jniLibs/arm64-v8a"))
			{
				System.removeDirectory(sourceSet + "/jniLibs/arm64-v8a");
			}
		}

		if (!hasARMV7)
		{
			if (FileSystem.exists(sourceSet + "/jniLibs/armeabi-v7a"))
			{
				System.removeDirectory(sourceSet + "/jniLibs/armeabi-v7a");
			}
		}

		if (!hasX64)
		{
			if (FileSystem.exists(sourceSet + "/jniLibs/x86_64"))
			{
				System.removeDirectory(sourceSet + "/jniLibs/x86_64");
			}
		}

		if (!hasX86)
		{
			if (FileSystem.exists(sourceSet + "/jniLibs/x86"))
			{
				System.removeDirectory(sourceSet + "/jniLibs/x86");
			}
		}

		if (noOutput) return;

		AndroidHelper.build(project, destination);
	}

	public override function clean():Void
	{
		if (FileSystem.exists(targetDirectory))
		{
			System.removeDirectory(targetDirectory);
		}
	}

	public override function deploy():Void
	{
		DeploymentHelper.deploy(project, targetFlags, targetDirectory, "Android");
	}

	public override function display():Void
	{
		if (project.targetFlags.exists("output-file"))
		{
			var build = "-debug";
			if (project.keystore != null)
			{
				build = "-release";
			}

			var outputDirectory = null;
			if (project.config.exists("android.gradle-build-directory"))
			{
				outputDirectory = Path.combine(project.config.getString("android.gradle-build-directory"), project.app.file + "/app/outputs/apk");
			}
			else
			{
				outputDirectory = Path.combine(FileSystem.fullPath(targetDirectory), "bin/app/build/outputs/apk");
			}

			Sys.println(Path.combine(outputDirectory, project.app.file + build + ".apk"));
		}
		else
		{
			Sys.println(getDisplayHXML().toString());
		}
	}

	private function getDisplayHXML():HXML
	{
		var path = targetDirectory + "/haxe/" + buildType + ".hxml";

		// try to use the existing .hxml file. however, if the project file was
		// modified more recently than the .hxml, then the .hxml cannot be
		// considered valid anymore. it may cause errors in editors like vscode.
		if (FileSystem.exists(path)
			&& (project.projectFilePath == null || !FileSystem.exists(project.projectFilePath)
				|| (FileSystem.stat(path).mtime.getTime() > FileSystem.stat(project.projectFilePath).mtime.getTime())))
		{
			return File.getContent(path);
		}
		else
		{
			var context = project.templateContext;
			var hxml = HXML.fromString(context.HAXE_FLAGS);
			hxml.addClassName(context.APP_MAIN);
			hxml.cpp = "_";
			hxml.noOutput = true;
			return hxml;
		}
	}

	public override function install():Void
	{
		var build = "debug";

		if (project.keystore != null)
		{
			build = "release";
		}

		if (project.environment.exists("ANDROID_GRADLE_TASK"))
		{
			var task = project.environment.get("ANDROID_GRADLE_TASK");
			if (task == "assembleDebug")
			{
				build = "debug";
			}
			else
			{
				build = "release";
			}
		}

		var outputDirectory = null;

		if (project.config.exists("android.gradle-build-directory"))
		{
			outputDirectory = Path.combine(project.config.getString("android.gradle-build-directory"), project.app.file + "/app/outputs/apk/" + build);
		}
		else
		{
			outputDirectory = Path.combine(FileSystem.fullPath(targetDirectory), "bin/app/build/outputs/apk/" + build);
		}

		var apkPath = Path.combine(outputDirectory, project.app.file + "-" + build + ".apk");

		deviceID = AndroidHelper.install(project, apkPath, deviceID);
	}

	public override function rebuild():Void
	{
		var arm64 = ArrayTools.containsValue(project.architectures, Architecture.ARM64);
		var armv7 = (command == "rebuild" || ArrayTools.containsValue(project.architectures, Architecture.ARMV7));
		var x64 = ArrayTools.containsValue(project.architectures, Architecture.X64);
		var x86 = (command == "rebuild" || ArrayTools.containsValue(project.architectures, Architecture.X86));

		var commands = [];

		var minSDKVer = 21;
		var platformDefine = '-DPLATFORM_NUMBER=$minSDKVer';

		if (project.targetFlags.exists("ONLY_ARM64"))
		{
			arm64 = true;
			armv7 = x86 = x64 = false;
		}
		else if (project.targetFlags.exists("ONLY_ARMV7"))
		{
			armv7 = true;
			arm64 = x86 = x64 = false;
		}
		else if (project.targetFlags.exists("ONLY_X86_64"))
		{
			x64 = true;
			arm64 = armv7 = x86 = false;
		}
		else if (project.targetFlags.exists("ONLY_X86"))
		{
			x86 = true;
			arm64 = armv7 = x64 = false;
		}

		if (arm64) commands.push(["-Dandroid", "-DHXCPP_ARM64", platformDefine]);
		if (armv7) commands.push(["-Dandroid", "-DHXCPP_ARMV7", platformDefine]);
		if (x64) commands.push(["-Dandroid", "-DHXCPP_X86_64", platformDefine]);
		if (x86) commands.push(["-Dandroid", "-DHXCPP_X86", platformDefine]);

		CPPHelper.rebuild(project, commands);
	}

	public override function run():Void
	{
		AndroidHelper.run(project.meta.packageName + "/" + project.meta.packageName + ".MainActivity", deviceID);
	}

	public override function trace():Void
	{
		AndroidHelper.trace(project, project.debug, deviceID);
	}

	public override function uninstall():Void
	{
		AndroidHelper.uninstall(project.meta.packageName, deviceID);
	}

	public override function update():Void
	{
		AssetHelper.processLibraries(project, targetDirectory);

		// project = project.clone ();

		for (asset in project.assets)
		{
			if (asset.embed && asset.sourcePath == "")
			{
				var path = Path.combine(targetDirectory + "/obj/tmp", asset.targetPath);
				System.mkdir(Path.directory(path));
				AssetHelper.copyAsset(asset, path);
				asset.sourcePath = path;
			}
		}

		// initialize (project);

		var destination = targetDirectory + "/bin";
		var sourceSet = destination + "/app/src/main";
		System.mkdir(sourceSet);
		System.mkdir(sourceSet + "/res/drawable-ldpi/");
		System.mkdir(sourceSet + "/res/drawable-mdpi/");
		System.mkdir(sourceSet + "/res/drawable-hdpi/");
		System.mkdir(sourceSet + "/res/drawable-xhdpi/");

		if (project.targetFlags.exists("xml"))
		{
			project.haxeflags.push("-xml " + targetDirectory + "/types.xml");
		}

		var context = project.templateContext;

		for (asset in project.assets)
		{
			if (asset.embed != true && asset.type != AssetType.TEMPLATE)
			{
				AssetHelper.copyAssetIfNewer(asset, Path.combine(sourceSet + "/assets/", asset.resourceName));
			}
		}

		context.CPP_DIR = targetDirectory + "/obj";
		context.OUTPUT_DIR = targetDirectory;
		context.ANDROID_INSTALL_LOCATION = project.config.getString("android.install-location", "auto");
		context.ANDROID_MINIMUM_SDK_VERSION = project.config.getInt("android.minimum-sdk-version", 21);
		context.ANDROID_TARGET_SDK_VERSION = project.config.getInt("android.target-sdk-version", 35);
		context.ANDROID_EXTENSIONS = project.config.getArrayString("android.extension");
		context.ANDROID_PERMISSIONS = project.config.getArrayString("android.permission", [
			"android.permission.WAKE_LOCK",
			"android.permission.INTERNET",
			"android.permission.VIBRATE",
			"android.permission.ACCESS_NETWORK_STATE",
			"android.permission.ACCESS_MEDIA_LOCATION",
			"android.permission.MANAGE_EXTERNAL_STORAGE",
			"android.permission.READ_MEDIA_IMAGES",
			"android.permission.READ_MEDIA_VIDEO",
			"android.permission.READ_MEDIA_AUDIO",
			"android.permission.READ_MEDIA_VISUAL_USER_SELECTED",
			"android.permission.READ_EXTERNAL_STORAGE",
			"android.permission.WRITE_EXTERNAL_STORAGE"
		]);
		context.ANDROID_GRADLE_VERSION = project.config.getString("android.gradle-version", "8.10.2");
		context.ANDROID_GRADLE_PLUGIN = project.config.getString("android.gradle-plugin", "8.8.0");
		context.ANDROID_USE_ANDROIDX = project.config.getString("android.useAndroidX", "true");
		context.ANDROID_ENABLE_JETIFIER = project.config.getString("android.enableJetifier", "false");
		context.ANDROID_DISPLAY_CUTOUT = project.config.getString("android.layoutInDisplayCutoutMode", "shortEdges");

		context.ANDROID_APPLICATION = project.config.getKeyValueArray("android.application", {
			"android:label": project.meta.title,
			"android:allowBackup": "true",
			"android:theme": "@style/LimeAppMainTheme" + (project.window.fullscreen ? "Fullscreen" : ""),
			"android:hardwareAccelerated": "true",
			"android:allowNativeHeapPointerTagging": context.ANDROID_TARGET_SDK_VERSION >= 30 ? "false" : null,
			"android:requestLegacyExternalStorage": context.ANDROID_TARGET_SDK_VERSION >= 29 ? "true" : null,
			"android:preserveLegacyExternalStorage": context.ANDROID_TARGET_SDK_VERSION >= 30 ? "true" : null,
			"android:largeHeap": "true"
		});
		context.ANDROID_ACTIVITY = project.config.getKeyValueArray("android.activity", {
			"android:name": "MainActivity",
			"android:exported": "true",
			"android:launchMode": "singleTask",
			"android:label": project.meta.title,
			"android:resizeableActivity": '${project.window.resizable}',
			"android:configChanges": project.config.getArrayString("android.configChanges",
				["layoutDirection", "locale", "grammaticalGender", "fontScale", "fontWeightAdjustment", "orientation", "uiMode", "screenLayout", "screenSize", "smallestScreenSize", "keyboard", "keyboardHidden", "navigation"])
				.join("|"),
			"android:screenOrientation": project.window.orientation == PORTRAIT ? "sensorPortrait" : (project.window.orientation == LANDSCAPE ? "sensorLandscape" : null)
		});
		context.ANDROID_ACCEPT_FILE_INTENT = project.config.getArrayString("android.accept-file-intent", []);

		context.SHARE_FILES = project.haxedefs.exists("SHARE_MOBILE_FILES");

		if (!project.environment.exists("ANDROID_SDK") || !project.environment.exists("ANDROID_NDK_ROOT"))
		{
			var command = #if lime "lime" #else "hxp" #end;
			var toolsBase = Type.resolveClass("CommandLineTools");
			if (toolsBase != null) command = Reflect.field(toolsBase, "commandName");

			Log.error("You must define ANDROID_SDK and ANDROID_NDK_ROOT to target Android, please run '" + command + " setup android' first");
			Sys.exit(1);
		}

		if (project.config.exists("android.gradle-build-directory"))
		{
			context.ANDROID_GRADLE_BUILD_DIRECTORY = project.config.getString("android.gradle-build-directory");
		}

		if (project.config.exists("android.build-tools-version"))
		{
			context.ANDROID_BUILD_TOOLS_VERSION = project.config.getString("android.build-tools-version");
		}
		else
		{
			context.ANDROID_BUILD_TOOLS_VERSION = AndroidHelper.getBuildToolsVersion(project);
		}

		context.ANDROID_SDK_ESCAPED = StringTools.replace(context.ENV_ANDROID_SDK, "\\", "\\\\");
		context.ANDROID_NDK_ROOT_ESCAPED = StringTools.replace(context.ENV_ANDROID_NDK_ROOT, "\\", "\\\\");

		// we need to specify ndkVersion in build.gradle, and the value can be
		// found in the NDK's source.properties file
		var ndkSrcPropsPath = Path.join([context.ENV_ANDROID_NDK_ROOT, "source.properties"]);
		if (FileSystem.exists(ndkSrcPropsPath))
		{
			try
			{
				var srcProps = File.getContent(ndkSrcPropsPath);
				var lines = srcProps.split("\n");
				for (line in lines)
				{
					var parts = ~/\s+=\s+/.split(StringTools.trim(line));
					if (parts.length == 2 && parts[0] == "Pkg.Revision")
					{
						context.ANDROID_NDK_VERSION = parts[1];
					}
				}
			}
			catch (e:Dynamic)
			{
			}
		}

		if (Reflect.hasField(context, "KEY_STORE")) context.KEY_STORE = StringTools.replace(context.KEY_STORE, "\\", "\\\\");
		if (Reflect.hasField(context, "KEY_STORE_ALIAS")) context.KEY_STORE_ALIAS = StringTools.replace(context.KEY_STORE_ALIAS, "\\", "\\\\");
		if (Reflect.hasField(context, "KEY_STORE_PASSWORD")) context.KEY_STORE_PASSWORD = StringTools.replace(context.KEY_STORE_PASSWORD, "\\", "\\\\");
		if (Reflect.hasField(context,
			"KEY_STORE_ALIAS_PASSWORD")) context.KEY_STORE_ALIAS_PASSWORD = StringTools.replace(context.KEY_STORE_ALIAS_PASSWORD, "\\", "\\\\");

		var index = 1;
		context.ANDROID_LIBRARY_PROJECTS = [];

		for (dependency in project.dependencies)
		{
			if (dependency.path != ""
				&& FileSystem.exists(dependency.path)
				&& FileSystem.isDirectory(dependency.path)
				&& (FileSystem.exists(Path.combine(dependency.path, "project.properties"))
					|| FileSystem.exists(Path.combine(dependency.path, "build.gradle"))))
			{
				var name = dependency.name;
				if (name == "") name = "project" + index;

				context.ANDROID_LIBRARY_PROJECTS.push(
					{
						name: name,
						index: index,
						path: "deps/" + name,
						source: dependency.path
					});
				index++;
			}
		}

		for (attribute in context.ANDROID_APPLICATION)
		{
			if (attribute.key == "android:icon")
			{
				context.HAS_ICON = true;
				break;
			}
		}

		if (context.HAS_ICON == null)
		{
			var iconTypes = ["ldpi", "mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"];
			var iconSizes = [36, 48, 72, 96, 144, 192];
			var icons = project.icons;

			if (icons.length == 0)
			{
				icons = [new Icon(System.findTemplate(project.templatePaths, "default/icon.svg"))];
			}
			for (i in 0...iconTypes.length)
			{
				// create multiple icons, only set "android:icon" once
				if (IconHelper.createIcon(icons, iconSizes[i], iconSizes[i], sourceSet + "/res/mipmap-" + iconTypes[i] + "-v4/ic_launcher.png")
					&& !context.HAS_ICON)
				{
					context.HAS_ICON = true;
					context.ANDROID_APPLICATION.push({ key: "android:icon", value: "@mipmap/ic_launcher" });
				}
				// make for Oreo users
				IconHelper.createIcon(icons, iconSizes[i], iconSizes[i], sourceSet + "/res/drawable-" + iconTypes[i] + "-v4/icon.png");
			}

			IconHelper.createIcon(icons, 732, 412, sourceSet + "/res/drawable-xhdpi/ouya_icon.png");
		}

		var packageDirectory = project.meta.packageName;
		packageDirectory = sourceSet + "/java/" + packageDirectory.split(".").join("/");
		System.mkdir(packageDirectory);

		for (javaPath in project.javaPaths)
		{
			try
			{
				if (FileSystem.isDirectory(javaPath))
				{
					System.recursiveCopy(javaPath, sourceSet + "/java", context, true);
				}
				else
				{
					if (Path.extension(javaPath) == "jar")
					{
						System.copyIfNewer(javaPath, destination + "/app/libs/" + Path.withoutDirectory(javaPath));
					}
					else
					{
						System.copyIfNewer(javaPath, sourceSet + "/java/" + Path.withoutDirectory(javaPath));
					}
				}
			}
			catch (e:Dynamic) {}

			//	throw"Could not find javaPath " + javaPath +" required by extension.";

			// }
		}

		for (library in cast(context.ANDROID_LIBRARY_PROJECTS, Array<Dynamic>))
		{
			System.recursiveCopy(library.source, destination + "/deps/" + library.name, context, true);
		}

		ProjectHelper.recursiveSmartCopyTemplate(project, "android/template", destination, context);
		System.copyFileTemplate(project.templatePaths, "android/MainActivity.java", packageDirectory + "/MainActivity.java", context);
		ProjectHelper.recursiveSmartCopyTemplate(project, "haxe", targetDirectory + "/haxe", context);
		ProjectHelper.recursiveSmartCopyTemplate(project, "android/hxml", targetDirectory + "/haxe", context);

		for (asset in project.assets)
		{
			if (asset.embed != true && asset.type == AssetType.TEMPLATE)
			{
				var targetPath = Path.combine(destination, asset.targetPath);
				System.mkdir(Path.directory(targetPath));
				AssetHelper.copyAsset(asset, targetPath, context);
			}
		}
	}

	public override function watch():Void
	{
		var hxml = getDisplayHXML();
		var dirs = hxml.getClassPaths(true);

		var outputPath = Path.combine(Sys.getCwd(), project.app.path);
		dirs = dirs.filter(function(dir)
		{
			return (!Path.startsWith(dir, outputPath));
		});

		var command = ProjectHelper.getCurrentCommand();
		System.watch(command, dirs);
	}
}
